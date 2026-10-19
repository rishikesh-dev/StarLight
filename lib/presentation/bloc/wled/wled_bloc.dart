// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:bloc/bloc.dart';

import 'package:starlight/core/utils/app_logger.dart';
import 'package:starlight/domain/entities/command_result.dart';
import 'package:starlight/domain/entities/device_capability.dart';
import 'package:starlight/domain/entities/device_command.dart';
import 'package:starlight/domain/entities/device_event.dart';
import 'package:starlight/domain/entities/network_device.dart';
import 'package:starlight/domain/entities/wled_config.dart';
import 'package:starlight/domain/entities/wled_probe.dart';
import 'package:starlight/domain/repositories/wled_repository.dart';

import 'wled_event.dart';
import 'wled_state.dart';

/// BLoC for WLED (Wi-Fi) devices.
///
/// All network traffic goes through [WledRepository]; this bloc only maps
/// results onto UI state. Command outcomes are reflected only after the
/// repository has confirmed them against the device, so the UI never shows
/// a requested value as if it were the device's state.
class WledBloc extends Bloc<WledEvent, WledState> {
  final WledRepository _repository;
  StreamSubscription<DeviceEvent>? _eventsSub;

  WledBloc(this._repository) : super(WledState.initial()) {
    on<WledDevicesLoad>(_onLoadDevices);
    on<WledConnectionTest>(_onTestConnection);
    on<WledDeviceAdd>(_onAddDevice);
    on<WledDeviceRemove>(_onRemoveDevice);
    on<WledDeviceRename>(_onRenameDevice);
    on<WledDeviceRefresh>(_onRefreshDevice);
    on<WledPower>(_onPower);
    on<WledBrightness>(_onBrightness);
    on<WledColor>(_onColor);
    on<WledEffectSelect>(_onEffect);
    on<WledPaletteSelect>(_onPalette);
    on<WledConnectionSync>(_onConnectionSync);

    // Connection events keep `reachable` in sync when the repository
    // observes a reachability transition outside the bloc's own calls.
    _eventsSub = _repository.events.listen((event) {
      if (event.kind != DeviceEventKind.connected &&
          event.kind != DeviceEventKind.disconnected) {
        return;
      }
      add(
        WledConnectionSync(
          event.deviceId,
          event.kind == DeviceEventKind.connected,
        ),
      );
    });
    AppLog.info('WledBloc initialized');
  }

  @override
  Future<void> close() async {
    await _eventsSub?.cancel();
    AppLog.info('WledBloc closing');
    return super.close();
  }

  // --- events ------------------------------------------------------------

  Future<void> _onLoadDevices(
    WledDevicesLoad event,
    Emitter<WledState> emit,
  ) async {
    emit(state.copyWith(loading: true));
    try {
      final devices = await _repository.getWledDevices();
      final map = <String, WledDeviceInfo>{};
      for (final d in devices) {
        map[d.id] = _toInfo(d, reachable: false);
      }
      emit(state.copyWith(loading: false, devices: map));
      AppLog.info('WledBloc: loaded ${map.length} WLED device(s)');
    } catch (e) {
      AppLog.error('WledBloc: failed to load WLED devices', e);
      emit(state.copyWith(loading: false, lastError: 'Failed to load devices'));
    }
  }

  Future<void> _onTestConnection(
    WledConnectionTest event,
    Emitter<WledState> emit,
  ) async {
    emit(state.copyWith(probeInProgress: true, addInProgress: false));
    try {
      final probe = await _repository.probe(
        host: event.host,
        port: event.port,
        useHttps: event.https,
        name: event.name,
      );
      emit(state.copyWith(probe: _probeInfo(event, probe)));
    } finally {
      emit(state.copyWith(probeInProgress: false));
    }
  }

  Future<void> _onAddDevice(
    WledDeviceAdd event,
    Emitter<WledState> emit,
  ) async {
    emit(state.copyWith(addInProgress: true, probe: null));
    try {
      final probe = await _repository.probe(
        host: event.host,
        port: event.port,
        useHttps: event.https,
        name: event.name,
      );
      if (!probe.ok || probe.device == null) {
        emit(
          state.copyWith(
            probe: WledProbeInfo(
              host: event.host,
              port: event.port,
              https: event.https,
              name: event.name,
              success: false,
              error: probe.message ?? probe.error,
              at: DateTime.now(),
            ),
          ),
        );
        return;
      }
      final probed = probe.device!;
      final result = await _repository.addDevice(
        _configFor(event),
        probed,
        name: event.name,
      );
      if (result.success) {
        // Keep the probe result (the Add view uses device presence to pop);
        // the Add view leaves the screen when the registered device shows up.
        final device = await _repository.getWledDevice(probed.id);
        if (device != null) {
          emit(
            state.replaceDevice(
              _toInfo(device, reachable: true, clearError: true),
            ),
          );
        }
        AppLog.info('WledBloc: added ${probed.id}');
      } else {
        emit(
          state.copyWith(
            probe: WledProbeInfo(
              host: event.host,
              port: event.port,
              https: event.https,
              name: event.name,
              success: false,
              error: result.message ?? result.error,
              at: DateTime.now(),
            ),
          ),
        );
      }
    } finally {
      emit(state.copyWith(addInProgress: false));
    }
  }

