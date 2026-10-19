// SPDX-License-Identifier: Apache-2.0

import 'package:equatable/equatable.dart';

import 'device_capability.dart';
import 'device_type.dart';
import 'rgb_color.dart';

/// Connection state for network devices (WLED, MQTT).
enum NetworkConnectionState { disconnected, connecting, connected, unreachable }

class NetworkDevice extends Equatable {
  final String id;
  final String name;
  final DeviceType type;
  final String address;
  final List<DeviceCapability> capabilities;
  final NetworkConnectionState connectionState;
  final int? brightness;
  final RGBColor? color;
  final String? effect;
  final bool? isOn;
  final int? ledCount;
  final String? firmwareVersion;
  final List<String> supportedEffects;
  final List<String> supportedPalettes;
  final Map<String, dynamic> metadata;
  final DateTime? lastSeen;
  final bool favorite;

  const NetworkDevice({
    required this.id,
    required this.name,
    required this.type,
    required this.address,
    required this.capabilities,
    required this.connectionState,
    this.brightness,
    this.color,
    this.effect,
    this.isOn,
    this.ledCount,
    this.firmwareVersion,
    this.supportedEffects = const [],
    this.supportedPalettes = const [],
    this.metadata = const {},
    this.lastSeen,
    this.favorite = false,
  });

  bool get isConnected => connectionState == NetworkConnectionState.connected;
  bool get isUnreachable =>
      connectionState == NetworkConnectionState.unreachable;

  NetworkDevice copyWith({
    String? id,
    String? name,
    DeviceType? type,
    String? address,
    List<DeviceCapability>? capabilities,
    NetworkConnectionState? connectionState,
    int? brightness,
    RGBColor? color,
    String? effect,
    bool? isOn,
    int? ledCount,
    String? firmwareVersion,
    List<String>? supportedEffects,
    List<String>? supportedPalettes,
    Map<String, dynamic>? metadata,
    DateTime? lastSeen,
    bool? favorite,
  }) {
    return NetworkDevice(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      address: address ?? this.address,
      capabilities: capabilities ?? this.capabilities,
      connectionState: connectionState ?? this.connectionState,
      brightness: brightness ?? this.brightness,
      color: color ?? this.color,
      effect: effect ?? this.effect,
      isOn: isOn ?? this.isOn,
      ledCount: ledCount ?? this.ledCount,
      firmwareVersion: firmwareVersion ?? this.firmwareVersion,
      supportedEffects: supportedEffects ?? this.supportedEffects,
      supportedPalettes: supportedPalettes ?? this.supportedPalettes,
      metadata: metadata ?? this.metadata,
      lastSeen: lastSeen ?? this.lastSeen,
      favorite: favorite ?? this.favorite,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'type': type.id,
      'address': address,
      'capabilities': capabilities.map((c) => c.id).toList(),
      'connectionState': connectionState.index,
      'brightness': brightness,
      'color': color?.toHexStr(),
      'effect': effect,
      'isOn': isOn,
      'ledCount': ledCount,
      'firmwareVersion': firmwareVersion,
      'supportedEffects': supportedEffects,
      'supportedPalettes': supportedPalettes,
      'metadata': metadata,
      'lastSeen': lastSeen?.toIso8601String(),
      'favorite': favorite,
    };
  }

  factory NetworkDevice.fromMap(Map<String, dynamic> map) {
    return NetworkDevice(
      id: map['id'] as String,
      name: map['name'] as String,
      type: DeviceType.values.firstWhere(
        (t) => t.id == map['type'],
        orElse: () => DeviceType.light,
      ),
      address: map['address'] as String,
      capabilities:
          (map['capabilities'] as List?)
              ?.map(
                (c) => DeviceCapability.values.firstWhere(
                  (cap) => cap.id == c,
                  orElse: () => DeviceCapability.custom,
                ),
              )
              .toList() ??
          [],
      connectionState: NetworkConnectionState.values.elementAt(
        (map['connectionState'] as int?) ?? 0,
      ),
      brightness: map['brightness'] as int?,
      color: map['color'] != null
          ? RGBColor.fromHexStr(map['color'] as String)
          : null,
      effect: map['effect'] as String?,
      isOn: map['isOn'] as bool?,
      ledCount: map['ledCount'] as int?,
      firmwareVersion: map['firmwareVersion'] as String?,
      supportedEffects:
          (map['supportedEffects'] as List?)?.cast<String>() ?? const [],
      supportedPalettes:
          (map['supportedPalettes'] as List?)?.cast<String>() ?? const [],
      metadata: (map['metadata'] as Map?)?.cast<String, dynamic>() ?? const {},
      lastSeen: map['lastSeen'] != null
          ? DateTime.parse(map['lastSeen'] as String)
          : null,
      favorite: map['favorite'] as bool? ?? false,
    );
  }

  @override
  List<Object?> get props => [
    id,
    name,
    type,
    address,
    capabilities,
    connectionState,
    brightness,
    color,
    effect,
    isOn,
    ledCount,
    firmwareVersion,
    supportedEffects,
    supportedPalettes,
    metadata,
    lastSeen,
    favorite,
  ];
}
