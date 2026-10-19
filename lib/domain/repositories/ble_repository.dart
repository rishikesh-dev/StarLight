// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../entities/ble_device.dart';
import '../entities/connection_state.dart';
import '../entities/debug_state.dart';
import '../entities/device_state_update.dart';
import '../entities/light_command.dart';

/// Abstract repository for BLE operations.
abstract class BleRepository {
  /// Checks if Bluetooth is enabled.
  Future<bool> isBluetoothEnabled();

  /// Waits for the Bluetooth adapter to reach the [BluetoothAdapterState.on]
  /// state. Returns `true` if the adapter is on (either already on or after
  /// waiting up to a default timeout); `false` if it does not become on within
  /// the timeout or turns off.
  Future<bool> waitForAdapterOn();

  /// Stream of Bluetooth adapter state changes.
  Stream<BluetoothAdapterState> get adapterState;

  /// Synchronous snapshot of the current adapter state.
  BluetoothAdapterState get adapterStateNow;

  /// Whether the platform/hardware supports Bluetooth.
  Future<bool> isSupported();

  /// Whether any required permission is permanently denied (the user must
  /// change it in the system app settings).
  Future<bool> isPermanentlyDenied();

  /// Opens the system app settings so a permanently denied permission can be
  /// granted manually.
  Future<void> openSystemSettings();

  /// Requests the adapter to be turned on (Android system dialog). Returns
  /// `true` only once the adapter is confirmed [BluetoothAdapterState.on].
  Future<bool> enableBluetooth();

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

  /// Current state updates from device notifications.
  Stream<DeviceStateUpdate> get stateUpdates;

  /// Current RSSI value.
  Future<int?> readRssi();

  /// Checks if currently connected.
  bool get isConnected;
}
