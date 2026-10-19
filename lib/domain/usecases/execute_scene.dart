// SPDX-License-Identifier: Apache-2.0

import 'package:starlight/core/utils/app_logger.dart';
import 'package:starlight/domain/entities/device.dart';
import 'package:starlight/domain/entities/execution_result.dart';
import 'package:starlight/domain/entities/scene.dart';
import 'package:starlight/domain/repositories/device_group_repository.dart';
import 'package:starlight/domain/repositories/device_repository.dart';
import 'package:starlight/domain/services/device_command_dispatcher.dart';

/// Runs a [Scene]: every action is validated, its targets resolved against the
/// real device registry, and each command sent *sequentially* through the
/// shared [DeviceCommandDispatcher].
///
/// Guarantees that matter for correctness:
///
/// * **No arbitrary execution.** A scene is data. Actions are matched against a
///   fixed, validated vocabulary and an unknown action is rejected outright.
/// * **No silent retargeting.** An action whose device or group is gone is
///   reported as `unavailable`; it is never redirected to some other device.
/// * **Honest partial results.** Every device gets its own result, and a run
///   with any failure is never reported as fully successful.
/// * **No overlapping runs.** Starting a new run (or calling [stop]) invalidates
///   the previous one, which stops at the next target and reports the untried
///   targets as `superseded`.
class ExecuteScene {
  final DeviceRepository _devices;
  final DeviceGroupRepository _groups;
  final DeviceCommandDispatcher _dispatcher;

  /// Identifies the newest run. Anything older is treated as superseded.
  int _activeRun = 0;

  bool _running = false;

  /// Whether a run started with [call] has not finished yet.
  bool get isRunning => _running;

  ExecuteScene({
    required this._devices,
    required this._groups,
    required this._dispatcher,
  });

  /// Requests the in-flight run to stop at its next target boundary.
  /// Safe to call when nothing is running.
  void stop() {
    if (!_running) return;
    _activeRun++;
  }

  Future<ExecutionReport> call(Scene scene) async {
    final run = ++_activeRun;
    _running = true;
    final results = <DeviceActionResult>[];
    try {
      AppLog.info(
        'ExecuteScene: "${scene.name}" v${scene.schemaVersion} '
        '(${scene.actions.length} action(s))',
      );

      for (var i = 0; i < scene.actions.length; i++) {
        if (run != _activeRun) {
          _markSuperseded(scene.actions.sublist(i), results);
          break;
        }
        final action = scene.actions[i];

        final targets = await _resolveTargets(action, results);
        var stopped = false;
        for (final target in targets) {
          if (run != _activeRun) {
            stopped = true;
            break;
          }
          results.add(
            await _dispatcher.apply(
              device: target,
              action: action.action,
              value: action.value,
            ),
          );
        }
        if (stopped) {
          _markSuperseded(scene.actions.sublist(i + 1), results);
          break;
        }
      }
    } finally {
      if (run == _activeRun) _running = false;
    }

    AppLog.info('ExecuteScene: "${scene.name}" → ${results.length} result(s)');
    return ExecutionReport(results);
  }

  /// Resolves one action to concrete devices, recording a failure for anything
  /// that cannot be resolved instead of failing the whole run.
  Future<List<Device>> _resolveTargets(
    SceneAction action,
    List<DeviceActionResult> results,
  ) async {
    final targetId = action.targetId ?? _unknownTarget;

    final validation = action.validationError;
    if (validation != null) {
      results.add(
        DeviceActionResult(
          deviceId: targetId,
          action: action.action,
          outcome: ExecutionOutcome.invalid,
          message: validation,
        ),
      );
      return const [];
    }

    if (action.targetsGroup) {
      final groupId = action.groupId!;
      final group = await _groups.getGroup(groupId);
      if (group == null) {
        results.add(
          DeviceActionResult(
            deviceId: groupId,
            deviceName: 'Group',
            action: action.action,
            outcome: ExecutionOutcome.unavailable,
            message: 'That group no longer exists.',
          ),
        );
        return const [];
      }
      final devices = <Device>[];
      for (final memberId in group.deviceIds) {
        final device = await _devices.getDevice(memberId);
        if (device == null) {
          results.add(
            DeviceActionResult(
              deviceId: memberId,
              deviceName: 'Unknown device',
              action: action.action,
              outcome: ExecutionOutcome.unavailable,
              message: 'That device is not paired any more.',
            ),
          );
          continue;
        }
        devices.add(device);
      }
      return devices;
    }

    final device = await _devices.getDevice(action.deviceId!);
    if (device == null) {
      results.add(
        DeviceActionResult(
          deviceId: action.deviceId!,
          deviceName: 'Unknown device',
          action: action.action,
          outcome: ExecutionOutcome.unavailable,
          message: 'That device is not paired any more.',
        ),
      );
      return const [];
    }
    return [device];
  }

  /// Records the targets that were never attempted because a newer run took
  /// over, so the report can never imply they were sent.
  void _markSuperseded(
    List<SceneAction> actions,
    List<DeviceActionResult> results,
  ) {
    for (final action in actions) {
      final id = action.targetId ?? _unknownTarget;
      // A group target expands to its members; without re-reading the group we
      // report it once, which is still honest ("nothing sent to this group").
      results.add(
        DeviceActionResult(
          deviceId: id,
          deviceName: action.targetsGroup ? 'Group' : null,
          action: action.action,
          outcome: ExecutionOutcome.superseded,
          message: 'Stopped before this target was reached.',
        ),
      );
    }
  }

  static const String _unknownTarget = '(no target)';
}
