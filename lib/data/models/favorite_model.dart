// SPDX-License-Identifier: Apache-2.0

import 'package:starlight/domain/entities/favorite.dart';

/// Serializable model for a persisted [Favorite].
class FavoriteModel {
  final String id;
  final String type;
  final String itemId;
  final int sortOrder;

  const FavoriteModel({
    required this.id,
    required this.type,
    required this.itemId,
    this.sortOrder = 0,
  });

  Favorite toEntity() => Favorite(
    id: id,
    type: _parseType(type),
    itemId: itemId,
    sortOrder: sortOrder,
  );

  factory FavoriteModel.fromEntity(Favorite favorite) => FavoriteModel(
    id: favorite.id,
    type: favorite.type.id,
    itemId: favorite.itemId,
    sortOrder: favorite.sortOrder,
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'type': type,
    'itemId': itemId,
    'sortOrder': sortOrder,
  };

  factory FavoriteModel.fromMap(Map<String, dynamic> map) => FavoriteModel(
    id: map['id'] as String,
    type: map['type'] as String,
    itemId: map['itemId'] as String,
    sortOrder: (map['sortOrder'] as int?) ?? 0,
  );

  static FavoriteType _parseType(String id) {
    for (final t in FavoriteType.values) {
      if (t.id == id) return t;
    }
    return FavoriteType.device;
  }
}
