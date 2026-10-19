// SPDX-License-Identifier: Apache-2.0

import 'dart:math';

import 'package:starlight/core/errors/exceptions.dart';
import 'package:starlight/core/utils/app_logger.dart';
import 'package:starlight/data/datasources/device_group_datasource.dart';
import 'package:starlight/data/models/device_group_model.dart';
import 'package:starlight/domain/entities/device_group.dart';
import 'package:starlight/domain/repositories/device_group_repository.dart';
import 'package:starlight/domain/repositories/device_repository.dart';
import 'package:starlight/domain/repositories/room_repository.dart';

/// [DeviceGroupRepository] backed by [DeviceGroupDataSource], validating every
/// member against the single [DeviceRepository] registry.
class DeviceGroupRepositoryImpl implements DeviceGroupRepository {
  final DeviceGroupDataSource _dataSource;
  final DeviceRepository _deviceRepository;
  final RoomRepository? _roomRepository;
  final Random _random;

  DeviceGroupRepositoryImpl(
    this._dataSource,
    this._deviceRepository, {
    this._roomRepository,
    Random? random,
  }) : _random = random ?? Random();

  /// Whether room references in groups are validated against [RoomRepository].
  bool get validatesRooms => _roomRepository != null;

  @override
  Future<List<DeviceGroup>> getGroups() async {
    final models = await _dataSource.loadGroups();
    final groups = models.map((m) => m.toEntity()).toList()
      ..sort(_byOrderThenName);
    return groups;
  }

  @override
  Future<DeviceGroup?> getGroup(String groupId) async {
    final groups = await getGroups();
    return groups.where((g) => g.id == groupId).firstOrNull;
  }

  @override
  Future<DeviceGroup> createGroup(DeviceGroup group) async {
    final existing = await getGroups();
    final name = _validatedName(group.name, groups: existing);
    final id = group.id.trim().isEmpty ? _generateId() : group.id.trim();
    if (existing.any((g) => g.id == id)) {
      throw ValidationException('A group with that identifier already exists.');
    }
    await _validateRoom(group.roomId);
    final members = await _validateMembers(group.deviceIds);
    final created = group.copyWith(
      id: id,
      name: name,
      deviceIds: members,
      sortOrder: group.sortOrder > 0
          ? group.sortOrder
          : _nextSortOrder(existing),
    );
    await _save(created, existing);
    AppLog.info('Groups: created "${created.name}" ($id)');
    return created;
  }

  @override
  Future<void> updateGroup(DeviceGroup group) async {
    final existing = await getGroups();
    if (!existing.any((g) => g.id == group.id)) {
      throw ValidationException('That group no longer exists.');
    }
    final name = _validatedName(
      group.name,
      groups: existing,
      ignoreId: group.id,
    );
    await _validateRoom(group.roomId);
    await _save(group.copyWith(name: name), existing);
    AppLog.info('Groups: updated ${group.id}');
  }

  @override
  Future<void> deleteGroup(String groupId) async {
    final existing = await getGroups();
    if (!existing.any((g) => g.id == groupId)) return; // idempotent
    // Devices are never touched by a group deletion.
    await _saveAll(existing.where((g) => g.id != groupId).toList());
    AppLog.info('Groups: deleted $groupId');
  }

  @override
  Future<void> addDeviceToGroup(String groupId, String deviceId) async {
    final group = await getGroup(groupId);
    if (group == null) {
      throw ValidationException('That group no longer exists.');
    }
    if (group.deviceIds.contains(deviceId)) return;
    final members = await _validateMembers([...group.deviceIds, deviceId]);
    await _save(group.copyWith(deviceIds: members), await getGroups());
  }

  @override
  Future<void> removeDeviceFromGroup(String groupId, String deviceId) async {
    final group = await getGroup(groupId);
    if (group == null) {
      throw ValidationException('That group no longer exists.');
    }
    if (!group.deviceIds.contains(deviceId)) return;
    final members = group.deviceIds.where((id) => id != deviceId).toList();
    await _save(group.copyWith(deviceIds: members), await getGroups());
  }

  @override
  Future<void> setGroupMembers(String groupId, List<String> deviceIds) async {
    final group = await getGroup(groupId);
    if (group == null) {
      throw ValidationException('That group no longer exists.');
    }
    final members = await _validateMembers(deviceIds);
    await _save(group.copyWith(deviceIds: members), await getGroups());
  }

  // --- Helpers ---------------------------------------------------------------

  Future<void> _save(DeviceGroup group, List<DeviceGroup> existing) {
    final next = [
      for (final g in existing)
        if (g.id == group.id) group else g,
      if (!existing.any((g) => g.id == group.id)) group,
    ];
    return _saveAll(next);
  }

  Future<void> _saveAll(List<DeviceGroup> groups) {
    return _dataSource.saveGroups(
      groups.map(DeviceGroupModel.fromEntity).toList(),
    );
  }

  /// Validates and de-duplicates member ids, preserving order.
  Future<List<String>> _validateMembers(List<String> deviceIds) async {
    final result = <String>[];
    for (final id in deviceIds) {
      if (result.contains(id)) continue;
      final device = await _deviceRepository.getDevice(id);
      if (device == null) {
        throw ValidationException(
          'One of the selected devices no longer exists.',
        );
      }
      result.add(id);
    }
    return result;
  }

  Future<void> _validateRoom(String? roomId) async {
    if (roomId == null) return;
    final rooms = _roomRepository;
    if (rooms == null) return;
    final room = await rooms.getRoom(roomId);
    if (room == null) {
      throw ValidationException('That room no longer exists.');
    }
  }

  String _validatedName(
    String raw, {
    required List<DeviceGroup> groups,
    String? ignoreId,
  }) {
    final name = raw.trim();
    if (name.isEmpty) {
      throw ValidationException('Group names cannot be empty.');
    }
    if (name.length > 60) {
      throw ValidationException(
        'Group names cannot be longer than 60 characters.',
      );
    }
    final lower = name.toLowerCase();
    if (groups.any((g) => g.id != ignoreId && g.name.toLowerCase() == lower)) {
      throw ValidationException('A group named "$name" already exists.');
    }
    return name;
  }

  static int _nextSortOrder(List<DeviceGroup> groups) {
    if (groups.isEmpty) return 1;
    return groups.map((g) => g.sortOrder).reduce(max) + 1;
  }

  static int _byOrderThenName(DeviceGroup a, DeviceGroup b) {
    final byOrder = a.sortOrder.compareTo(b.sortOrder);
    if (byOrder != 0) return byOrder;
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  }

  String _generateId() {
    final micros = DateTime.now().microsecondsSinceEpoch;
    final suffix = _random.nextInt(1 << 32).toRadixString(36);
    return 'group_${micros.toRadixString(36)}_$suffix';
  }
}
