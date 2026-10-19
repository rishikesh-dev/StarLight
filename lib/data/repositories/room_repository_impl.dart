// SPDX-License-Identifier: Apache-2.0

import 'dart:math';

import 'package:starlight/core/errors/exceptions.dart';
import 'package:starlight/core/utils/app_logger.dart';
import 'package:starlight/data/datasources/room_datasource.dart';
import 'package:starlight/data/models/room_model.dart';
import 'package:starlight/domain/entities/device.dart';
import 'package:starlight/domain/entities/room.dart';
import 'package:starlight/domain/repositories/device_repository.dart';
import 'package:starlight/domain/repositories/room_repository.dart';

/// [RoomRepository] backed by [RoomDataSource] (SharedPreferences) with device
/// membership delegated to the single [DeviceRepository] registry.
///
/// Room membership is *never* duplicated here: a device belongs to a room only
/// through [Device.roomId]. Rooms therefore cannot go stale relative to the
/// device list, and deleting a room cannot delete a device.
class RoomRepositoryImpl implements RoomRepository {
  final RoomDataSource _dataSource;
  final DeviceRepository _deviceRepository;
  final Random _random;

  RoomRepositoryImpl(this._dataSource, this._deviceRepository, {Random? random})
    : _random = random ?? Random();

  @override
  Future<List<Room>> getRooms() async {
    final models = await _dataSource.loadRooms();
    await _migrateLegacyMembership(models);
    final rooms = models.map((m) => m.toEntity()).toList()
      ..sort(_byOrderThenName);
    return rooms;
  }

  @override
  Future<Room?> getRoom(String roomId) async {
    final rooms = await getRooms();
    for (final room in rooms) {
      if (room.id == roomId) return room;
    }
    return null;
  }

  @override
  Future<List<Device>> getDevicesInRoom(String roomId) {
    return _deviceRepository.getDevicesByRoom(roomId);
  }

  @override
  Future<Room> createRoom(Room room) async {
    final existing = await getRooms();
    final name = _validatedName(room.name, rooms: existing);
    final id = room.id.trim().isEmpty ? _generateId() : room.id.trim();
    if (existing.any((r) => r.id == id)) {
      throw ValidationException('A room with that identifier already exists.');
    }
    final created = room.copyWith(
      id: id,
      name: name,
      sortOrder: room.sortOrder > 0 ? room.sortOrder : _nextSortOrder(existing),
    );
    await _dataSource.saveRoom(RoomModel.fromEntity(created));
    AppLog.info('Rooms: created "${created.name}" ($id)');
    return created;
  }

  @override
  Future<void> updateRoom(Room room) async {
    final existing = await getRooms();
    if (!existing.any((r) => r.id == room.id)) {
      throw ValidationException('That room no longer exists.');
    }
    final name = _validatedName(room.name, rooms: existing, ignoreId: room.id);
    await _dataSource.saveRoom(RoomModel.fromEntity(room.copyWith(name: name)));
    AppLog.info('Rooms: updated ${room.id}');
  }

  Room _requireRoom(List<Room> rooms, String roomId) {
    final room = rooms.where((r) => r.id == roomId).firstOrNull;
    if (room != null) return room;
    throw ArgumentError('Room not found: $roomId');
  }

  @override
  Future<void> renameRoom(String roomId, String name) async {
    final existing = await getRooms();
    final room = _requireRoom(existing, roomId);
    final validated = _validatedName(name, rooms: existing, ignoreId: roomId);
    await _dataSource.saveRoom(
      RoomModel.fromEntity(room.copyWith(name: validated)),
    );
    AppLog.info('Rooms: renamed $roomId to "$validated"');
  }

  @override
  Future<void> reorderRooms(List<String> orderedIds) async {
    final existing = await getRooms();
    final byId = {for (final room in existing) room.id: room};
    var order = 1;
    final seen = <String>{};
    for (final id in orderedIds) {
      final room = byId[id];
      if (room == null || !seen.add(id)) continue;
      byId[id] = room.copyWith(sortOrder: order++);
    }
    // Rooms not mentioned keep a stable position after the listed ones.
    final remaining = existing.where((r) => !seen.contains(r.id)).toList()
      ..sort(_byOrderThenName);
    for (final room in remaining) {
      byId[room.id] = room.copyWith(sortOrder: order++);
    }
    await _dataSource.saveRooms([
      for (final room in existing) RoomModel.fromEntity(byId[room.id]!),
    ]);
    AppLog.info('Rooms: reordered ${orderedIds.length} room(s)');
  }

