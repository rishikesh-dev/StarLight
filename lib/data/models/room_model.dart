import 'package:starlight/domain/entities/room.dart';

/// Serializable model for a persisted [Room].
class RoomModel {
  final String id;
  final String name;
  final String? iconName;
  final int sortOrder;
  final List<String> deviceIds;

  const RoomModel({
    required this.id,
    required this.name,
    this.iconName,
    this.sortOrder = 0,
    this.deviceIds = const [],
  });

  Room toEntity() => Room(
        id: id,
        name: name,
        iconName: iconName,
        sortOrder: sortOrder,
        deviceIds: deviceIds,
      );

  factory RoomModel.fromEntity(Room room) => RoomModel(
        id: room.id,
        name: room.name,
        iconName: room.iconName,
        sortOrder: room.sortOrder,
        deviceIds: room.deviceIds,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'iconName': iconName,
        'sortOrder': sortOrder,
        'deviceIds': deviceIds,
      };

  factory RoomModel.fromMap(Map<String, dynamic> map) => RoomModel(
        id: map['id'] as String,
        name: map['name'] as String,
        iconName: map['iconName'] as String?,
        sortOrder: (map['sortOrder'] as int?) ?? 0,
        deviceIds: (map['deviceIds'] as List<dynamic>?)
            ?.map((e) => e as String)
            .toList() ??
            const [],
      );
}