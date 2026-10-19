// SPDX-License-Identifier: Apache-2.0

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

  /// True when the permission is permanently denied, so the request dialog
  /// will not be shown again and the user must use the system app settings.
  final bool permanentlyDenied;

  const BlePermissionDenied(this.message, {this.permanentlyDenied = false});

  @override
  List<Object?> get props => [message, permanentlyDenied];
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

/// Disconnected (or ready to connect).
///
/// [device] is the last-known paired device, when one exists. It lets the UI
/// show the saved device and offer a reconnect without fabricating a live
/// connection: it is only ever the identity this bloc actually connected to or
/// loaded from the persisted pairing. It is null when nothing is paired.
class BleDisconnected extends BleState {
  final DeviceConnectionState connectionState;
  final BleDevice? device;

  const BleDisconnected([
    this.connectionState = DeviceConnectionState.disconnected,
    this.device,
  ]);

  @override
  List<Object?> get props => [connectionState, device];
}

/// Error state.
class BleError extends BleState {
  final String message;

  const BleError(this.message);

  @override
  List<Object?> get props => [message];
}

/// Bluetooth adapter is off. The user can retry (which re-requests the system
/// enable flow) or turn Bluetooth on manually.
class BleBluetoothOff extends BleState {
  final String message;

  const BleBluetoothOff([this.message = 'Bluetooth is turned off']);

  @override
  List<Object?> get props => [message];
}

/// Bluetooth is not supported on this device, or the required permissions are
/// permanently denied so it cannot be used.
class BleBluetoothUnavailable extends BleState {
  final String message;

  const BleBluetoothUnavailable(this.message);

  @override
  List<Object?> get props => [message];
}

/// A system enable-Bluetooth request is in progress.
class BleBluetoothEnabling extends BleState {
  const BleBluetoothEnabling();
}
