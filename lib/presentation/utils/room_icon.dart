// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';

/// Maps a room's optional `iconName` to an icon.
///
/// Kept in one place so the Home selector, the rooms manager and the room
/// picker all show the same glyph for the same stored value, with a sane
/// fallback for unknown or missing names.
IconData roomIconFor(String? iconName) => switch (iconName) {
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

/// The icons a user can pick from when creating or editing a room.
const List<RoomIconChoice> kRoomIconChoices = [
  RoomIconChoice('living', 'Living'),
  RoomIconChoice('bedroom', 'Bedroom'),
  RoomIconChoice('work', 'Office'),
  RoomIconChoice('kitchen', 'Kitchen'),
  RoomIconChoice('bathroom', 'Bathroom'),
  RoomIconChoice('restaurant', 'Dining'),
  RoomIconChoice('garage', 'Garage'),
  RoomIconChoice('yard', 'Outdoor'),
];

class RoomIconChoice {
  final String id;
  final String label;

  const RoomIconChoice(this.id, this.label);
}