  @override
  Future<void> deleteRoom(String roomId, {String? reassignToRoomId}) async {
    final existing = await getRooms();
    final room = existing.where((r) => r.id == roomId).firstOrNull;
    if (room == null) return; // Already gone: idempotent, never destructive.

    if (reassignToRoomId != null) {
      if (reassignToRoomId == roomId) {
        throw ValidationException(
          'Devices cannot be moved into the room being deleted.',
        );
      }
      if (!existing.any((r) => r.id == reassignToRoomId)) {
        throw ValidationException(
          'The room to move devices into no longer exists.',
        );
      }
    }

    // Devices are preserved: they are reassigned or unassigned, never removed.
    final devices = await _deviceRepository.getDevicesByRoom(roomId);
    for (final device in devices) {
      await _deviceRepository.updateDevice(device.withRoom(reassignToRoomId));
    }
    await _dataSource.removeRoom(roomId);
    AppLog.info(
      'Rooms: deleted $roomId (${devices.length} device(s) '
      '${reassignToRoomId == null ? 'unassigned' : 'moved to $reassignToRoomId'})',
    );
  }

  @override
  Future<void> moveDeviceToRoom(String deviceId, String? roomId) async {
    final device = await _deviceRepository.getDevice(deviceId);
    if (device == null) {
      throw ValidationException('That device no longer exists.');
    }
    if (roomId != null) {
      final rooms = await getRooms();
      if (!rooms.any((r) => r.id == roomId)) {
        throw ValidationException('That room no longer exists.');
      }
    }
    if (device.roomId == roomId) return;
    await _deviceRepository.updateDevice(device.withRoom(roomId));
    AppLog.info('Rooms: moved device $deviceId → ${roomId ?? 'unassigned'}');
  }

  // --- Migration -------------------------------------------------------------

  /// Moves assignments stored on old room records onto the devices themselves.
  ///
  /// Only runs for legacy payloads (a room that still carries `deviceIds`), and
  /// only fills in devices that have no room yet — an explicit assignment is
  /// never overwritten. Afterwards the legacy arrays are not written back.
  Future<void> _migrateLegacyMembership(List<RoomModel> models) async {
    var migrated = false;
    for (final model in models) {
      if (model.legacyDeviceIds.isEmpty) continue;
      migrated = true;
      for (final deviceId in model.legacyDeviceIds) {
        try {
          final device = await _deviceRepository.getDevice(deviceId);
          if (device == null || device.roomId != null) continue;
          await _deviceRepository.updateDevice(device.withRoom(model.id));
        } catch (e) {
          AppLog.warn('Rooms: legacy assignment for $deviceId failed: $e');
        }
      }
    }
    if (migrated) {
      await _dataSource.saveRooms(
        models.map((m) => RoomModel.fromEntity(m.toEntity())).toList(),
      );
      AppLog.info('Rooms: migrated legacy device assignments');
    }
  }

  // --- Helpers ---------------------------------------------------------------

  String _validatedName(
    String raw, {
    required List<Room> rooms,
    String? ignoreId,
  }) {
    final name = raw.trim();
    if (name.isEmpty) {
      throw ValidationException('Room names cannot be empty.');
    }
    if (name.length > 60) {
      throw ValidationException(
        'Room names cannot be longer than 60 characters.',
      );
    }
    final lower = name.toLowerCase();
    final duplicate = rooms.any(
      (r) => r.id != ignoreId && r.name.toLowerCase() == lower,
    );
    if (duplicate) {
      throw ValidationException('A room named "$name" already exists.');
    }
    return name;
  }

  static int _nextSortOrder(List<Room> rooms) {
    if (rooms.isEmpty) return 1;
    return rooms.map((r) => r.sortOrder).reduce(max) + 1;
  }

  static int _byOrderThenName(Room a, Room b) {
    final byOrder = a.sortOrder.compareTo(b.sortOrder);
    if (byOrder != 0) return byOrder;
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  }

  String _generateId() {
    final micros = DateTime.now().microsecondsSinceEpoch;
    final suffix = _random.nextInt(1 << 32).toRadixString(36);
    return 'room_${micros.toRadixString(36)}_$suffix';
  }
}
