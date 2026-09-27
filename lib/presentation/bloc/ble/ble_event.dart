import 'package:equatable/equatable.dart';

import 'package:starlight/domain/entities/ble_device.dart';
import 'package:starlight/domain/entities/connection_state.dart';

/// Events for the BLE Bloc.
abstract class BleEvent extends Equatable {
  const BleEvent();

  @override
  List<Object?> get props => [];
}

/// Request permissions and start scanning.
class StartScan extends BleEvent {}

/// Stop the current scan.
class StopScanRequested extends BleEvent {}

/// Connect to a specific device.
class ConnectToDevice extends BleEvent {
  final String deviceId;
  final String deviceName;

  const ConnectToDevice(this.deviceId, this.deviceName);

  @override
  List<Object?> get props => [deviceId, deviceName];
}

/// Disconnect from the current device.
class DisconnectRequested extends BleEvent {}

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
