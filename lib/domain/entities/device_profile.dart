// SPDX-License-Identifier: Apache-2.0

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

import '../../core/ble/ble_constants.dart';
import 'device_capability.dart';
import 'notification_format.dart';
import 'profile_command.dart';

/// Transport protocol a [DeviceProfile] describes.
///
/// Only [bleGatt] is executable in this milestone; WLED/MQTT are intentionally
/// absent rather than presented as supported.
enum ProfileProtocol {
  bleGatt('ble_gatt', 'Bluetooth LE (GATT)');

  const ProfileProtocol(this.id, this.label);

  final String id;
  final String label;

  static ProfileProtocol? fromId(String id) {
    for (final p in ProfileProtocol.values) {
      if (p.id == id) return p;
    }
    return null;
  }
}

/// How a profile's commands are written to the GATT characteristic.
enum GattWriteMode {
  automatic('automatic', 'Automatic'),
  withResponse('with_response', 'With response'),
  withoutResponse('without_response', 'Without response');

  const GattWriteMode(this.id, this.label);

  final String id;
  final String label;

  static GattWriteMode fromId(String? id) {
    for (final m in GattWriteMode.values) {
      if (m.id == id) return m;
    }
    return GattWriteMode.automatic;
  }
}

/// Schema version written with every persisted profile.
const int kProfileSchemaVersion = 1;

/// Id of the built-in MR Star profile. It is never persisted and never edited:
/// assigning it means "use the existing MR Star encoder".
const String kMrStarProfileId = 'builtin.mrstar';

/// Capabilities the app can genuinely execute for a custom GATT profile today.
/// A profile declaring anything else is rejected by the validator rather than
/// silently offering a control that cannot work.
const Set<DeviceCapability> kExecutableProfileCapabilities = {
  DeviceCapability.power,
  DeviceCapability.brightness,
  DeviceCapability.color,
};

/// The validated command mappings for one profile.
@immutable
class GattCommandSet extends Equatable {
  final CommandTemplate? powerOn;
  final CommandTemplate? powerOff;
  final CommandTemplate? brightness;
  final CommandTemplate? color;

  /// Brightness range the device expects. The app's internal brightness scale
  /// is 0–1000, which is linearly mapped into this range before encoding.
  final int brightnessMin;
  final int brightnessMax;

  const GattCommandSet({
    this.powerOn,
    this.powerOff,
    this.brightness,
    this.color,
    this.brightnessMin = 0,
    this.brightnessMax = 255,
  });

  bool get hasAny =>
      powerOn != null ||
      powerOff != null ||
      brightness != null ||
      color != null;

  /// Maps a 0–1000 app brightness onto [brightnessMin]..[brightnessMax].
  int scaleBrightness(int value) {
    final clamped = value.clamp(0, 1000);
    if (brightnessMax <= brightnessMin) return brightnessMin;
    final span = brightnessMax - brightnessMin;
    return brightnessMin + ((clamped / 1000) * span).round();
  }

  GattCommandSet copyWith({
    CommandTemplate? powerOn,
    CommandTemplate? powerOff,
    CommandTemplate? brightness,
    CommandTemplate? color,
    int? brightnessMin,
    int? brightnessMax,
  }) {
    return GattCommandSet(
      powerOn: powerOn ?? this.powerOn,
      powerOff: powerOff ?? this.powerOff,
      brightness: brightness ?? this.brightness,
      color: color ?? this.color,
      brightnessMin: brightnessMin ?? this.brightnessMin,
      brightnessMax: brightnessMax ?? this.brightnessMax,
    );
  }

  @override
  List<Object?> get props => [
    powerOn,
    powerOff,
    brightness,
    color,
    brightnessMin,
    brightnessMax,
  ];
}

/// A user-defined (or built-in) device profile.
///
/// Pure domain object: persistence, validation and transport concerns live in
/// the data/domain services. [isBuiltIn] profiles are never edited, deleted or
/// persisted — they describe behaviour the app already implements.
@immutable
class DeviceProfile extends Equatable {
  final String id;
  final String name;
  final ProfileProtocol protocol;

