// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:starlight/domain/entities/device.dart';
import 'package:starlight/domain/entities/device_capability.dart';
import 'package:starlight/domain/entities/execution_result.dart';
import 'package:starlight/presentation/bloc/group/group_cubit.dart';
import 'package:starlight/presentation/bloc/registry/device_registry_cubit.dart';
import 'package:starlight/presentation/theme/app_theme.dart';
import 'package:starlight/presentation/widgets/error_banner.dart';
import 'package:starlight/presentation/widgets/execution_report_view.dart';

/// Group detail: membership management plus capability-aware group controls.
///
/// Only actions that *every* member supports are offered as a shared control;
/// when the group is mixed, those actions are hidden and the member list shows
/// what each device can actually do. Every run reports one outcome per device,
/// so a partial failure can never look like a success.
class GroupDetailPage extends StatefulWidget {
  final String groupId;

  const GroupDetailPage({super.key, required this.groupId});

  @override
  State<GroupDetailPage> createState() => _GroupDetailPageState();
}

class _GroupDetailPageState extends State<GroupDetailPage> {
  @override
  Widget build(BuildContext context) {
    final groupCubit = context.read<GroupCubit>();
    final registry = context.watch<DeviceRegistryCubit>();

    return BlocBuilder<GroupCubit, GroupState>(
      builder: (context, state) {
        final group = state.byId(widget.groupId);
        if (group == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Group')),
            body: const Center(child: Text('This group no longer exists.')),
          );
        }

        final members = <Device?>[
          for (final id in group.deviceIds) registry.state.byId(id),
        ];
        final known = members.whereType<Device>().toList();
        final common = _commonCapabilities(known);
        final running = state.isRunning(group.id);
        final report = state.lastReportGroupId == group.id
            ? state.lastReport
            : null;

        return Scaffold(
          appBar: AppBar(title: Text(group.name)),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: [
              ErrorBanner(message: state.error),
              _SummaryCard(
                total: group.deviceIds.length,
                known: known.length,
                connected: known.where((d) => d.isConnected).length,
              ),
              const SizedBox(height: 18),
              if (running) ...[
                const LinearProgressIndicator(minHeight: 3),
                const SizedBox(height: 14),
              ],
              if (report != null) ...[
                ExecutionReportView(report: report),
                const SizedBox(height: 18),
              ],
              Text(
                'Controls',
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                common.isEmpty
                    ? 'No action is supported by every member, so no shared '
                          'control is offered. Open a device for individual '
                          'controls.'
                    : 'Shared by every member',
                style: TextStyle(
                  fontSize: 12,
                  color: context.tokens.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              _Controls(
                groupId: group.id,
                common: common,
                enabled: !running && known.isNotEmpty,
                onRun: (action, value) =>
                    groupCubit.run(group.id, action: action, value: value),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Members',
                      style: Theme.of(context).textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => _addMembers(context, group.id),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Add'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (group.deviceIds.isEmpty)
                _EmptyMembers(onAdd: () => _addMembers(context, group.id))
              else
                for (var i = 0; i < group.deviceIds.length; i++)
                  _MemberTile(
                    deviceId: group.deviceIds[i],
                    device: members[i],
                    onRemove: () =>
                        groupCubit.removeDevice(group.id, group.deviceIds[i]),
                  ),
            ],
          ),
        );
      },
    );
  }

  /// Capabilities shared by all known members. A missing member empties the set,
  /// so a group with an unavailable reference offers no shared control.
  static Set<DeviceCapability> _commonCapabilities(List<Device> known) {
    if (known.isEmpty) return {};
    var common = known.first.capabilities.toSet();
    for (final device in known.skip(1)) {
      common = common.intersection(device.capabilities.toSet());
    }
    return common;
  }

  Future<void> _addMembers(BuildContext context, String groupId) async {
    final groupCubit = context.read<GroupCubit>();
    final registry = context.read<DeviceRegistryCubit>().state;
    final selected = await showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => _MemberPickerSheet(
        devices: registry.devices,
        current: groupCubit.state.byId(groupId)?.deviceIds ?? const [],
      ),
    );
    if (selected == null) return;
    for (final deviceId in selected) {
      await groupCubit.addDevice(groupId, deviceId);
    }
  }
}

class _SummaryCard extends StatelessWidget {
  final int total;
  final int known;
  final int connected;

