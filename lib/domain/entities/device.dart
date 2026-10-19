// SPDX-License-Identifier: Apache-2.0

import 'package:equatable/equatable.dart';

import 'device_type.dart';
import 'device_capability.dart';
import 'device_state.dart';
import 'connection_state.dart';

/// Represents a device in the home automation system.
class Device extends Equatable {
  final String id;
  final String name;
  final DeviceType type;
  final String? manufacturer;
  final String? model;
  final String transport; // ble, wifi, mqtt, matter, homeassistant
  final String address; // MAC, IP, etc.
  final String? roomId;
  final List<DeviceCapability> capabilities;
  final DeviceConnectionState connectionState;
  final DeviceState state;
  final bool favorite;
  final DateTime? lastSeen;
  final Map<String, dynamic> metadata;

  const Device({
    required this.id,
    required this.name,
    required this.type,
    this.manufacturer,
    this.model,
    required this.transport,
    required this.address,
    this.roomId,
    required this.capabilities,
    required this.connectionState,
    required this.state,
    this.favorite = false,
    this.lastSeen,
    this.metadata = const {},
  });

  /// Creates a Device from a BLE device (for StarLight).
  factory Device.fromBleDevice({
    required String id,
    required String name,
    required String address,
    required List<DeviceCapability> capabilities,
    required DeviceConnectionState connectionState,
    required DeviceState state,
    String? roomId,
    bool favorite = false,
    Map<String, dynamic> metadata = const {},
  }) {
    return Device(
      id: id,
      name: name,
      type: DeviceType.light,
      manufacturer: 'MR Star',
      model: 'GATT--DEMO',
      transport: 'ble',
      address: address,
      roomId: roomId,
      capabilities: capabilities,
      connectionState: connectionState,
      state: state,
      favorite: favorite,
      metadata: metadata,
    );
  }

  Device copyWith({
    String? id,
    String? name,
    DeviceType? type,
    String? manufacturer,
    String? model,
    String? transport,
    String? address,
    String? roomId,
    List<DeviceCapability>? capabilities,
    DeviceConnectionState? connectionState,
    DeviceState? state,
    bool? favorite,
    DateTime? lastSeen,
    Map<String, dynamic>? metadata,
  }) {
    return Device(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      manufacturer: manufacturer ?? this.manufacturer,
      model: model ?? this.model,
      transport: transport ?? this.transport,
      address: address ?? this.address,
      roomId: roomId ?? this.roomId,
      capabilities: capabilities ?? this.capabilities,
      connectionState: connectionState ?? this.connectionState,
      state: state ?? this.state,
      favorite: favorite ?? this.favorite,
      lastSeen: lastSeen ?? this.lastSeen,
      metadata: metadata ?? this.metadata,
    );
  }

  /// Returns a copy of this device assigned to [roomId].
  ///
  /// Unlike [copyWith], passing `null` clears the room assignment — required to
  /// unassign a device when its room is deleted.
  Device withRoom(String? roomId) => Device(
    id: id,
    name: name,
    type: type,
    manufacturer: manufacturer,
    model: model,
    transport: transport,
    address: address,
    roomId: roomId,
    capabilities: capabilities,
    connectionState: connectionState,
    state: state,
    favorite: favorite,
    lastSeen: lastSeen,
    metadata: metadata,
  );

  bool get isConnected => connectionState == DeviceConnectionState.connected;

  bool get isConnecting => connectionState == DeviceConnectionState.connecting;
  bool get isDisconnected =>
      connectionState == DeviceConnectionState.disconnected;
  bool get hasError => connectionState == DeviceConnectionState.error;

  /// Checks whether this device supports a given capability.
  /// Used by the UI and scene engine to decide which controls are available.
  bool supports(DeviceCapability capability) =>
      capabilities.contains(capability);

  /// Checks whether this device supports ALL of the given capabilities.
  bool supportsAll(Iterable<DeviceCapability> caps) =>
      caps.every((c) => capabilities.contains(c));

  /// Checks whether this device supports ANY of the given capabilities.
  bool supportsAny(Iterable<DeviceCapability> caps) =>
      caps.any((c) => capabilities.contains(c));

  @override
  List<Object?> get props => [
    id,
    name,
    type,
    manufacturer,
    model,
    transport,
    address,
    roomId,
    capabilities,
    connectionState,
    state,
    favorite,
    lastSeen,
    metadata,
  ];
}
