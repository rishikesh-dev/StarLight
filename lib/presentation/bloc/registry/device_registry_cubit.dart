// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

import 'package:starlight/core/utils/app_logger.dart';
import 'package:starlight/domain/entities/device.dart';
import 'package:starlight/domain/entities/device_event.dart';
import 'package:starlight/domain/repositories/device_repository.dart';

/// Reactive view of the device registry.
///
/// [DeviceRepository] is the single source of truth for configured devices but
/// is not a stream, so this cubit owns the subscription that keeps the UI in
/// step with it: any registry event (connect/disconnect/error) triggers a
/// reload, and callers that mutate the registry directly (room or group
/// membership) call [refresh].
class DeviceRegistryState extends Equatable {
  final List<Device> devices;
  final bool loading;

  const DeviceRegistryState({this.devices = const [], this.loading = false});

  bool get isEmpty => devices.isEmpty;

  int get connectedCount => devices.where((d) => d.isConnected).length;

  /// Devices assigned to [roomId]; pass null for unassigned devices.
  List<Device> inRoom(String? roomId) => devices
      .where((d) => roomId == null ? d.roomId == null : d.roomId == roomId)
      .toList();

  Device? byId(String id) => devices.where((d) => d.id == id).firstOrNull;

  @override
  List<Object?> get props => [devices, loading];
}

class DeviceRegistryCubit extends Cubit<DeviceRegistryState> {
  final DeviceRepository _repository;
  StreamSubscription<DeviceEvent>? _eventsSub;

  DeviceRegistryCubit(this._repository) : super(const DeviceRegistryState()) {
    _eventsSub = _repository.events.listen((_) => refresh());
    refresh();
  }

  Future<void> refresh() async {
    try {
      final devices = await _repository.getDevices();
      if (isClosed) return;
      emit(DeviceRegistryState(devices: devices));
    } catch (e) {
      AppLog.warn('DeviceRegistry: refresh failed: $e');
    }
  }

  @override
  Future<void> close() async {
    await _eventsSub?.cancel();
    _eventsSub = null;
    return super.close();
  }
}
