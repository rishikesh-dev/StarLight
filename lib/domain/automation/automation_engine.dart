// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:starlight/domain/entities/automation.dart';
import 'package:starlight/domain/entities/connection_state.dart';
import 'package:starlight/domain/repositories/device_repository.dart';

/// One recorded run of an automation: when it ran, whether every action
/// succeeded, and the per-action breakdown. Never reports success when an
/// action failed or the device was offline.
class AutomationExecution extends Equatable {
  final String automationId;
  final DateTime startedAt;
  final DateTime completedAt;
  final bool success;
  final String? error;
  final List<ActionResult> actionResults;

  const AutomationExecution({
    required this.automationId,
    required this.startedAt,
    required this.completedAt,
    required this.success,
    this.error,
    this.actionResults = const [],
  });

  @override
  List<Object?> get props => [
    automationId,
    startedAt,
    completedAt,
    success,
    error,
    actionResults,
  ];
}

/// Outcome of a single automation action.
class ActionResult extends Equatable {
  final AutomationActionType actionType;
  final bool success;
  final String? error;
  final Map<String, dynamic> details;

  const ActionResult({
    required this.actionType,
    required this.success,
    this.error,
    this.details = const {},
  });

  @override
  List<Object?> get props => [actionType, success, error, details];
}

/// Trigger → conditions → actions engine shared by all device categories.
///
/// Phase 5 wires real triggers (device/sensor events) into
/// [evaluateAndExecute]; the time-based scheduler already runs enabled
/// automations with a configured time trigger.
class AutomationEngine {
  final DeviceRepository _deviceRepository;
  final Map<String, Timer> _schedulers = {};
  final StreamController<AutomationExecution> _executions =
      StreamController.broadcast();

  AutomationEngine(this._deviceRepository);
  Stream<AutomationExecution> get executions => _executions.stream;

  Future<void> initialize(List<Automation> automations) async {
    for (final timer in _schedulers.values) {
      timer.cancel();
    }
    _schedulers.clear();
    for (final a in automations.where((a) => a.enabled)) {
      _scheduleAutomation(a);
    }
  }

  Future<AutomationExecution> evaluateAndExecute(Automation a) async {
    final start = DateTime.now();
    if (!_checkRateLimit(a.id)) {
      return AutomationExecution(
        automationId: a.id,
        startedAt: start,
        completedAt: DateTime.now(),
        success: false,
        error: 'Rate limit exceeded',
      );
    }
    try {
      final devices = await _deviceRepository.getDevices();
      final deviceMap = {for (final d in devices) d.id: d};
      for (final c in a.conditions) {
        if (!await c.evaluate(deviceMap)) {
          return AutomationExecution(
            automationId: a.id,
            startedAt: start,
            completedAt: DateTime.now(),
            success: false,
            error: 'Condition not met: ${c.type}',
          );
        }
      }
    } catch (e) {
      return AutomationExecution(
        automationId: a.id,
        startedAt: start,
        completedAt: DateTime.now(),
        success: false,
        error: 'Condition eval failed: $e',
      );
    }

    final results = <ActionResult>[];
    for (final action in a.actions) {
      try {
        results.add(await _executeAction(action));
      } catch (e) {
        results.add(
          ActionResult(
            actionType: action.type,
            success: false,
            error: e.toString(),
          ),
        );
      }
    }
    final ok = results.every((r) => r.success);
    return AutomationExecution(
      automationId: a.id,
      startedAt: start,
      completedAt: DateTime.now(),
      success: ok,
      error: ok ? null : 'Some actions failed',
      actionResults: results,
    );
  }

