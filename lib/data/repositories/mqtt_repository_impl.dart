// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:starlight/domain/entities/command_result.dart';
import 'package:starlight/domain/entities/device_capability.dart';
import 'package:starlight/domain/entities/device_command.dart';
import 'package:starlight/domain/entities/device_event.dart';
import 'package:starlight/domain/entities/device_type.dart';
import 'package:starlight/domain/entities/mqtt_config.dart';
import 'package:starlight/domain/entities/network_device.dart';
import 'package:starlight/domain/entities/rgb_color.dart';
import 'package:starlight/domain/repositories/mqtt_repository.dart';

/// Repository implementation for MQTT devices.
///
/// Wraps MQTT subscription/publish for network-controlled devices.
class MqttRepositoryImpl implements MqttRepository {
  MqttConfig _config;
  final Map<String, String> _clientIds = {};
  final StreamController<DeviceEvent> _eventsController =
      StreamController<DeviceEvent>.broadcast();
  final Map<String, NetworkDevice> _devices = {};

  MqttRepositoryImpl(this._config);

  @override
  Stream<DeviceEvent> get events => _eventsController.stream;

  @override
  Future<void> updateMqttConfig(MqttConfig config) async {
    _config = config;
  }

  @override
  MqttConfig getMqttConfig() => _config;

  @override
  Future<CommandResult> publishCommand(
    String deviceId,
    DeviceCommand command,
  ) async {
    // Parse payload based on topic
    final payload = _commandToPayload(command);

    if (payload == null) {
      return CommandResult.failure(
        'invalid_command',
        'Cannot convert command to payload',
      );
    }

    try {
      // In a real implementation, we'd publish to the MQTT broker
      // Here we just simulate success
      await Future<void>.delayed(Duration.zero);
      _emitEvent(
        DeviceEvent(
          deviceId: deviceId,
          kind: DeviceEventKind.stateUpdated,
          timestamp: DateTime.now(),
          data: {'command': command.type},
        ),
      );
      return CommandResult.ok();
    } catch (e) {
      return CommandResult.failure('publish_failed', e.toString());
    }
  }

  String? _commandToPayload(DeviceCommand command) {
    switch (command.type) {
      case 'power':
        if (command.parameters['on'] == true) return 'ON';
        return 'OFF';
      case 'brightness':
        return command.parameters['value'].toString();
      case 'color':
        final red = command.parameters['red'] as int;
        final green = command.parameters['green'] as int;
        final blue = command.parameters['blue'] as int;
        return RGBColor(red, green, blue).toHexStr();
      case 'effect':
        return 'FX=${command.parameters['name']}';
      default:
        return null;
    }
  }

  @override
  void updateDeviceFromMessage(String clientId, Map<String, dynamic> payload) {
    // TODO: Implement MQTT message handling for device state updates
  }

  @override
  Future<NetworkDevice?> readState(String deviceId) async {
    final device = _devices[deviceId];
    if (device != null) return device;

    // If offline, return cached state
    return _devices.values.firstWhere(
      (d) => d.id == deviceId,
      orElse: () => NetworkDevice(
        id: deviceId,
        name: 'Unknown',
        type: DeviceType.light,
        address: '',
        capabilities: [],
        connectionState: NetworkConnectionState.unreachable,
        isOn: false,
      ),
    );
  }

  @override
  void updateDeviceOnlineStatus(String deviceId, bool isOnline) {
    final device = _devices[deviceId];
    if (device == null) {
      final newDevice = NetworkDevice(
        id: deviceId,
        name: isOnline ? 'MQTT Device' : 'Offline Device',
        type: DeviceType.light,
        address: _config.clientId,
        capabilities: [DeviceCapability.power, DeviceCapability.brightness],
        connectionState: isOnline
            ? NetworkConnectionState.connected
            : NetworkConnectionState.unreachable,
        isOn: isOnFromOnline(isOnline),
        lastSeen: isOnline ? DateTime.now() : null,
      );
      _devices[deviceId] = newDevice;
      _emitEvent(
        DeviceEvent(
          deviceId: deviceId,
          kind: isOnline
              ? DeviceEventKind.connected
              : DeviceEventKind.disconnected,
          timestamp: DateTime.now(),
        ),
      );
      return;
    }

    if (device.connectionState !=
        (isOnline
            ? NetworkConnectionState.connected
            : NetworkConnectionState.unreachable)) {
      _devices[deviceId] = device.copyWith(
        connectionState: isOnline
            ? NetworkConnectionState.connected
            : NetworkConnectionState.unreachable,
        lastSeen: isOnline ? DateTime.now() : device.lastSeen,
      );
      _emitEvent(
        DeviceEvent(
          deviceId: deviceId,
          kind: isOnline
              ? DeviceEventKind.connected
              : DeviceEventKind.disconnected,
          timestamp: DateTime.now(),
        ),
      );
    }
  }

  bool isOnFromOnline(bool online) => online; // Simplified

  @override
  Future<List<NetworkDevice>> getMqttDevices() async {
    return List.from(_devices.values);
  }

  @override
  Future<void> addMqttDevice(String clientId, String brokerClientId) async {
    _clientIds[clientId] = brokerClientId;
    // Create device entry
    final device = NetworkDevice(
      id: clientId,
      name: 'MQTT Device ($brokerClientId)',
      type: DeviceType.light,
      address: brokerClientId,
      capabilities: [DeviceCapability.power, DeviceCapability.brightness],
      connectionState: NetworkConnectionState.connected,
      isOn: false,
    );
    _devices[clientId] = device;
    await _saveDevices();
  }

  @override
  Future<void> removeMqttDevice(String clientId) async {
    _devices.remove(clientId);
    _clientIds.remove(clientId);
    await _saveDevices();
  }

  @override
  Future<List<NetworkDevice>> getDevices() async {
    if (_devices.isEmpty) {
      await _loadDevices();
    }
    return List.from(_devices.values);
  }

  @override
  Future<NetworkDevice?> getDevice(String deviceId) async {
    await _loadDevices();
    return _devices[deviceId];
  }

  Future<void> _loadDevices() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString('mqtt_devices');
    if (json == null) return;

    final decoded = jsonDecode(json) as List<dynamic>;
    for (final item in decoded) {
      final map = item as Map<String, dynamic>;
      final device = NetworkDevice.fromMap(map);
      _devices[device.id] = device;
    }
  }

  Future<void> _saveDevices() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'mqtt_devices',
      jsonEncode(_devices.values.map((d) => d.toMap()).toList()),
    );
  }

  void _emitEvent(DeviceEvent event) {
    if (!_eventsController.isClosed) {
      _eventsController.add(event);
    }
  }

  void dispose() {
    _eventsController.close();
  }
}
