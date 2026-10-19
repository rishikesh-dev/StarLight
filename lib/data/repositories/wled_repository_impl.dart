// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:starlight/core/utils/app_logger.dart';
import 'package:starlight/data/adapters/wled_http_adapter.dart';
import 'package:starlight/data/models/wled_snapshot.dart';
import 'package:starlight/data/transport/wled_transport.dart';
import 'package:starlight/domain/entities/command_result.dart';
import 'package:starlight/domain/entities/device_command.dart';
import 'package:starlight/domain/entities/device_event.dart';
import 'package:starlight/domain/entities/device_type.dart';
import 'package:starlight/domain/entities/network_device.dart';
import 'package:starlight/domain/entities/wled_config.dart';
import 'package:starlight/domain/entities/wled_probe.dart';
import 'package:starlight/domain/repositories/wled_repository.dart';

/// [WledRepository] backed by the WLED JSON HTTP API.
///
/// One shared [WledTransport] serves every device (dart:io pools
/// connections per host). Each device's requests are serialized through a
/// per-device task chain so rapid UI input cannot interleave writes; a
/// device that is removed while a request is in flight simply no longer
/// receives its result.
///
/// Persistence: the registry (config + last confirmed state) is stored as
/// one JSON document in SharedPreferences. No secrets are stored — WLED
/// core does not use credentials for the JSON API, and StarLight does not
/// send basic-auth headers (see docs/phase2-m2-wled.md, limitations).
class WledRepositoryImpl implements WledRepository {
  static const String _storageKey = 'starlight_wled_devices_v1';

  final WledTransport _transport;
  final bool _ownsTransport;

  final Map<String, WledConfig> _configs = {};
  final Map<String, NetworkDevice> _devices = {};
  final Map<String, Future<void>> _locks = {};

  final StreamController<DeviceEvent> _events =
      StreamController<DeviceEvent>.broadcast();
  bool _disposed = false;

  WledRepositoryImpl({WledTransport? transport})
    : _transport = transport ?? IoWledTransport(),
      _ownsTransport = transport == null;

  // --- lifecycle ----------------------------------------------------------

