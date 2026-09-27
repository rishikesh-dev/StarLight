import 'package:starlight/domain/entities/connection_state.dart';
import 'package:starlight/domain/entities/device.dart';
import 'package:starlight/domain/entities/device_state.dart';
import 'package:starlight/domain/repositories/device_repository.dart';

/// Abstract adapter for a specific device type/transport.
/// Each device type (StarLight, SmartPlug, etc.) implements this interface.
abstract class DeviceAdapter {
  /// The type of device this adapter handles.
  String get deviceTypeId;

  /// The transport this adapter uses (ble, wifi, mqtt, matter, etc.)
  String get transport;

  /// Creates a device instance from discovery data.
  Device createDevice({
    required String id,
    required String name,
    required String address,
    Map<String, dynamic> metadata = const {},
  });

  /// Connects to the device.
  /// Returns a stream of connection state updates.
  Stream<DeviceConnectionState> connect(Device device);

  /// Disconnects from the device.
  Future<void> disconnect(Device device);

  /// Sends a command to the device.
  Future<void> sendCommand(Device device, DeviceCommand command);

  /// Reads the current state of the device.
  Future<DeviceState> readState(Device device);

  /// Whether this adapter can handle the given device.
  bool canHandle(Device device);
}