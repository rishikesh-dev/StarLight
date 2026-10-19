// SPDX-License-Identifier: Apache-2.0

import 'package:equatable/equatable.dart';

/// Represents a light command to be sent to the LED controller.
class LightCommand extends Equatable {
  final String type;
  final List<int> bytes;

  const LightCommand({required this.type, required this.bytes});

  @override
  List<Object?> get props => [type, bytes];
}

/// Represents a BLE device connection result.
class DeviceConnectionResult extends Equatable {
  final bool success;
  final String? errorMessage;

  const DeviceConnectionResult({required this.success, this.errorMessage});

  @override
  List<Object?> get props => [success, errorMessage];
}
