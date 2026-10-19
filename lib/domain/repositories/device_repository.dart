// SPDX-License-Identifier: Apache-2.0

import 'package:starlight/domain/entities/connection_state.dart';
import 'package:starlight/domain/entities/device.dart';
import 'package:starlight/domain/entities/device_command.dart';
import 'package:starlight/domain/entities/device_event.dart';
import 'package:starlight/domain/entities/device_state.dart';
import 'package:starlight/domain/entities/device_type.dart';
import 'package:starlight/domain/entities/command_result.dart';

/// Re-export the canonical entity definitions so legacy callers that typed
/// `import 'package:starlight/domain/repositories/device_repository.dart';`
/// still get [DeviceCommand] and [CommandResult] without a separate import.
export 'package:starlight/domain/entities/command_result.dart';
export 'package:starlight/domain/entities/device_command.dart';

/// Abstract repository for device operations.
/// Replaces BleRepository with a device-type-agnostic interface.
abstract class DeviceRepository {
  /// Checks if the underlying transport (BLE, WiFi, etc.) is available.
  Future<bool> isTransportAvailable();

  /// Checks if permissions are granted for device communication.
  Future<bool> hasPermissions();

  /// Requests permissions for device communication.
  Future<bool> requestPermissions();

  /// Starts scanning for discoverable devices.
  /// Returns a stream of discovered devices.
  Stream<List<Device>> scanDevices();

  /// Stops the current scan.
  Future<void> stopScan();

  /// Connects to a device.
  /// Returns a stream of connection state updates.
  Stream<DeviceConnectionState> connectDevice(String deviceId);

  /// Disconnects from a device.
  Future<void> disconnectDevice(String deviceId);

  /// Sends a command to a device.
  /// The command format is device-type-specific.
  ///
  /// Never throws for expected device conditions (offline, unknown device,
  /// unsupported command): those are reported explicitly through the
  /// returned [CommandResult] so callers can surface the real outcome.
  Future<CommandResult> sendCommand(String deviceId, DeviceCommand command);

  /// Shared stream of device events (connection, state, errors).
  ///
  /// This is the common event contract for scenes, automations and external
  /// interfaces. See [DeviceEvent].
  Stream<DeviceEvent> get events;

  /// Reads the current state of a device.
  Future<DeviceState> readState(String deviceId);

  /// Gets all known devices (cached + discovered).
  Future<List<Device>> getDevices();

  /// Gets a specific device by ID.
  Future<Device?> getDevice(String deviceId);

  /// Lists devices filtered by type.
  Future<List<Device>> getDevicesByType(DeviceType type);

  /// Lists devices filtered by room.
  Future<List<Device>> getDevicesByRoom(String roomId);

  /// Lists devices that are currently connected.
  Future<List<Device>> getConnectedDevices();

  /// Lists devices that are favorited.
  Future<List<Device>> getFavoriteDevices();

  /// Updates device metadata (name, room, favorite, etc.)
  Future<void> updateDevice(Device device);

  /// Removes a device from the registry.
  Future<void> removeDevice(String deviceId);

  /// Current connection state stream for a device.
  Stream<DeviceConnectionState> connectionState(String deviceId);
}
