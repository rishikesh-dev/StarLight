// SPDX-License-Identifier: Apache-2.0

import 'package:equatable/equatable.dart';

/// Data layer model for a BLE device.
class BleDeviceModel extends Equatable {
  final String id;
  final String name;
  final int rssi;
  final bool isConnected;
  final bool isDemoDevice;

  const BleDeviceModel({
    required this.id,
    required this.name,
    required this.rssi,
    this.isConnected = false,
    this.isDemoDevice = false,
  });

  /// Returns true if this device is likely an MR Star controller.
  static bool isMrStarDevice(String? name) {
    if (name == null || name.isEmpty) return false;
    return name.contains('GATT--DEMO', 0) ||
        name.toUpperCase().contains('GATT--DEMO');
  }

  BleDeviceModel copyWith({
    String? id,
    String? name,
    int? rssi,
    bool? isConnected,
    bool? isDemoDevice,
  }) {
    return BleDeviceModel(
      id: id ?? this.id,
      name: name ?? this.name,
      rssi: rssi ?? this.rssi,
      isConnected: isConnected ?? this.isConnected,
      isDemoDevice: isDemoDevice ?? this.isDemoDevice,
    );
  }

  @override
  List<Object?> get props => [id, name, rssi, isConnected, isDemoDevice];
}
