import 'package:equatable/equatable.dart';

/// Represents a room in the home.
class Room extends Equatable {
  final String id;
  final String name;
  final String? iconName;
  final int sortOrder;
  final List<String> deviceIds;

  const Room({
    required this.id,
    required this.name,
    this.iconName,
    this.sortOrder = 0,
    this.deviceIds = const [],
  });

  Room copyWith({
    String? id,
    String? name,
    String? iconName,
    int? sortOrder,
    List<String>? deviceIds,
  }) {
    return Room(
      id: id ?? this.id,
      name: name ?? this.name,
      iconName: iconName ?? this.iconName,
      sortOrder: sortOrder ?? this.sortOrder,
      deviceIds: deviceIds ?? this.deviceIds,
    );
  }

  @override
  List<Object?> get props => [id, name, iconName, sortOrder, deviceIds];
}

/// Default rooms for a new home.
class DefaultRooms {
  static const List<Room> rooms = [
    Room(id: 'living-room', name: 'Living Room', iconName: 'living', sortOrder: 1),
    Room(id: 'bedroom', name: 'Bedroom', iconName: 'bedroom', sortOrder: 2),
    Room(id: 'office', name: 'Office', iconName: 'work', sortOrder: 3),
    Room(id: 'kitchen', name: 'Kitchen', iconName: 'kitchen', sortOrder: 4),
    Room(id: 'bathroom', name: 'Bathroom', iconName: 'bathroom', sortOrder: 5),
    Room(id: 'dining-room', name: 'Dining Room', iconName: 'restaurant', sortOrder: 6),
    Room(id: 'garage', name: 'Garage', iconName: 'garage', sortOrder: 7),
    Room(id: 'outdoor', name: 'Outdoor', iconName: 'yard', sortOrder: 8),
  ];
}