// SPDX-License-Identifier: Apache-2.0

import 'package:starlight/core/utils/app_logger.dart';
import 'package:starlight/domain/entities/device.dart';
import 'package:starlight/domain/entities/device_capability.dart';
import 'package:starlight/domain/entities/execution_result.dart';
import 'package:starlight/domain/repositories/device_group_repository.dart';
import 'package:starlight/domain/repositories/device_repository.dart';
import 'package:starlight/domain/services/device_command_dispatcher.dart';

/// Runs one command against every member of a device group.
///
/// A group is a logical convenience, not a second transport: the command is sent
/// to each member *sequentially* through the shared
/// [DeviceCommandDispatcher], i.e. the same single BLE owner and serialised
/// command queue every other control uses. No additional connection is ever
/// opened, and nothing here claims the writes happen simultaneously.
///
/// Each member is validated on its own capabilities, so a mixed group yields
/// per-device outcomes (sent / unsupported / not connected / unavailable /
/// failed) and a partial failure can never be reported as a full success.
class ExecuteGroupCommand {
  final DeviceGroupRepository _groups;
  final DeviceRepository _devices;
  final DeviceCommandDispatcher _dispatcher;

  ExecuteGroupCommand({
    required this._groups,
    required this._devices,
    required this._dispatcher,
  });

  /// The actions a group control may offer, in presentation order.
  static const List<String> groupActionNames = [
    'power',
    'brightness',
    'color',
    'effect',
  ];

  /// Capabilities that **every** member supports.
  ///
  /// A group only offers a shared control for a capability in this set, so a
  /// control never appears merely because one member happens to support it. An
  /// unknown member (a forgotten device) empties the intersection, because a
  /// group with a dead reference cannot be driven as a unit.
  static Set<DeviceCapability> commonCapabilities(List<Device?> members) {
    if (members.isEmpty) return {};
    var common = members.first?.capabilities.toSet() ?? <DeviceCapability>{};
    for (final member in members.skip(1)) {
      if (member == null) return {};
      common = common.intersection(member.capabilities.toSet());
    }
    return common;
  }

  /// Whether [action] can be offered as a single group control.
  ///
  /// True only when the group has at least one member and *every* member's
  /// registry capabilities include it. This is what stops a control from
  /// appearing just because one capable member exists.
  Future<bool> isSafeForAllMembers(String groupId, String action) async {
    final capability = DeviceCommandDispatcher.capabilityFor(action);
    if (capability == null) return false;
    final group = await _groups.getGroup(groupId);
    if (group == null || group.deviceIds.isEmpty) return false;
    final members = [
      for (final memberId in group.deviceIds)
        await _devices.getDevice(memberId),
    ];
    return commonCapabilities(members).contains(capability);
  }

  /// The subset of [groupActionNames] that is safe for every member.
  Future<List<String>> safeActionsFor(String groupId) async {
    final safe = <String>[];
    for (final action in groupActionNames) {
      if (await isSafeForAllMembers(groupId, action)) safe.add(action);
    }
    return safe;
  }

  /// Applies `action` with `value` to every member of [groupId].
  ///
  /// Never throws; an unreadable or empty group produces a report explaining
  /// why instead of a crash or a silent success.
  Future<ExecutionReport> call(
    String groupId, {
    required String action,
    required Object? value,
  }) async {
    final group = await _groups.getGroup(groupId);
    if (group == null) {
      return ExecutionReport([
        DeviceActionResult(
          deviceId: groupId,
          deviceName: 'Group',
          action: action,
          outcome: ExecutionOutcome.unavailable,
          message: 'That group no longer exists.',
        ),
      ]);
    }
    if (group.deviceIds.isEmpty) {
      return const ExecutionReport.empty();
    }

    AppLog.info(
      'ExecuteGroupCommand: "${group.name}" $action → '
      '${group.deviceIds.length} member(s)',
    );

    final results = <DeviceActionResult>[];
    for (final memberId in group.deviceIds) {
      final device = await _devices.getDevice(memberId);
      if (device == null) {
        results.add(
          DeviceActionResult(
            deviceId: memberId,
            deviceName: 'Unknown device',
            action: action,
            outcome: ExecutionOutcome.unavailable,
            message: 'That device is not paired any more.',
          ),
        );
        continue;
      }
      results.add(
        await _dispatcher.apply(device: device, action: action, value: value),
      );
    }
    return ExecutionReport(results);
  }
}
