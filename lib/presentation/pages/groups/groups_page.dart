// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:starlight/domain/entities/device.dart';
import 'package:starlight/domain/entities/device_group.dart';
import 'package:starlight/presentation/bloc/group/group_cubit.dart';
import 'package:starlight/presentation/bloc/registry/device_registry_cubit.dart';
import 'package:starlight/presentation/theme/app_theme.dart';
import 'package:starlight/presentation/widgets/error_banner.dart';

import 'group_detail_page.dart';

/// Device-group list (route `/groups`).
///
/// A group is a logical convenience over devices that already exist. The list
/// shows only real membership counts derived from the device registry, and
/// offers no control that the members cannot actually perform.
class GroupsPage extends StatelessWidget {
  const GroupsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final groupCubit = context.read<GroupCubit>();
    final registry = context.watch<DeviceRegistryCubit>();

    return Scaffold(
      appBar: AppBar(title: const Text('Groups')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _create(context),
        icon: const Icon(Icons.add),
        label: const Text('New group'),
      ),
      body: BlocConsumer<GroupCubit, GroupState>(
        listenWhen: (a, b) => a.error != b.error && b.error != null,
        listener: (context, state) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(state.error!)));
          groupCubit.clearError();
        },
        builder: (context, state) {
          if (state.loading && state.groups.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }
          if (state.groups.isEmpty) {
            return _EmptyGroups(
              hasDevices: registry.state.devices.isNotEmpty,
              onCreate: () => _create(context),
            );
          }
          return Column(
            children: [
              ErrorBanner(message: state.error),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                  itemCount: state.groups.length,
                  itemBuilder: (context, index) {
                    final group = state.groups[index];
                    return _GroupTile(
                      group: group,
                      devices: registry.state.devices
                          .where((d) => group.deviceIds.contains(d.id))
                          .toList(),
                      missing:
                          group.deviceIds.length -
                          registry.state.devices
                              .where((d) => group.deviceIds.contains(d.id))
                              .length,
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  static Future<void> _create(BuildContext context) async {
    final cubit = context.read<GroupCubit>();
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('New group'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          maxLength: 60,
          decoration: const InputDecoration(
            labelText: 'Group name',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (value) => Navigator.of(dialogContext).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.trim().isEmpty) return;
    final group = await cubit.create(name.trim());
    if (group == null || !context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => GroupDetailPage(groupId: group.id),
      ),
    );
  }
}

class _GroupTile extends StatelessWidget {
  final DeviceGroup group;
  final List<Device> devices;
  final int missing;

  const _GroupTile({
    required this.group,
    required this.devices,
    required this.missing,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.tokens;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => GroupDetailPage(groupId: group.id),
            ),
          ),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: tokens.border),
            ),
            padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: tokens.primary.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.widgets_outlined,
                    size: 20,
                    color: tokens.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        group.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _subtitle(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: missing > 0
                              ? tokens.warning
                              : tokens.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: 'Group actions',
                  onSelected: (value) {
                    if (value == 'rename') _rename(context);
                    if (value == 'delete') _delete(context);
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'rename', child: Text('Rename')),
                    PopupMenuItem(value: 'delete', child: Text('Delete')),
                  ],
                ),
                Icon(
                  Icons.chevron_right,
                  size: 20,
                  color: tokens.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _subtitle() {
    if (group.deviceIds.isEmpty) return 'No members — tap to add';
    final connected = devices.where((d) => d.isConnected).length;
    final parts = <String>[];
    if (missing > 0) {
      parts.add('$missing unavailable');
    }
    parts.add('$connected of ${devices.length} connected');
    return parts.join(' · ');
  }

  Future<void> _rename(BuildContext context) async {
    final cubit = context.read<GroupCubit>();
    final controller = TextEditingController(text: group.name);
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Rename group'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          maxLength: 60,
          decoration: const InputDecoration(
            labelText: 'Group name',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (value) => Navigator.of(dialogContext).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.trim().isEmpty) return;
    await cubit.rename(group.id, name.trim());
  }

  Future<void> _delete(BuildContext context) async {
    final cubit = context.read<GroupCubit>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Delete "${group.name}"?'),
        content: Text(
          group.deviceIds.isEmpty
              ? 'This group is empty. It will be removed.'
              : '${group.deviceIds.length} device(s) will be removed from this '
                    'group. The devices themselves are not affected.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await cubit.delete(group.id);
  }
}

class _EmptyGroups extends StatelessWidget {
  final bool hasDevices;
  final VoidCallback onCreate;

  const _EmptyGroups({required this.hasDevices, required this.onCreate});

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.widgets_outlined, size: 44, color: tokens.primary),
            const SizedBox(height: 14),
            Text(
              'No groups yet',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              hasDevices
                  ? 'A group controls several devices with one command. Every '
                        'device reports its own result.'
                  : 'Pair a device first, then group devices together.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: tokens.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: onCreate,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Create group'),
            ),
          ],
        ),
      ),
    );
  }
}
