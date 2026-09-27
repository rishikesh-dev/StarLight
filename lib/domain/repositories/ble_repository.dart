import '../entities/ble_device.dart';
import '../entities/connection_state.dart';
import '../entities/debug_state.dart';
import '../entities/light_command.dart';

/// Abstract repository for BLE operations.
abstract class BleRepository {
  /// Checks if Bluetooth is enabled.
  Future<bool> isBluetoothEnabled();

  /// Checks if Bluetooth permissions are granted.
  Future<bool> hasPermissions();

  /// Requests BLE permissions.
  Future<bool> requestPermissions();

  /// Starts scanning for BLE devices.
  Stream<List<BleDevice>> scanDevices();

  /// Stops the current scan.
  Future<void> stopScan();

  /// Connects to a BLE device.
  /// Returns a stream of [DeviceConnectionState] updates.
  Stream<DeviceConnectionState> connectDevice(String deviceId);

  /// Disconnects from the current device.
  Future<void> disconnectDevice();

  /// Sends a command to the connected device.
  /// Commands are serialized internally.
  Future<void> sendCommand(LightCommand command);

  /// Current connection state.
  Stream<DeviceConnectionState> get connectionState;

  /// Current debug state (last command, last notification, etc.)
  Stream<DebugState> get debugState;

  /// Current RSSI value.
  Future<int?> readRssi();

  /// Checks if currently connected.
  bool get isConnected;
}
