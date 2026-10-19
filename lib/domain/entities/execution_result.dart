// SPDX-License-Identifier: Apache-2.0

import 'package:equatable/equatable.dart';

/// The outcome of applying a single command to a single device.
///
/// Distinct values are kept for the conditions a user needs to tell apart, so a
/// group or scene run never collapses "the device is offline" and "the device
/// does not support this" into a generic failure.
enum ExecutionOutcome {
  success,
  unsupported,
  notConnected,
  unavailable,

  /// The stored action itself was rejected before anything was sent.
  invalid,

  /// The run was stopped, or a newer run took over, before this target was
  /// reached. Reported so a partial run is never mistaken for a full one.
  superseded,

  failed,
}

/// Result of applying one action to one device.
class DeviceActionResult extends Equatable {
  final String deviceId;
  final String? deviceName;

  /// The scene/group action name, e.g. `power`, `brightness`, `color`.
  final String action;
  final ExecutionOutcome outcome;

  /// Human-readable detail for a non-success outcome (never a raw stack trace).
  final String? message;

  const DeviceActionResult({
    required this.deviceId,
    required this.action,
    required this.outcome,
    this.deviceName,
    this.message,
  });

  bool get success => outcome == ExecutionOutcome.success;

  /// A short, honest, user-facing description.
  String get label => deviceName ?? deviceId;

  @override
  List<Object?> get props => [deviceId, action, outcome, deviceName, message];
}

/// The full, ordered result of executing a scene or a group action.
class ExecutionReport extends Equatable {
  /// One entry per device/action actually attempted, in execution order.
  final List<DeviceActionResult> results;

  const ExecutionReport(this.results);

  const ExecutionReport.empty() : results = const [];

  bool get isEmpty => results.isEmpty;

  int get successCount =>
      results.where((r) => r.outcome == ExecutionOutcome.success).length;
  int get failureCount => results.length - successCount;

  /// Targets never attempted because the run stopped early.
  int get skippedCount =>
      results.where((r) => r.outcome == ExecutionOutcome.superseded).length;

  bool get allSucceeded => results.isNotEmpty && failureCount == 0;
  bool get anySucceeded => successCount > 0;
  bool get hasFailures => failureCount > 0;

  /// Honest one-line summary.
  ///
  /// Wording deliberately says "sent"/"not sent": a successful write only means
  /// the transport accepted the command, never that the hardware visibly
  /// changed.
  String get summary {
    if (results.isEmpty) return 'Nothing to run.';
    if (skippedCount > 0) {
      return 'Stopped early — sent to $successCount of ${results.length} targets.';
    }
    if (allSucceeded) {
      return results.length == 1
          ? 'Sent.'
          : 'Sent to all ${results.length} targets.';
    }
    if (!anySucceeded) {
      return results.length == 1
          ? 'Not sent: ${results.first.message ?? 'the command was rejected'}'
          : 'Nothing was sent (${results.length} targets).';
    }
    return 'Sent to $successCount of ${results.length} targets.';
  }

  /// The first non-success result, for a detailed follow-up message.
  DeviceActionResult? get firstFailure =>
      results.where((r) => r.outcome != ExecutionOutcome.success).firstOrNull;

  @override
  List<Object?> get props => [results];
}
