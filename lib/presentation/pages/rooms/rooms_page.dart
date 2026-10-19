// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:starlight/domain/entities/device.dart';
import 'package:starlight/domain/entities/room.dart';
import 'package:starlight/presentation/bloc/registry/device_registry_cubit.dart';
import 'package:starlight/presentation/bloc/room/room_cubit.dart';
import 'package:starlight/presentation/theme/app_theme.dart';
import 'package:starlight/presentation/utils/room_icon.dart';
import 'package:starlight/presentation/widgets/error_banner.dart';

/// Room management (route `/rooms`).
///
/// Rooms are a pure grouping over the device registry: creating, renaming,
/// reordering and deleting a room never touches a device record. Deleting a
/// room only ever reassigns or unassigns its devices, and the page always states
/// where they go before the destructive step runs.
class RoomsPage extends StatelessWidget {
  const RoomsPage({super.key});

  static const String _unassigned = '__unassigned__';
  static const String _pickPrompt = '__pick__';

  @override
  Widget build(BuildContext context) {
    final roomCubit = context.read<RoomCubit>();
    final registry = context.watch<DeviceRegistryCubit>();

    return Scaffold(
      appBar: AppBar(title: const Text('Rooms')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _editRoom(context),
        icon: const Icon(Icons.add),
        label: const Text('New room'),
      ),
      body: BlocConsumer<RoomCubit, RoomState>(
        listenWhen: (a, b) => a.error != b.error && b.error != null,
        listener: (context, state) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(state.error!)));
          roomCubit.clearError();
        },
        builder: (context, state) {
          if (state.loading && state.rooms.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }
          if (state.rooms.isEmpty) {
            return _EmptyRooms(
              hasDevices: registry.state.devices.isNotEmpty,
              onCreate: () => _editRoom(context),
            );
          }
          return Column(
            children: [
              ErrorBanner(message: state.error),
              Expanded(
                child: ReorderableListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                  itemCount: state.rooms.length,
                  onReorder: (from, to) =>
                      _reorder(context, state.rooms, from, to),
                  itemBuilder: (context, index) {
                    final room = state.rooms[index];
                    return _RoomTile(
                      key: ValueKey(room.id),
                      room: room,
                      index: index,
                      devices: registry.state.inRoom(room.id),
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

  static void _reorder(
    BuildContext context,
    List<Room> rooms,
    int from,
    int to,
  ) {
    final ids = rooms.map((r) => r.id).toList();
    // ReorderableListView reports the destination index before removal.
    final target = to > from ? to - 1 : to;
    ids.insert(target, ids.removeAt(from));
    context.read<RoomCubit>().reorder(ids);
  }

  static Future<void> _editRoom(BuildContext context, {Room? room}) async {
    final cubit = context.read<RoomCubit>();
    final draft = await showModalBottomSheet<_RoomDraft>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _RoomEditorSheet(room: room),
    );
    if (draft == null) return;

    if (room == null) {
      await cubit.create(draft.name, iconName: draft.iconName);
      return;
    }
    final nameChanged = draft.name != room.name;
    final iconChanged = draft.iconName != room.iconName;
    if (nameChanged) await cubit.rename(room.id, draft.name);
    if (iconChanged) await cubit.setIcon(room.id, draft.iconName);
  }

  static Future<void> _deleteRoom(
    BuildContext context,
    Room room,
    List<Device> devices,
  ) async {
    final roomCubit = context.read<RoomCubit>();
    final others = roomCubit.state.rooms.where((r) => r.id != room.id).toList();

    // Explicit reassignment policy: devices are kept, and the user chooses
    // whether they move somewhere or simply lose their room.
    final destination = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Delete "${room.name}"?'),
        content: Text(
          devices.isEmpty
              ? 'This room is empty. It will be removed.'
              : '${devices.length} device(s) are in this room. Devices are '
                    'never deleted — choose where they go.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(_unassigned),
            child: const Text('Leave without a room'),
          ),
          if (others.isNotEmpty)
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(_pickPrompt),
              child: const Text('Move to…'),
            ),
        ],
      ),
    );
    if (destination == null) return;

    String? reassignTo;
    if (destination == _pickPrompt) {
      reassignTo = await showDialog<String>(
        context: context,
        builder: (dialogContext) => SimpleDialog(
          title: const Text('Move devices to'),
          children: [
            for (final other in others)
              SimpleDialogOption(
                onPressed: () => Navigator.of(dialogContext).pop(other.id),
                child: Row(
                  children: [
                    Icon(roomIconFor(other.iconName), size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        other.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      );
      if (reassignTo == null) return;
    } else {
      reassignTo = null;
    }

    await roomCubit.delete(room.id, reassignToRoomId: reassignTo);
  }

  static Future<void> _assignDevices(BuildContext context, Room room) async {
    final registry = context.read<DeviceRegistryCubit>().state;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) =>
          _DeviceAssignmentSheet(room: room, devices: registry.devices),
    );
  }
}

class _RoomTile extends StatelessWidget {
  final Room room;
  final int index;
  final List<Device> devices;

  const _RoomTile({
    super.key,
    required this.room,
    required this.index,
    required this.devices,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.tokens;
    final connected = devices.where((d) => d.isConnected).length;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => RoomsPage._assignDevices(context, room),
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
                    roomIconFor(room.iconName),
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
                        room.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        devices.isEmpty
                            ? 'No devices — tap to assign'
                            : connected == devices.length
                            ? '${devices.length} device(s), all connected'
                            : '$connected of ${devices.length} connected',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: tokens.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: 'Room actions',
                  onSelected: (value) {
                    if (value == 'rename') {
                      RoomsPage._editRoom(context, room: room);
                    } else if (value == 'delete') {
                      RoomsPage._deleteRoom(context, room, devices);
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'rename', child: Text('Rename')),
                    PopupMenuItem(value: 'delete', child: Text('Delete')),
                  ],
                ),
                ReorderableDragStartListener(
                  index: index,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Icon(
                      Icons.drag_handle,
                      size: 20,
                      color: tokens.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Per-device room picker.
///
/// Membership is stored on the device (`Device.roomId`), so this writes each
/// device directly instead of editing a copy of the list on the room.
class _DeviceAssignmentSheet extends StatelessWidget {
  final Room room;
  final List<Device> devices;

  const _DeviceAssignmentSheet({required this.room, required this.devices});

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final theme = Theme.of(context);
    final roomCubit = context.read<RoomCubit>();

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
            child: Text(
              room.name,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Text(
              'Assign each device to a room.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: tokens.onSurfaceVariant,
              ),
            ),
          ),
          if (devices.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
              child: Text(
                'No devices are paired yet. Pair a device first, then assign it '
                'to a room.',
                style: TextStyle(color: tokens.onSurfaceVariant),
              ),
            )
          else
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final device in devices)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                      child: DropdownButtonFormField<String?>(
                        initialValue: device.roomId,
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText: device.name,
                          helperText: device.isConnected
                              ? 'Connected'
                              : 'Not connected',
                          border: const OutlineInputBorder(),
                          isDense: true,
                        ),
                        items: [
                          const DropdownMenuItem<String?>(
                            value: null,
                            child: Text('No room'),
                          ),
                          for (final option in roomCubit.state.rooms)
                            DropdownMenuItem<String?>(
                              value: option.id,
                              child: Text(
                                option.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: (value) =>
                            roomCubit.assignDevice(device.id, value),
                      ),
                    ),
                ],
              ),
            ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

class _RoomEditorSheet extends StatefulWidget {
  final Room? room;

  const _RoomEditorSheet({this.room});

  @override
  State<_RoomEditorSheet> createState() => _RoomEditorSheetState();
}

class _RoomEditorSheetState extends State<_RoomEditorSheet> {
  late final TextEditingController _name;
  late String? _iconName;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.room?.name ?? '');
    _iconName = widget.room?.iconName;
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    Navigator.of(context).pop(_RoomDraft(name: name, iconName: _iconName));
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          20,
          20,
          20 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.room == null ? 'New room' : 'Rename room',
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _name,
                autofocus: widget.room == null,
                textCapitalization: TextCapitalization.words,
                maxLength: 60,
                decoration: const InputDecoration(
                  labelText: 'Room name',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 12),
              Text(
                'Icon',
                style: TextStyle(fontSize: 12, color: tokens.onSurfaceVariant),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final choice in kRoomIconChoices)
                    _IconChoice(
                      choice: choice,
                      selected: _iconName == choice.id,
                      onTap: () => setState(() => _iconName = choice.id),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _submit,
                child: Text(widget.room == null ? 'Create room' : 'Save'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _IconChoice extends StatelessWidget {
  final RoomIconChoice choice;
  final bool selected;
  final VoidCallback onTap;

  const _IconChoice({
    required this.choice,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? tokens.primary.withValues(alpha: 0.16)
              : tokens.surface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: selected ? tokens.primary : tokens.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              roomIconFor(choice.id),
              size: 16,
              color: selected ? tokens.primary : tokens.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Text(
              choice.label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? tokens.primary : tokens.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyRooms extends StatelessWidget {
  final bool hasDevices;
  final VoidCallback onCreate;

  const _EmptyRooms({required this.hasDevices, required this.onCreate});

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
            Icon(Icons.meeting_room_outlined, size: 44, color: tokens.primary),
            const SizedBox(height: 14),
            Text(
              'No rooms yet',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              hasDevices
                  ? 'Group your devices into rooms, then assign each device to '
                        'the room it belongs to.'
                  : 'Pair a device first, then create a room to group your '
                        'devices.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: tokens.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: onCreate,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Create room'),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoomDraft {
  final String name;
  final String? iconName;

  const _RoomDraft({required this.name, this.iconName});
}
