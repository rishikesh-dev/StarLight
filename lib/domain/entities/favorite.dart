// SPDX-License-Identifier: Apache-2.0

import 'package:equatable/equatable.dart';

/// Type of item that can be favorited.
enum FavoriteType {
  device('device', 'Device'),
  scene('scene', 'Scene'),
  room('room', 'Room');

  const FavoriteType(this.id, this.label);
  final String id;
  final String label;
}

/// Represents a favorite item for quick access on the home screen.
class Favorite extends Equatable {
  final String id;
  final FavoriteType type;
  final String itemId; // deviceId, sceneId, or roomId
  final int sortOrder;

  const Favorite({
    required this.id,
    required this.type,
    required this.itemId,
    this.sortOrder = 0,
  });

  Favorite copyWith({
    String? id,
    FavoriteType? type,
    String? itemId,
    int? sortOrder,
  }) {
    return Favorite(
      id: id ?? this.id,
      type: type ?? this.type,
      itemId: itemId ?? this.itemId,
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }

  @override
  List<Object?> get props => [id, type, itemId, sortOrder];
}
