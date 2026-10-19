// SPDX-License-Identifier: Apache-2.0

import 'package:starlight/domain/entities/device.dart';
import 'package:starlight/domain/entities/room.dart';

/// Repository for room management.
///
/// Rooms group devices logically (Living Room, Bedroom, …). Membership lives on
/// [Device.roomId]; the room itself never stores a duplicate list of devices.
///
/// All mutations validate their inputs and throw [ValidationException]
/// (`starlight/core/errors/exceptions.dart`) when a rule is violated (blank or
/// duplicate names, unknown room/device, …). Reads are defensive: malformed
/// persisted data is skipped rather than crashing the app.
abstract class RoomRepository {
  /// Returns all rooms, ordered by [Room.sortOrder] then name.
  Future<List<Room>> getRooms();

  /// Returns a single room by ID, or null.
  Future<Room?> getRoom(String roomId);

  /// Returns all devices currently assigned to a room (from the real device
  /// registry — never a duplicated record on the room itself).
  Future<List<Device>> getDevicesInRoom(String roomId);

  /// Creates a new room. Returns the created room with its generated id.
  ///
  /// Throws when [room].name is blank or already used by another room.
  Future<Room> createRoom(Room room);

  /// Updates a room's name, icon and/or sort order.
  Future<void> updateRoom(Room room);

  /// Renames an existing room, rejecting blank/duplicate names.
  Future<void> renameRoom(String roomId, String name);

  /// Persists a new ordering. Unknown ids are ignored; rooms missing from
  /// [orderedIds] keep a stable position after the listed ones.
  Future<void> reorderRooms(List<String> orderedIds);

  /// Deletes a room.
  ///
  /// Devices are never deleted. By default they become unassigned
  /// (`roomId = null`); pass [reassignToRoomId] to move them to another room.
  Future<void> deleteRoom(String roomId, {String? reassignToRoomId});

  /// Moves a device to a room. Pass `null` [roomId] to unassign.
  ///
  /// Throws when the device does not exist or the target room does not exist.
  Future<void> moveDeviceToRoom(String deviceId, String? roomId);
}