  const _SummaryCard({
    required this.total,
    required this.known,
    required this.connected,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final missing = total - known;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: tokens.border),
      ),
      child: Row(
        children: [
          _Stat(label: 'Members', value: '$total'),
          const SizedBox(width: 12),
          _Stat(label: 'Connected', value: '$connected'),
          const SizedBox(width: 12),
          _Stat(label: 'Unavailable', value: '$missing'),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;

  const _Stat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final theme = Theme.of(context);
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11, color: tokens.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _Controls extends StatelessWidget {
  final String groupId;
  final Set<DeviceCapability> common;
  final bool enabled;
  final Future<void> Function(String action, Object? value) onRun;

  const _Controls({
    required this.groupId,
    required this.common,
    required this.enabled,
    required this.onRun,
  });

  @override
  Widget build(BuildContext context) {
    final canPower = common.contains(DeviceCapability.power);
    final canBrightness = common.contains(DeviceCapability.brightness);
    if (!canPower && !canBrightness) return const SizedBox.shrink();

    return Column(
      children: [
        if (canPower)
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: enabled ? () => onRun('power', false) : null,
                  icon: const Icon(Icons.power_settings_new, size: 18),
                  label: const Text('All off'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: enabled ? () => onRun('power', true) : null,
                  icon: const Icon(Icons.power_settings_new, size: 18),
                  label: const Text('All on'),
                ),
              ),
            ],
          ),
        if (canBrightness) ...[
          const SizedBox(height: 16),
          _BrightnessControl(enabled: enabled, onRun: onRun),
        ],
      ],
    );
  }
}

/// Brightness slider shared by the group.
///
/// Previews while dragging and only sends on release, so the UI never implies a
/// value was sent before it actually was.
class _BrightnessControl extends StatefulWidget {
  final bool enabled;
  final Future<void> Function(String action, Object? value) onRun;

  const _BrightnessControl({required this.enabled, required this.onRun});

  @override
  State<_BrightnessControl> createState() => _BrightnessControlState();
}

class _BrightnessControlState extends State<_BrightnessControl> {
  double _value = 50;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Row(
      children: [
        Icon(Icons.brightness_6, size: 20, color: tokens.onSurfaceVariant),
        Expanded(
          child: Slider(
            value: _value,
            max: 100,
            onChanged: widget.enabled
                ? (v) => setState(() => _value = v)
                : null,
            onChangeEnd: widget.enabled
                ? (v) => widget.onRun('brightness', (v * 10).round())
                : null,
          ),
        ),
        SizedBox(
          width: 38,
          child: Text(
            '${_value.round()}%',
            textAlign: TextAlign.end,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: tokens.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

class _MemberTile extends StatelessWidget {
  final String deviceId;
  final Device? device;
  final VoidCallback onRemove;

  const _MemberTile({
    required this.deviceId,
    required this.device,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final theme = Theme.of(context);
    final missing = device == null;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
        decoration: BoxDecoration(
          color: tokens.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: tokens.border),
        ),
        child: Row(
          children: [
            Icon(
              missing ? Icons.help_outline : Icons.lightbulb_outline,
              size: 20,
              color: missing ? tokens.warning : tokens.onSurfaceVariant,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    device?.name ?? 'Unavailable device',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    missing
                        ? 'No longer paired'
                        : device!.isConnected
                        ? 'Connected'
                        : 'Not connected',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: missing ? tokens.warning : tokens.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Remove from group',
              icon: const Icon(Icons.remove_circle_outline, size: 20),
              onPressed: onRemove,
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyMembers extends StatelessWidget {
  final VoidCallback onAdd;

  const _EmptyMembers({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: tokens.border),
      ),
      child: Column(
        children: [
          Text(
            'This group has no members yet.',
            style: TextStyle(color: tokens.onSurfaceVariant, fontSize: 13),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add devices'),
          ),
        ],
      ),
    );
  }
}

class _MemberPickerSheet extends StatefulWidget {
  final List<Device> devices;
  final List<String> current;

  const _MemberPickerSheet({required this.devices, required this.current});

  @override
  State<_MemberPickerSheet> createState() => _MemberPickerSheetState();
}

class _MemberPickerSheetState extends State<_MemberPickerSheet> {
  late final Set<String> _selected = {...widget.current};

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
            child: Text(
              'Members',
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          if (widget.devices.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              child: Text(
                'No devices are paired yet.',
                style: TextStyle(color: tokens.onSurfaceVariant),
              ),
            )
          else
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final device in widget.devices)
                    CheckboxListTile(
                      value: _selected.contains(device.id),
                      title: Text(
                        device.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        device.isConnected ? 'Connected' : 'Not connected',
                        style: TextStyle(
                          fontSize: 12,
                          color: tokens.onSurfaceVariant,
                        ),
                      ),
                      onChanged: (checked) => setState(() {
                        if (checked == true) {
                          _selected.add(device.id);
                        } else {
                          _selected.remove(device.id);
                        }
                      }),
                    ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            child: FilledButton(
              onPressed: widget.devices.isEmpty
                  ? null
                  : () => Navigator.of(context).pop(_selected.toList()),
              child: const Text('Save members'),
            ),
          ),
        ],
      ),
    );
  }
}
