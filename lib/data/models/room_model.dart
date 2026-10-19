// SPDX-License-Identifier: Apache-2.0

import 'package:starlight/domain/entities/room.dart';

/// Serializable model for a persisted [Room].
///
/// Room *membership* is not persisted here: it lives on the device registry
/// (`Device.roomId`). Older builds stored a `deviceIds` array on the room; it is
/// still read into [legacyDeviceIds] so a one-time migration can move those
/// assignments onto the devices instead of losing them. It is never written
/// back.
class RoomModel {
  final String id;
  final String name;
  final String? iconName;
  final int sortOrder;

  /// Device ids read from a legacy `deviceIds` array (pre-migration only).
  final List<String> legacyDeviceIds;

  const RoomModel({
    required this.id,
    required this.name,
    this.iconName,
    this.sortOrder = 0,
    this.legacyDeviceIds = const [],
  });

  Room toEntity() =>
      Room(id: id, name: name, iconName: iconName, sortOrder: sortOrder);

  factory RoomModel.fromEntity(Room room) => RoomModel(
    id: room.id,
    name: room.name,
    iconName: room.iconName,
    sortOrder: room.sortOrder,
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'iconName': iconName,
    'sortOrder': sortOrder,
  };

  factory RoomModel.fromMap(Map<String, dynamic> map) {
    final rawIds = map['deviceIds'];
    return RoomModel(
      id: map['id'] as String,
      name: map['name'] as String,
      iconName: map['iconName'] as String?,
      sortOrder: (map['sortOrder'] as int?) ?? 0,
      legacyDeviceIds: rawIds is List
          ? rawIds.whereType<String>().toList(growable: false)
          : const [],
    );
  }
}
