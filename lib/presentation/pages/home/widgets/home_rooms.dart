// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';

import 'package:starlight/domain/entities/room.dart';
import 'package:starlight/presentation/theme/app_theme.dart';

/// Horizontal scope selector for the Home dashboard.
///
/// Shows the "Home" overview and then any persisted rooms that actually exist.
/// Each chip shows the real device count for that room. With no rooms stored,
/// only the real overview scope is shown. No fake rooms are invented.
class HomeRooms extends StatelessWidget {
  final List<Room> rooms;
  final String? selectedRoomId;
  final ValueChanged<String?> onSelect;
  final Map<String, int> roomDeviceCounts;

  const HomeRooms({
    super.key,
    this.rooms = const [],
    this.selectedRoomId,
    required this.onSelect,
    this.roomDeviceCounts = const {},
  });

  @override
  Widget build(BuildContext context) {
    // The selector always renders the real "Home" overview (every device
    // StarLight knows); persisted rooms follow it with their real counts.
    // With no rooms stored only the overview scope is shown — no fake rooms.
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        children: [
          _RoomChip(
            label: 'Home',
            icon: Icons.home_outlined,
            count: roomDeviceCounts['__home__'] ?? 0,
            selected: selectedRoomId == null,
            onTap: () => onSelect(null),
          ),
          for (final room in rooms) ...[
            const SizedBox(width: 8),
            _RoomChip(
              label: room.name,
              icon: _iconFor(room.iconName),
              count: roomDeviceCounts[room.id] ?? 0,
              selected: room.id == selectedRoomId,
              onTap: () => onSelect(room.id),
            ),
          ],
        ],
      ),
    );
  }

  static IconData _iconFor(String? iconName) {
    return switch (iconName) {
      'living' => Icons.weekend_outlined,
      'bedroom' => Icons.bed_outlined,
      'work' => Icons.work_outline,
      'kitchen' => Icons.kitchen_outlined,
      'bathroom' => Icons.bathtub_outlined,
      'restaurant' => Icons.restaurant_outlined,
      'garage' => Icons.garage_outlined,
      'yard' => Icons.yard_outlined,
      _ => Icons.meeting_room_outlined,
    };
  }
}

class _RoomChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  const _RoomChip({
    required this.label,
    required this.icon,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Semantics(
      label: '$label, $count device${count == 1 ? '' : 's'}',
      button: true,
      selected: selected,
      child: Material(
        color: selected
            ? tokens.primary.withValues(alpha: 0.14)
            : tokens.surfaceHigh,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(999),
          side: BorderSide(
            color: selected ? tokens.primary : tokens.onSurfaceVariant,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 18,
                  color: selected ? tokens.primary : tokens.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected ? tokens.primary : tokens.onSurface,
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: selected
                        ? tokens.primary.withValues(alpha: 0.2)
                        : tokens.surfaceHigh.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    count.toString(),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: selected
                          ? tokens.primary
                          : tokens.onSurfaceVariant,
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
