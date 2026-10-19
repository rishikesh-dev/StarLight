// SPDX-License-Identifier: Apache-2.0

import 'package:equatable/equatable.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'package:starlight/domain/entities/ble_device.dart';
import 'package:starlight/domain/entities/connection_state.dart';

/// Events for the BLE Bloc.
abstract class BleEvent extends Equatable {
  const BleEvent();

  @override
  List<Object?> get props => [];
}

/// Inspect the Bluetooth adapter on app start and, if it is off, request the
/// system enable-Bluetooth flow once. Idempotent: repeated dispatches while a
/// request is in flight are ignored.
class EnsureBluetoothReady extends BleEvent {
  const EnsureBluetoothReady();
}

/// User-initiated retry of the Bluetooth enable/permission flow.
class RetryBluetooth extends BleEvent {
  const RetryBluetooth();
}

/// Open the system app settings so a permanently denied permission can be
/// granted manually.
class OpenAppSettingsRequested extends BleEvent {
  const OpenAppSettingsRequested();
}

/// Re-check adapter/support state after returning from system settings or on
/// an adapter-state transition. When [state] is provided it is the observed
/// adapter state (avoids re-reading a possibly-stale cached value).
class BluetoothStateRecheck extends BleEvent {
  final BluetoothAdapterState? state;

  const BluetoothStateRecheck([this.state]);

  @override
  List<Object?> get props => [state];
}

/// Request permissions and start scanning.
class StartScan extends BleEvent {
  const StartScan();
}

/// Stop the current scan.
class StopScanRequested extends BleEvent {
  const StopScanRequested();
}

/// Connect to a specific device.
class ConnectToDevice extends BleEvent {
  final String deviceId;
  final String deviceName;

  const ConnectToDevice(this.deviceId, this.deviceName);

  @override
  List<Object?> get props => [deviceId, deviceName];
}

/// Disconnect from the current device.
class DisconnectRequested extends BleEvent {
  const DisconnectRequested();
}

/// Load the previously paired device (if any) so the UI can show its
/// last-known identity and offer a reconnect. Does NOT auto-connect: the user
/// decides when to reconnect.
class LoadPairedDevice extends BleEvent {
  const LoadPairedDevice();
}

/// User-initiated reconnect to the paired device.
class ReconnectRequested extends BleEvent {
  const ReconnectRequested();
}

/// Rename the paired device. The display name is metadata only — the device id
/// (MAC) is unchanged.
class RenameDevice extends BleEvent {
  final String name;

  const RenameDevice(this.name);

  @override
  List<Object?> get props => [name];
}

/// Forget the paired device: disconnect, clear the persisted pairing and drop
/// it from the device registry.
class ForgetDevice extends BleEvent {
  const ForgetDevice();
}

/// Refresh connection state (for reconnect logic).
class RefreshConnection extends BleEvent {}

/// Internal event dispatched when scan results arrive.
class ScanResultReceived extends BleEvent {
  final List<BleDevice> devices;

  const ScanResultReceived(this.devices);

  @override
  List<Object?> get props => [devices];
}

/// Internal event dispatched when connection state changes.
class ConnectionStateChanged extends BleEvent {
  final DeviceConnectionState state;

  const ConnectionStateChanged(this.state);

  @override
  List<Object?> get props => [state];
}

/// Internal event for errors.
class BleErrorOccurred extends BleEvent {
  final String message;

  const BleErrorOccurred(this.message);

  @override
  List<Object?> get props => [message];
}