  Future<void> _onRemoveDevice(
    WledDeviceRemove event,
    Emitter<WledState> emit,
  ) async {
    await _repository.removeDevice(event.id);
    emit(state.removeDevice(event.id));
    AppLog.info('WledBloc: removed ${event.id}');
  }

  Future<void> _onRenameDevice(
    WledDeviceRename event,
    Emitter<WledState> emit,
  ) async {
    final current = state.device(event.id);
    if (current == null || event.name.trim().isEmpty) return;
    await _repository.renameDevice(event.id, event.name.trim());
    emit(state.replaceDevice(current.copyWith(name: event.name.trim())));
  }

  Future<void> _onRefreshDevice(
    WledDeviceRefresh event,
    Emitter<WledState> emit,
  ) async {
    final current = state.device(event.id);
    if (current == null) return;
    emit(state.replaceDevice(current.copyWith(busy: true, clearError: true)));
    final device = await _repository.readState(event.id);
    if (device == null) {
      emit(
        state.replaceDevice(
          state
              .device(event.id)!
              .copyWith(
                busy: false,
                reachable: false,
                error: 'Could not reach the device',
              ),
        ),
      );
      return;
    }
    emit(
      state.replaceDevice(
        _toInfo(device, reachable: true, clearError: true, busy: false),
      ),
    );
  }

  Future<void> _onPower(WledPower event, Emitter<WledState> emit) =>
      _runCommand(event.id, DeviceCommand.power(event.on), emit);

  Future<void> _onBrightness(WledBrightness event, Emitter<WledState> emit) =>
      _runCommand(event.id, DeviceCommand.brightness(event.value100), emit);

  Future<void> _onColor(WledColor event, Emitter<WledState> emit) =>
      _runCommand(
        event.id,
        DeviceCommand.color(
          event.color.red,
          event.color.green,
          event.color.blue,
        ),
        emit,
      );

  Future<void> _onEffect(
    WledEffectSelect event,
    Emitter<WledState> emit,
  ) async {
    final current = state.device(event.id);
    if (current == null) return;
    await _runCommand(
      event.id,
      DeviceCommand.effect(
        current.effects.elementAt(event.effectId),
        id: event.effectId,
      ),
      emit,
    );
  }

  Future<void> _onPalette(WledPaletteSelect event, Emitter<WledState> emit) =>
      _runCommand(event.id, DeviceCommand.palette(event.paletteId), emit);

  // --- shared command handling -------------------------------------------

  /// Sends [command] for [deviceId]; success means the repository confirmed
  /// the resulting state against the device.
  Future<void> _runCommand(
    String deviceId,
    DeviceCommand command,
    Emitter<WledState> emit,
  ) async {
    final current = state.device(deviceId);
    if (current == null || current.busy) return;
    if (!current.reachable) {
      emit(
        state.replaceDevice(
          current.copyWith(error: 'Device unreachable — tap refresh to retry'),
        ),
      );
      return;
    }
    emit(state.replaceDevice(current.copyWith(busy: true)));
    try {
      final result = await _repository.sendCommand(deviceId, command);
      if (result.success) {
        final device = await _repository.getWledDevice(deviceId);
        if (device != null) {
          emit(
            state.replaceDevice(
              _toInfo(device, reachable: true, clearError: true, busy: false),
            ),
          );
        }
      } else {
        final after = state.device(deviceId);
        emit(
          state.replaceDevice(
            (after ?? current).copyWith(
              busy: false,
              error: _friendlyError(result),
            ),
          ),
        );
      }
    } catch (e) {
      AppLog.error('WledBloc: unexpected command error', e);
      final after = state.device(deviceId);
      emit(
        state.replaceDevice(
          (after ?? current).copyWith(busy: false, error: 'Command failed'),
        ),
      );
    }
  }

  // --- repository events ---------------------------------------------------

