import 'package:starlight/domain/entities/connection_state.dart';
import 'package:starlight/domain/entities/device.dart';
import 'package:starlight/domain/entities/device_state.dart';
import 'package:starlight/domain/entities/device_type.dart';

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
  Future<void> sendCommand(String deviceId, DeviceCommand command);

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

/// A command to send to a device.
/// The interpretation is device-type-specific.
class DeviceCommand {
  final String type; // 'power', 'brightness', 'color', 'effect', etc.
  final Map<String, dynamic> parameters;

  const DeviceCommand({
    required this.type,
    required this.parameters,
  });

  factory DeviceCommand.power(bool on) => DeviceCommand(
    type: 'power',
    parameters: {'on': on},
  );

  factory DeviceCommand.brightness(int value) => DeviceCommand(
    type: 'brightness',
    parameters: {'value': value},
  );

  factory DeviceCommand.color(int red, int green, int blue) => DeviceCommand(
    type: 'color',
    parameters: {'red': red, 'green': green, 'blue': blue},
  );

  factory DeviceCommand.colorTemperature(int kelvin) => DeviceCommand(
    type: 'colorTemperature',
    parameters: {'kelvin': kelvin},
  );

  factory DeviceCommand.effect(String name, {Map<String, dynamic>? params}) => DeviceCommand(
    type: 'effect',
    parameters: {'name': name, 'params': params ?? {}},
  );

  factory DeviceCommand.speed(int value) => DeviceCommand(
    type: 'speed',
    parameters: {'value': value},
  );

  factory DeviceCommand.custom(String type, Map<String, dynamic> parameters) => DeviceCommand(
    type: type,
    parameters: parameters,
  );
}