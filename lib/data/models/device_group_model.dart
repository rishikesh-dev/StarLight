// SPDX-License-Identifier: Apache-2.0

import 'package:starlight/domain/entities/device_group.dart';

/// Serializable model for a persisted [DeviceGroup].
class DeviceGroupModel {
  final String id;
  final String name;
  final String? iconName;
  final List<String> deviceIds;
  final String? roomId;
  final int sortOrder;
  final bool favorite;

  const DeviceGroupModel({
    required this.id,
    required this.name,
    this.iconName,
    this.deviceIds = const [],
    this.roomId,
    this.sortOrder = 0,
    this.favorite = false,
  });

  DeviceGroup toEntity() => DeviceGroup(
    id: id,
    name: name,
    iconName: iconName,
    deviceIds: deviceIds,
    roomId: roomId,
    sortOrder: sortOrder,
    favorite: favorite,
  );

  factory DeviceGroupModel.fromEntity(DeviceGroup group) => DeviceGroupModel(
    id: group.id,
    name: group.name,
    iconName: group.iconName,
    deviceIds: group.deviceIds,
    roomId: group.roomId,
    sortOrder: group.sortOrder,
    favorite: group.favorite,
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'iconName': iconName,
    'deviceIds': deviceIds,
    'roomId': roomId,
    'sortOrder': sortOrder,
    'favorite': favorite,
  };

  factory DeviceGroupModel.fromMap(Map<String, dynamic> map) =>
      DeviceGroupModel(
        id: map['id'] as String,
        name: map['name'] as String,
        iconName: map['iconName'] as String?,
        deviceIds:
            (map['deviceIds'] as List<dynamic>?)
                ?.map((e) => e as String)
                .toList() ??
            const [],
        roomId: map['roomId'] as String?,
        sortOrder: (map['sortOrder'] as int?) ?? 0,
        favorite: (map['favorite'] as bool?) ?? false,
      );
}
