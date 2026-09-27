import 'package:equatable/equatable.dart';

import 'package:starlight/domain/entities/ble_device.dart';
import 'package:starlight/domain/entities/connection_state.dart';

/// States for the BLE Bloc.
abstract class BleState extends Equatable {
  const BleState();

  @override
  List<Object?> get props => [];
}

/// Initial state - not scanning, not connected.
class BleInitial extends BleState {}

/// Checking permissions.
class BleCheckingPermissions extends BleState {}

/// Permissions denied.
class BlePermissionDenied extends BleState {
  final String message;

  const BlePermissionDenied(this.message);

  @override
  List<Object?> get props => [message];
}

/// Scanning for devices.
class BleScanning extends BleState {
  final List<BleDevice> devices;

  const BleScanning(this.devices);

  @override
  List<Object?> get props => [devices];
}

/// Connecting to a device.
class BleConnecting extends BleState {
  final String deviceId;
  final String deviceName;

  const BleConnecting(this.deviceId, this.deviceName);

  @override
  List<Object?> get props => [deviceId, deviceName];
}

/// Connected to a device.
class BleConnected extends BleState {
  final BleDevice device;

  const BleConnected(this.device);

  @override
  List<Object?> get props => [device];
}

/// Disconnected.
class BleDisconnected extends BleState {
  final DeviceConnectionState connectionState;

  const BleDisconnected([this.connectionState = DeviceConnectionState.disconnected]);

  @override
  List<Object?> get props => [connectionState];
}

/// Error state.
class BleError extends BleState {
  final String message;

  const BleError(this.message);

  @override
  List<Object?> get props => [message];
}
