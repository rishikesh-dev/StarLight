// SPDX-License-Identifier: Apache-2.0

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

import 'package:starlight/core/errors/exceptions.dart';
import 'package:starlight/core/utils/app_logger.dart';
import 'package:starlight/domain/entities/device_group.dart';
import 'package:starlight/domain/entities/execution_result.dart';
import 'package:starlight/domain/repositories/device_group_repository.dart';
import 'package:starlight/domain/usecases/execute_group_command.dart';

class GroupState extends Equatable {
  final List<DeviceGroup> groups;
  final bool loading;

  /// Id of the group whose command is currently being sent, if any.
  final String? runningGroupId;

  /// The most recent per-device report, for honest partial-failure feedback.
  final ExecutionReport? lastReport;

  /// The group [lastReport] belongs to.
  final String? lastReportGroupId;

  final String? error;

  const GroupState({
    this.groups = const [],
    this.loading = false,
    this.runningGroupId,
    this.lastReport,
    this.lastReportGroupId,
    this.error,
  });

  DeviceGroup? byId(String id) => groups.where((g) => g.id == id).firstOrNull;

  bool isRunning(String groupId) => runningGroupId == groupId;

  GroupState copyWith({
    List<DeviceGroup>? groups,
    bool? loading,
    String? runningGroupId,
    bool clearRunning = false,
    ExecutionReport? lastReport,
    bool clearReport = false,
    String? lastReportGroupId,
    String? error,
    bool clearError = false,
  }) {
    return GroupState(
      groups: groups ?? this.groups,
      loading: loading ?? this.loading,
      runningGroupId: clearRunning
          ? null
          : (runningGroupId ?? this.runningGroupId),
      lastReport: clearReport ? null : (lastReport ?? this.lastReport),
      lastReportGroupId: clearReport
          ? null
          : (lastReportGroupId ?? this.lastReportGroupId),
      error: clearError ? null : (error ?? this.error),
    );
  }

  @override
  List<Object?> get props => [
    groups,
    loading,
    runningGroupId,
    lastReport,
    lastReportGroupId,
    error,
  ];
}

/// Owns the device-group list and runs group commands.
///
/// Group commands are executed through [ExecuteGroupCommand], which sends to
/// every member sequentially via the single BLE owner and returns one result per
/// device. While a run is in flight another run for the *same* group is refused
/// rather than interleaved, so device state cannot be corrupted by overlapping
/// writes.
class GroupCubit extends Cubit<GroupState> {
  final DeviceGroupRepository _repository;
  final ExecuteGroupCommand _execute;

  GroupCubit(this._repository, this._execute)
    : super(const GroupState(loading: true)) {
    load();
  }

  Future<void> load() async {
    emit(state.copyWith(loading: true));
    try {
      final groups = await _repository.getGroups();
      if (isClosed) return;
      emit(state.copyWith(groups: groups, loading: false));
    } catch (e) {
      AppLog.error('Groups: load failed: $e');
      if (isClosed) return;
      emit(
        state.copyWith(loading: false, error: 'Groups could not be loaded.'),
      );
    }
  }

  Future<DeviceGroup?> create(String name, {String? iconName}) async {
    try {
      final group = await _repository.createGroup(
        DeviceGroup(id: '', name: name, iconName: iconName),
      );
      await load();
      return group;
    } on ValidationException catch (e) {
      _fail(e.message);
      return null;
    } catch (e) {
      AppLog.error('Groups: create failed: $e');
      _fail('The group could not be created.');
      return null;
    }
  }

  Future<bool> update(DeviceGroup group) async {
    final ok = await _guard(
      () => _repository.updateGroup(group),
      'The group could not be saved.',
    );
    if (ok) await load();
    return ok;
  }

  Future<bool> rename(String groupId, String name) => update(
    (state.byId(groupId) ?? DeviceGroup(id: groupId, name: name)).copyWith(
      name: name,
    ),
  );

  /// Deletes a group. Devices referenced by it are untouched.
  Future<bool> delete(String groupId) async {
    final ok = await _guard(
      () => _repository.deleteGroup(groupId),
      'The group could not be deleted.',
    );
    if (ok) await load();
    return ok;
  }

  Future<bool> addDevice(String groupId, String deviceId) async {
    final ok = await _guard(
      () => _repository.addDeviceToGroup(groupId, deviceId),
      'The device could not be added.',
    );
    if (ok) await load();
    return ok;
  }

  Future<bool> removeDevice(String groupId, String deviceId) async {
    final ok = await _guard(
      () => _repository.removeDeviceFromGroup(groupId, deviceId),
      'The device could not be removed.',
    );
    if (ok) await load();
    return ok;
  }

  Future<bool> setMembers(String groupId, List<String> deviceIds) async {
    final ok = await _guard(
      () => _repository.setGroupMembers(groupId, deviceIds),
      'The members could not be saved.',
    );
    if (ok) await load();
    return ok;
  }

  /// Whether [action] is safe to offer as a single control for every member.
  Future<bool> isSafeForAll(String groupId, String action) =>
      _execute.isSafeForAllMembers(groupId, action);

  /// The group-level actions every member supports.
  Future<List<String>> safeActions(String groupId) =>
      _execute.safeActionsFor(groupId);

  /// Sends one action to every member of [groupId].
  ///
  /// Returns the per-device report, or null when the run was refused because
  /// another run for the same group is already in flight.
  Future<ExecutionReport?> run(
    String groupId, {
    required String action,
    required Object? value,
  }) async {
    if (state.runningGroupId == groupId) {
      AppLog.info('Groups: run for $groupId refused, already running');
      return null;
    }
    emit(state.copyWith(runningGroupId: groupId));
    try {
      final report = await _execute(groupId, action: action, value: value);
      if (isClosed) return report;
      emit(
        state.copyWith(
          lastReport: report,
          lastReportGroupId: groupId,
          clearRunning: true,
        ),
      );
      return report;
    } catch (e) {
      AppLog.error('Groups: run for $groupId failed: $e');
      if (!isClosed) {
        emit(state.copyWith(clearRunning: true, error: 'The command failed.'));
      }
      return null;
    }
  }

  /// Clears the last report so its banner is not shown again.
  void clearReport() {
    if (state.lastReport == null) return;
    emit(state.copyWith(clearReport: true));
  }

  void clearError() {
    if (state.error == null) return;
    emit(state.copyWith(clearError: true));
  }

  Future<bool> _guard(Future<void> Function() action, String failure) async {
    try {
      await action();
      return true;
    } on ValidationException catch (e) {
      _fail(e.message);
      return false;
    } catch (e) {
      AppLog.error('Groups: $failure $e');
      _fail(failure);
      return false;
    }
  }

  void _fail(String message) {
    if (isClosed) return;
    emit(state.copyWith(error: message));
  }
}