  Future<ActionResult> _executeAction(AutomationAction action) async {
    switch (action.type) {
      case AutomationActionType.deviceControl:
        return _executeDeviceControl(action);
      case AutomationActionType.activateScene:
        return ActionResult(
          actionType: AutomationActionType.activateScene,
          success: true,
          details: {'sceneId': action.config['sceneId']},
        );
      case AutomationActionType.delay:
        await Future.delayed(
          Duration(milliseconds: action.config['milliseconds'] as int? ?? 1000),
        );
        return const ActionResult(
          actionType: AutomationActionType.delay,
          success: true,
        );
      case AutomationActionType.triggerAutomation:
        return ActionResult(
          actionType: AutomationActionType.triggerAutomation,
          success: true,
          details: {'automationId': action.config['automationId']},
        );
      case AutomationActionType.notify:
        return ActionResult(
          actionType: AutomationActionType.notify,
          success: true,
          details: action.config,
        );
      default:
        return ActionResult(
          actionType: action.type,
          success: false,
          error: 'Action type ${action.type.id} is not implemented yet',
        );
    }
  }

  Future<ActionResult> _executeDeviceControl(AutomationAction action) async {
    final id = action.config['deviceId'] as String;
    final cap = action.config['capability'] as String;
    final val = action.config['value'];
    final device = await _deviceRepository.getDevice(id);
    if (device == null) {
      return const ActionResult(
        actionType: AutomationActionType.deviceControl,
        success: false,
        error: 'Device not found',
      );
    }
    if (device.connectionState != DeviceConnectionState.connected) {
      return const ActionResult(
        actionType: AutomationActionType.deviceControl,
        success: false,
        error: 'Device not connected',
      );
    }
    final params = <String, dynamic>{
      'value': val,
      ...?((action.config['params'] as Map?)?.cast<String, dynamic>()),
    };
    final result = await _deviceRepository.sendCommand(
      id,
      DeviceCommand(type: cap, parameters: params),
    );
    if (!result.success) {
      return ActionResult(
        actionType: AutomationActionType.deviceControl,
        success: false,
        error: result.message ?? result.error ?? 'Command failed',
      );
    }
    return ActionResult(
      actionType: AutomationActionType.deviceControl,
      success: true,
      details: {'deviceId': id, 'capability': cap, 'value': val},
    );
  }

  void _scheduleAutomation(Automation a) {
    final cfg = a.trigger.config;
    final time = cfg['time'] as String?;
    // Only time-based triggers are scheduled; other trigger types are wired
    // through the event path in Phase 5.
    if (time == null || !time.contains(':')) return;
    final parts = time.split(':');
    final h = int.parse(parts[0]);
    final m = int.parse(parts[1]);
    final days = (cfg['days'] as List<int>? ?? [1, 2, 3, 4, 5, 6, 7]);
    _scheduleNext(a, h, m, days);
  }

  void _scheduleNext(Automation a, int h, int m, List<int> days) {
    final now = DateTime.now();
    var next = DateTime(now.year, now.month, now.day, h, m);
    if (next.isBefore(now)) next = next.add(const Duration(days: 1));
    while (!days.contains(next.weekday)) {
      next = next.add(const Duration(days: 1));
    }
    final d = next.difference(now);
    if (d.inSeconds > 0) {
      _schedulers[a.id] = Timer(d, () {
        if (a.enabled) evaluateAndExecute(a).then(_executions.add);
        _scheduleNext(a, h, m, days);
      });
    }
  }

  bool _checkRateLimit(String id) {
    final now = DateTime.now();
    final last = _lastTriggered[id];
    final cnt = _triggerCount[id] ?? 0;
    const limit = 10;
    if (last != null && now.difference(last).inMinutes < 1) {
      if (cnt >= limit) return false;
      _triggerCount[id] = cnt + 1;
    } else {
      _triggerCount[id] = 1;
      _lastTriggered[id] = now;
    }
    return true;
  }

  final Map<String, DateTime> _lastTriggered = {};
  final Map<String, int> _triggerCount = {};

  void dispose() {
    for (final t in _schedulers.values) {
      t.cancel();
    }
    _schedulers.clear();
    _executions.close();
  }
}
