// SPDX-License-Identifier: Apache-2.0

import 'package:equatable/equatable.dart';

/// A logical grouping of devices in the home (Living Room, Bedroom, …).
///
/// Membership deliberately lives *on the device* ([Device.roomId]) rather than
/// on the room. That keeps a single source of truth: a device can only ever be
/// in one room, no device record is duplicated, and counts/status shown in the
/// UI are always derived from the real device registry rather than copied into
/// the room.
class Room extends Equatable {
  /// Stable identifier. Never reused once a room is deleted.
  final String id;

  /// Human-readable, non-blank name, unique case-insensitively.
  final String name;

  /// Optional presentation hint (mapped to an icon by the UI).
  final String? iconName;

  /// Position in the room list; lower comes first.
  final int sortOrder;

  const Room({
    required this.id,
    required this.name,
    this.iconName,
    this.sortOrder = 0,
  });

  Room copyWith({String? id, String? name, String? iconName, int? sortOrder}) {
    return Room(
      id: id ?? this.id,
      name: name ?? this.name,
      iconName: iconName ?? this.iconName,
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }

  @override
  List<Object?> get props => [id, name, iconName, sortOrder];
}
