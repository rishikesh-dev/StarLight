// SPDX-License-Identifier: Apache-2.0

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

import 'package:starlight/core/errors/exceptions.dart';
import 'package:starlight/core/utils/app_logger.dart';
import 'package:starlight/domain/entities/room.dart';
import 'package:starlight/domain/repositories/room_repository.dart';
import 'package:starlight/presentation/bloc/registry/device_registry_cubit.dart';

class RoomState extends Equatable {
  final List<Room> rooms;
  final bool loading;

  /// Set after a rejected operation; the UI shows it and clears it via
  /// [RoomCleared].
  final String? error;

  const RoomState({this.rooms = const [], this.loading = false, this.error});

  Room? byId(String id) => rooms.where((r) => r.id == id).firstOrNull;

  RoomState copyWith({
    List<Room>? rooms,
    bool? loading,
    String? error,
    bool clearError = false,
  }) {
    return RoomState(
      rooms: rooms ?? this.rooms,
      loading: loading ?? this.loading,
      error: clearError ? null : (error ?? this.error),
    );
  }

  @override
  List<Object?> get props => [rooms, loading, error];
}

/// Owns the room list and room/device membership for the whole app.
///
/// Membership changes are delegated to [RoomRepository] (which writes to the
/// device registry) and the registry cubit is then refreshed so Home and the
/// device-management screens never disagree about who lives where.
class RoomCubit extends Cubit<RoomState> {
  final RoomRepository _repository;
  final DeviceRegistryCubit? _registry;

  RoomCubit(this._repository, {DeviceRegistryCubit? registry})
    : _registry = registry,
      super(const RoomState(loading: true)) {
    load();
  }

  Future<void> load() async {
    emit(state.copyWith(loading: true));
    try {
      final rooms = await _repository.getRooms();
      if (isClosed) return;
      emit(RoomState(rooms: rooms));
    } catch (e) {
      AppLog.error('Rooms: load failed: $e');
      if (isClosed) return;
      emit(RoomState(rooms: state.rooms, error: 'Rooms could not be loaded.'));
    }
  }

  /// Creates a room. Returns the created room, or null when it was rejected.
  Future<Room?> create(String name, {String? iconName}) async {
    try {
      final room = await _repository.createRoom(
        Room(id: '', name: name, iconName: iconName),
      );
      await load();
      return room;
    } on ValidationException catch (e) {
      _fail(e.message);
      return null;
    } catch (e) {
      AppLog.error('Rooms: create failed: $e');
      _fail('The room could not be created.');
      return null;
    }
  }

  Future<bool> rename(String roomId, String name) async {
    final ok = await _guard(
      () => _repository.renameRoom(roomId, name),
      'The room could not be renamed.',
    );
    if (ok) await load();
    return ok;
  }

  /// Deletes a room. Devices are kept; they are moved to [reassignToRoomId] or
  /// become unassigned. The caller is responsible for confirming with the user.
  Future<bool> delete(String roomId, {String? reassignToRoomId}) async {
    final ok = await _guard(
      () => _repository.deleteRoom(roomId, reassignToRoomId: reassignToRoomId),
      'The room could not be deleted.',
    );
    if (ok) await _refreshDevices();
    return ok;
  }

  /// Moves a device into [roomId], or out of every room when null.
  Future<bool> assignDevice(String deviceId, String? roomId) async {
    final ok = await _guard(
      () => _repository.moveDeviceToRoom(deviceId, roomId),
      'The device could not be moved.',
    );
    if (ok) await _refreshDevices();
    return ok;
  }

  Future<bool> reorder(List<String> orderedIds) async {
    final ok = await _guard(
      () => _repository.reorderRooms(orderedIds),
      'The room order could not be saved.',
    );
    if (ok) await load();
    return ok;
  }

  /// Changes only the room's icon.
  Future<bool> setIcon(String roomId, String? iconName) async {
    final room = state.byId(roomId);
    if (room == null) {
      _fail('That room no longer exists.');
      return false;
    }
    final ok = await _guard(
      () => _repository.updateRoom(room.copyWith(iconName: iconName)),
      'The room could not be saved.',
    );
    if (ok) await load();
    return ok;
  }

  void clearError() {
    if (state.error == null) return;
    emit(state.copyWith(clearError: true));
  }

  // --- Internals -------------------------------------------------------------

  Future<void> _refreshDevices() async {
    await _registry?.refresh();
    if (!isClosed) await load();
  }

  Future<bool> _guard(Future<void> Function() action, String failure) async {
    try {
      await action();
      return true;
    } on ValidationException catch (e) {
      _fail(e.message);
      return false;
    } catch (e) {
      AppLog.error('Rooms: $failure $e');
      _fail(failure);
      return false;
    }
  }

  void _fail(String message) {
    if (isClosed) return;
    emit(state.copyWith(error: message));
  }
}