  /// GATT service that contains the write/notify characteristics.
  final String serviceUuid;

  /// Characteristic commands are written to.
  final String writeCharacteristicUuid;

  /// Optional characteristic state notifications are read from.
  final String? notifyCharacteristicUuid;

  final GattWriteMode writeMode;

  /// Validated command encodings.
  final GattCommandSet commands;

  /// Optional notification decoding configuration.
  final NotificationFormat? notifications;

  /// Capabilities the author declares the device supports.
  final Set<DeviceCapability> capabilities;

  final int schemaVersion;
  final bool isBuiltIn;

  const DeviceProfile({
    required this.id,
    required this.name,
    this.protocol = ProfileProtocol.bleGatt,
    required this.serviceUuid,
    required this.writeCharacteristicUuid,
    this.notifyCharacteristicUuid,
    this.writeMode = GattWriteMode.automatic,
    this.commands = const GattCommandSet(),
    this.notifications,
    this.capabilities = const {},
    this.schemaVersion = kProfileSchemaVersion,
    this.isBuiltIn = false,
  });

  /// The built-in MR Star profile.
  ///
  /// It carries the real MR Star UUIDs for display, but its commands are the
  /// existing [ProtocolEncoder] path — assigning it means "no custom profile".
  static const DeviceProfile mrStar = DeviceProfile(
    id: kMrStarProfileId,
    name: 'MR Star (built-in)',
    protocol: ProfileProtocol.bleGatt,
    serviceUuid: BleConstants.serviceUuid,
    writeCharacteristicUuid: BleConstants.writeCharUuid,
    notifyCharacteristicUuid: BleConstants.notifyCharUuid,
    capabilities: {
      DeviceCapability.power,
      DeviceCapability.brightness,
      DeviceCapability.color,
    },
    isBuiltIn: true,
  );

  bool get hasNotifications =>
      notifyCharacteristicUuid != null &&
      notifyCharacteristicUuid!.trim().isNotEmpty &&
      notifications != null &&
      !notifications!.isEmpty;

  DeviceProfile copyWith({
    String? id,
    String? name,
    ProfileProtocol? protocol,
    String? serviceUuid,
    String? writeCharacteristicUuid,
    String? notifyCharacteristicUuid,
    bool clearNotifyCharacteristic = false,
    GattWriteMode? writeMode,
    GattCommandSet? commands,
    NotificationFormat? notifications,
    bool clearNotifications = false,
    Set<DeviceCapability>? capabilities,
    int? schemaVersion,
    bool? isBuiltIn,
  }) {
    return DeviceProfile(
      id: id ?? this.id,
      name: name ?? this.name,
      protocol: protocol ?? this.protocol,
      serviceUuid: serviceUuid ?? this.serviceUuid,
      writeCharacteristicUuid:
          writeCharacteristicUuid ?? this.writeCharacteristicUuid,
      notifyCharacteristicUuid: clearNotifyCharacteristic
          ? null
          : (notifyCharacteristicUuid ?? this.notifyCharacteristicUuid),
      writeMode: writeMode ?? this.writeMode,
      commands: commands ?? this.commands,
      notifications: clearNotifications
          ? null
          : (notifications ?? this.notifications),
      capabilities: capabilities ?? this.capabilities,
      schemaVersion: schemaVersion ?? this.schemaVersion,
      isBuiltIn: isBuiltIn ?? this.isBuiltIn,
    );
  }

  @override
  List<Object?> get props => [
    id,
    name,
    protocol,
    serviceUuid,
    writeCharacteristicUuid,
    notifyCharacteristicUuid,
    writeMode,
    commands,
    notifications,
    // Sets compare by identity, so compare a canonical, ordered copy.
    (capabilities.map((c) => c.name).toList()..sort()),
    schemaVersion,
    isBuiltIn,
  ];
}