  @override
  Stream<DeviceEvent> get events => _events.stream;

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _events.close();
    if (_ownsTransport) _transport.dispose();
  }

  // --- persistence --------------------------------------------------------

  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  @override
  Future<void> loadDevices() async {
    final prefs = await _prefs;
    final json = prefs.getString(_storageKey);
    if (json == null || json.isEmpty) return;
    try {
      final list = jsonDecode(json) as List<dynamic>;
      for (final item in list) {
        final map = Map<String, dynamic>.from(item as Map<dynamic, dynamic>);
        final configRaw = map.remove('config');
        if (configRaw is! Map) continue;
        final config = WledConfig.fromMap(Map<String, dynamic>.from(configRaw));
        if (WledConfig.validateHost(config.host) != null) continue;
        final device = NetworkDevice.fromMap(map);
        // A persisted configuration never implies the device is online:
        // restore as disconnected until a live probe succeeds.
        _configs[device.id] = config;
        _devices[device.id] = device.copyWith(
          connectionState: NetworkConnectionState.disconnected,
        );
      }
      AppLog.info('WLED: restored ${_devices.length} saved device(s)');
    } catch (e) {
      // Corrupt storage must not break startup: log and start empty.
      AppLog.warn('WLED: failed to restore saved devices: $e');
    }
  }

  Future<void> _save() async {
    if (_disposed) return;
    final saved = _devices.entries
        .map(
          (e) => <String, dynamic>{
            ...e.value.toMap(),
            'config': _configs[e.key]?.toMap() ?? const {},
          },
        )
        .toList();
    final prefs = await _prefs;
    await prefs.setString(_storageKey, jsonEncode(saved));
  }

  // --- registry -----------------------------------------------------------

  @override
  Future<List<NetworkDevice>> getWledDevices() async {
    return _devices.values.toList(growable: true);
  }

  @override
  Future<NetworkDevice?> getWledDevice(String deviceId) async {
    return _devices[deviceId];
  }

  @override
  Future<WledProbe> probe({
    required String host,
    required int port,
    required bool useHttps,
    String? name,
    int timeoutSeconds = 5,
  }) async {
    if (_disposed) {
      return const WledProbe.failure('disposed', 'WLED service is stopped');
    }
    final validation = WledConfig.validate(
      host: host,
      port: port,
      timeoutSeconds: timeoutSeconds,
    );
    if (validation != null) {
      return WledProbe.failure('invalid_configuration', validation);
    }
    final config = WledConfig(
      host: host.trim().toLowerCase(),
      port: port,
      useHttps: useHttps,
      timeoutSeconds: timeoutSeconds,
    );
    final adapter = WledHttpAdapter(transport: _transport, config: config);
    try {
      final snapshot = await adapter.fetchSnapshot();
      return WledProbe.success(_deviceFromSnapshot(config, snapshot, name));
    } on WledException catch (e) {
      return WledProbe.failure(e.code, e.message);
    }
  }

  @override
  Future<CommandResult> addDevice(
    WledConfig config,
    NetworkDevice device, {
    String? name,
  }) async {
    for (final existing in _devices.values) {
      if (existing.address == device.address) {
        return CommandResult.failure(
          'duplicate_device',
          '“${existing.name}” is already registered at ${device.address}',
        );
      }
    }
    final stored = name != null && name.trim().isNotEmpty
        ? device.copyWith(name: name.trim())
        : device;
    _configs[stored.id] = config;
    _devices[stored.id] = stored;
    await _save();
    _emitConnection(stored.id, connected: true);
    AppLog.info('WLED: registered ${stored.id} (${stored.name})');
    return CommandResult.ok();
  }

  @override
  Future<void> removeDevice(String deviceId) async {
    _configs.remove(deviceId);
    _devices.remove(deviceId);
    _locks.remove(deviceId);
    await _save();
    _emitConnection(deviceId, connected: false);
    AppLog.info('WLED: removed $deviceId');
  }

  @override
  Future<void> renameDevice(String deviceId, String name) async {
    final device = _devices[deviceId];
    final trimmed = name.trim();
    if (device == null || trimmed.isEmpty) return;
    _devices[deviceId] = device.copyWith(name: trimmed);
    await _save();
  }

  // --- commands ------------------------------------------------------------

  @override
  Future<CommandResult> sendCommand(
    String deviceId,
    DeviceCommand command,
  ) async {
    final config = _configs[deviceId];
    final device = _devices[deviceId];
    if (config == null || device == null) {
      return CommandResult.failure(
        'device_not_found',
        'No WLED device registered as $deviceId',
      );
    }
    final result = await _serialized(deviceId, () async {
      if (!_devices.containsKey(deviceId)) {
        return CommandResult.failure(
          'device_not_found',
          'Device was removed before the command ran',
        );
      }
      final payload = WledPayload.build(
        command,
        segmentBased: _isSegmentBased(device),
        effects: device.supportedEffects,
      );
      if (payload.isRejected) {
        return CommandResult.failure(
          payload.error ?? 'unsupported_command',
          'Command “${command.type}” is not supported by this WLED device',
        );
      }
      final adapter = _adapter(config);
      try {
        final outcome = await adapter.sendUpdate(payload.patch);
        if (outcome.confirmed != null) {
          _applyState(deviceId, outcome.confirmed!);
        } else {
          // Firmware answered {"success":true} without echoing state:
          // read the state back so "success" means the device really
          // reports the change.
          final snapshot = await adapter.fetchSnapshot();
          _applySnapshot(deviceId, snapshot);
        }
        _markReachable(deviceId);
        return const CommandResult.ok();
      } on WledException catch (e) {
        _markUnreachable(deviceId);
        return CommandResult.failure(e.code, e.message);
      }
    });
    return result;
  }

  @override
  Future<NetworkDevice?> readState(String deviceId) async {
    final config = _configs[deviceId];
    if (config == null || !_devices.containsKey(deviceId)) return null;
    return _serialized(deviceId, () async {
      if (!_devices.containsKey(deviceId)) return null;
      final adapter = _adapter(config);
      try {
        final snapshot = await adapter.fetchSnapshot();
        _applySnapshot(deviceId, snapshot);
        _markReachable(deviceId);
        return _devices[deviceId];
      } on WledException catch (e) {
        AppLog.warn('WLED readState $deviceId failed: ${e.code} ${e.message}');
        _markUnreachable(deviceId);
        return null;
      }
    });
  }

  // --- internals -----------------------------------------------------------

  WledHttpAdapter _adapter(WledConfig config) =>
      WledHttpAdapter(transport: _transport, config: config);

  bool _isSegmentBased(NetworkDevice device) =>
      device.metadata['wledFormat'] == 'segments';

  /// Runs [body] after any previously queued operation on the same device
  /// has finished (the WLED docs recommend sequential calls).
  Future<T> _serialized<T>(String deviceId, Future<T> Function() body) {
    final previous = _locks[deviceId] ?? Future<void>.value();
    final task = previous.then((_) => body());
    _locks[deviceId] = task.then((_) {}, onError: (Object _) {});
    return task;
  }

  NetworkDevice _deviceFromSnapshot(
    WledConfig config,
    WledSnapshot snapshot,
    String? name,
  ) {
    final mac = snapshot.info.mac;
    final id = (mac != null && mac.isNotEmpty)
        ? 'wled-$mac'
        : 'wled-${_idHost(config)}';
    final displayName = (name != null && name.trim().isNotEmpty)
        ? name.trim()
        : (snapshot.info.name ?? 'WLED ${config.host}');
    return NetworkDevice(
      id: id,
      name: displayName,
      type: DeviceType.light,
      address: '${config.host}:${config.port}',
      capabilities: WledCapabilities.fromSnapshot(snapshot),
      connectionState: NetworkConnectionState.connected,
      brightness: snapshot.state.brightness,
      color: snapshot.state.color,
      effect: _effectName(snapshot.effects, snapshot.state.effectId),
      isOn: snapshot.state.on,
      ledCount: snapshot.info.ledCount,
      firmwareVersion: snapshot.info.version,
      supportedEffects: snapshot.effects,
      supportedPalettes: snapshot.palettes,
      lastSeen: DateTime.now(),
      metadata: {
        ..._stateMetadata(snapshot.state),
        'wledFormat': snapshot.state.segmentBased ? 'segments' : 'legacy',
        'useHttps': config.useHttps,
      },
    );
  }

  /// Device-confirmed ids that have no first-class NetworkDevice field.
  Map<String, dynamic> _stateMetadata(WledLightState state) => {
    'wledEffectId': state.effectId,
    'wledPaletteId': state.paletteId,
  };

  String _idHost(WledConfig config) {
    // ':' is an illegal character in a UI path segment; keep the id
    // stable and filesystem/route-safe.
    return config.host.replaceAll(':', '-');
  }

  static String? _effectName(List<String> effects, int? id) {
    if (id == null || id < 0 || id >= effects.length) return null;
    final name = effects[id];
    if (name.isEmpty || name == 'RSVD' || name == '-') return null;
    return name;
  }

  void _applySnapshot(String deviceId, WledSnapshot snapshot) {
    final device = _devices[deviceId];
    if (device == null) return; // removed while the request was in flight
    _devices[deviceId] = device.copyWith(
      brightness: snapshot.state.brightness,
      color: snapshot.state.color,
      effect: _effectName(snapshot.effects, snapshot.state.effectId),
      isOn: snapshot.state.on,
      ledCount: snapshot.info.ledCount,
      firmwareVersion: snapshot.info.version,
      supportedEffects: snapshot.effects,
      supportedPalettes: snapshot.palettes,
      connectionState: NetworkConnectionState.connected,
      lastSeen: DateTime.now(),
      metadata: {
        ...device.metadata,
        ..._stateMetadata(snapshot.state),
        'wledFormat': snapshot.state.segmentBased ? 'segments' : 'legacy',
      },
    );
    _emit(
      DeviceEvent(
        deviceId: deviceId,
        kind: DeviceEventKind.stateUpdated,
        timestamp: DateTime.now(),
      ),
    );
  }

  void _applyState(String deviceId, WledLightState confirmed) {
    final device = _devices[deviceId];
    if (device == null) return;
    _devices[deviceId] = device.copyWith(
      brightness: confirmed.brightness,
      color: confirmed.color,
      isOn: confirmed.on,
      connectionState: NetworkConnectionState.connected,
      lastSeen: DateTime.now(),
      metadata: {...device.metadata, ..._stateMetadata(confirmed)},
    );
    _emit(
      DeviceEvent(
        deviceId: deviceId,
        kind: DeviceEventKind.stateUpdated,
        timestamp: DateTime.now(),
      ),
    );
  }

  void _markReachable(String deviceId) {
    final device = _devices[deviceId];
    if (device == null) return;
    if (device.connectionState != NetworkConnectionState.connected) {
      _devices[deviceId] = device.copyWith(
        connectionState: NetworkConnectionState.connected,
        lastSeen: DateTime.now(),
      );
      _emitConnection(deviceId, connected: true);
    } else {
      _devices[deviceId] = device.copyWith(lastSeen: DateTime.now());
    }
  }

  void _markUnreachable(String deviceId) {
    final device = _devices[deviceId];
    if (device == null) return;
    if (device.connectionState != NetworkConnectionState.unreachable) {
      _devices[deviceId] = device.copyWith(
        connectionState: NetworkConnectionState.unreachable,
      );
      _emitConnection(deviceId, connected: false);
    }
  }

  void _emitConnection(String deviceId, {required bool connected}) {
    _emit(
      DeviceEvent.connectionChanged(deviceId: deviceId, connected: connected),
    );
  }

  void _emit(DeviceEvent event) {
    if (!_events.isClosed) _events.add(event);
  }
}
