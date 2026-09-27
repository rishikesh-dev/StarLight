import 'package:starlight/domain/entities/device.dart';
import 'package:starlight/domain/entities/room.dart';

/// Repository for room management.
///
/// Rooms group devices logically (Living Room, Bedroom, etc.).
/// Default rooms are seeded on first launch; users can create their own.
abstract class RoomRepository {
  /// Returns all rooms, ordered by [Room.sortOrder].
  Future<List<Room>> getRooms();

  /// Returns a single room by ID, or null.
  Future<Room?> getRoom(String roomId);

  /// Returns all devices assigned to a room.
  Future<List<Device>> getDevicesInRoom(String roomId);

  /// Creates a new room. Returns the created room with its generated ID.
  Future<Room> createRoom(Room room);

  /// Renames an existing room.
  Future<void> renameRoom(String roomId, String name);

  /// Deletes a room. Devices in the room are unassigned (roomId = null).
  Future<void> deleteRoom(String roomId);

  /// Moves a device to a room. Pass null roomId to unassign.
  Future<void> moveDeviceToRoom(String deviceId, String? roomId);

  /// Seeds the default rooms if none exist yet.
  Future<void> ensureDefaultRooms();
}