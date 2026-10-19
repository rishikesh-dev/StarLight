// SPDX-License-Identifier: Apache-2.0

import 'package:equatable/equatable.dart';

/// A logical group of devices (for example "Downstairs" or "All desk lights").
///
/// A group is a *logical* convenience only — it does not model, and must never
/// be confused with, a physical BLE connection. Members are explicit device ids;
/// a device may belong to any number of groups, and a group never owns or
/// duplicates device records. Every command is still sent to each member through
/// the single BLE owner, sequentially, with per-device results.
class DeviceGroup extends Equatable {
  final String id;
  final String name;
  final String? iconName;

  /// Member device ids. Order is preserved but has no command semantics.
  final List<String> deviceIds;

  /// Optional room association, matching [Device.roomId]. Not a membership
  /// requirement: devices may join a group regardless of their room.
  final String? roomId;

  final int sortOrder;
  final bool favorite;

  const DeviceGroup({
    required this.id,
    required this.name,
    this.iconName,
    this.deviceIds = const [],
    this.roomId,
    this.sortOrder = 0,
    this.favorite = false,
  });

  DeviceGroup copyWith({
    String? id,
    String? name,
    String? iconName,
    List<String>? deviceIds,
    Object? roomId = _unset,
    int? sortOrder,
    bool? favorite,
  }) {
    return DeviceGroup(
      id: id ?? this.id,
      name: name ?? this.name,
      iconName: iconName ?? this.iconName,
      deviceIds: deviceIds ?? this.deviceIds,
      roomId: roomId == _unset ? this.roomId : roomId as String?,
      sortOrder: sortOrder ?? this.sortOrder,
      favorite: favorite ?? this.favorite,
    );
  }

  @override
  List<Object?> get props => [
    id,
    name,
    iconName,
    deviceIds,
    roomId,
    sortOrder,
    favorite,
  ];
}

/// Sentinel so [DeviceGroup.copyWith] can distinguish "leave roomId" from
/// "set roomId to null".
const Object _unset = Object();