  void _onConnectionSync(WledConnectionSync event, Emitter<WledState> emit) {
    final current = state.device(event.deviceId);
    if (current == null || current.reachable == event.reachable) return;
    emit(
      state.replaceDevice(
        current.copyWith(
          reachable: event.reachable,
          error: event.reachable
              ? null
              : (current.error ?? 'Device unreachable'),
        ),
      ),
    );
  }

  // --- mapping -------------------------------------------------------------

  WledProbeInfo _probeInfo(WledConnectionTest event, WledProbe probe) {
    if (probe.ok && probe.device != null) {
      return WledProbeInfo(
        host: event.host,
        port: event.port,
        https: event.https,
        name: event.name,
        success: true,
        version: probe.device!.firmwareVersion,
        ledCount: probe.device!.ledCount,
        reportedName: probe.device!.name,
        at: DateTime.now(),
      );
    }
    return WledProbeInfo(
      host: event.host,
      port: event.port,
      https: event.https,
      name: event.name,
      success: false,
      error: probe.message ?? probe.error,
      at: DateTime.now(),
    );
  }

  WledConfig _configFor(WledDeviceAdd event) => WledConfig(
    host: event.host.trim().toLowerCase(),
    port: event.port,
    useHttps: event.https,
  );

  WledDeviceInfo _toInfo(
    NetworkDevice d, {
    bool reachable = false,
    String? error,
    bool clearError = false,
    bool busy = false,
  }) {
    final (host, port) = _splitAddress(d.address);
    final effects = d.supportedEffects;
    final palettes = d.supportedPalettes;
    final effectId = d.metadata['wledEffectId'] as int?;
    final paletteId = d.metadata['wledPaletteId'] as int?;
    return WledDeviceInfo(
      id: d.id,
      name: d.name,
      address: d.address,
      host: host,
      port: port,
      useHttps: d.metadata['useHttps'] as bool? ?? false,
      reachable: reachable,
      busy: busy,
      error: clearError ? null : error,
      version: d.firmwareVersion,
      ledCount: d.ledCount,
      capabilities: d.capabilities,
      on: d.isOn ?? false,
      brightness255: d.brightness ?? 0,
      color: d.color,
      effectId: effectId,
      effectName: d.effect,
      paletteId: paletteId,
      paletteName: _listName(palettes, paletteId),
      effects: effects,
      palettes: palettes,
      lastSeen: d.lastSeen,
    );
  }

  static String? _listName(List<String> names, int? id) {
    if (id == null || id < 0 || id >= names.length) return null;
    final name = names[id];
    if (name.isEmpty || name == 'RSVD' || name == '-') return null;
    return name;
  }

  static (String, int) _splitAddress(String address) {
    final idx = address.lastIndexOf(':');
    if (idx <= 0) return (address, 80);
    final port = int.tryParse(address.substring(idx + 1)) ?? 80;
    return (address.substring(0, idx), port);
  }

  /// Maps repository error codes to user-facing messages. No stack traces,
  /// no protocol internals.
  static String _friendlyError(CommandResult result) {
    switch (result.error) {
      case 'timeout':
        return 'The device did not respond in time';
      case 'dns_failure':
        return 'Could not resolve the device address';
      case 'connection_refused':
        return 'The device refused the connection';
      case 'network_error':
        return 'The device could not be reached';
      case 'http_error':
        return 'The device returned an error response';
      case 'malformed_json':
        return 'The device returned an unexpected response';
      case 'unsupported_command':
        return 'This control is not supported by the device';
      case 'effect_not_found':
        return 'Effect not found on the device';
      case 'invalid_value':
        return 'The requested value is out of range';
      case 'duplicate_device':
        return result.message ?? 'Device already registered';
      case 'device_not_found':
        return 'Device no longer registered';
      default:
        return result.message ?? 'Command failed';
    }
  }
}

/// Capability helpers for the UI.
class WledUi {
  WledUi._();

  /// Effect ids the UI should offer: everything the device reported except
  /// reserved slots (`RSVD` / `-` / empty), which WLED documents as
  /// "recommended to remove from the UI effect selection".
  static List<int> selectableEffects(WledDeviceInfo device) {
    return [
      for (var i = 0; i < device.effects.length; i++)
        if (device.effects[i].isNotEmpty &&
            device.effects[i] != 'RSVD' &&
            device.effects[i] != '-')
          i,
    ];
  }

  static List<int> selectablePalettes(WledDeviceInfo device) =>
      List<int>.generate(device.palettes.length, (i) => i);

  static bool supports(DeviceCapability capability, WledDeviceInfo device) =>
      device.supports(capability);
}
