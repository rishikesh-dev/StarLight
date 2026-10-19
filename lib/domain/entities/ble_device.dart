// SPDX-License-Identifier: Apache-2.0

import 'package:equatable/equatable.dart';

/// Represents a discovered BLE device.
class BleDevice extends Equatable {
  final String id;
  final String name;
  final int rssi;
  final bool isConnected;
  final String? debugLastCommand;
  final String? debugLastNotification;

  const BleDevice({
    required this.id,
    required this.name,
    required this.rssi,
    this.isConnected = false,
    this.debugLastCommand,
    this.debugLastNotification,
  });

  BleDevice copyWith({
    String? id,
    String? name,
    int? rssi,
    bool? isConnected,
    String? debugLastCommand,
    String? debugLastNotification,
  }) {
    return BleDevice(
      id: id ?? this.id,
      name: name ?? this.name,
      rssi: rssi ?? this.rssi,
      isConnected: isConnected ?? this.isConnected,
      debugLastCommand: debugLastCommand ?? this.debugLastCommand,
      debugLastNotification:
          debugLastNotification ?? this.debugLastNotification,
    );
  }

  @override
  List<Object?> get props => [
    id,
    name,
    rssi,
    isConnected,
    debugLastCommand,
    debugLastNotification,
  ];
}
