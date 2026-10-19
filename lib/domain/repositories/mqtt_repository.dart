// SPDX-License-Identifier: Apache-2.0

import '../entities/command_result.dart';
import '../entities/device_command.dart';
import '../entities/device_event.dart';
import '../entities/mqtt_config.dart';
import '../entities/network_device.dart';

/// Abstract repository for MQTT device operations.
abstract class MqttRepository {
  /// Updates the MQTT broker configuration.
  Future<void> updateMqttConfig(MqttConfig config);

  /// Gets the current MQTT configuration.
  MqttConfig getMqttConfig();

  /// Publishes a command to the MQTT broker.
  Future<CommandResult> publishCommand(String deviceId, DeviceCommand command);

  /// Reads the current state of an MQTT device by its clientID.
  Future<NetworkDevice?> readState(String deviceId);

  /// Updates device state from an MQTT message.
  void updateDeviceFromMessage(String clientId, Map<String, dynamic> payload);

  /// Gets all known MQTT devices.
  Future<List<NetworkDevice>> getMqttDevices();

  /// Adds a new MQTT device to the registry.
  Future<void> addMqttDevice(String clientId, String brokerClientId);

  /// Removes an MQTT device from the registry.
  Future<void> removeMqttDevice(String clientId);

  /// Gets all known network devices (WLED + MQTT).
  Future<List<NetworkDevice>> getDevices();

  /// Gets a specific device by ID.
  Future<NetworkDevice?> getDevice(String deviceId);

  /// Updates a device's online status based on MQTT connectivity.
  void updateDeviceOnlineStatus(String deviceId, bool isOnline);

  /// Current event stream for MQTT devices.
  Stream<DeviceEvent> get events;
}
