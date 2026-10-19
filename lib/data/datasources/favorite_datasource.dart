// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:starlight/core/utils/app_logger.dart';

import '../models/favorite_model.dart';

/// Data source for persisting favorites to SharedPreferences.
class FavoriteDataSource {
  static const String favoritesKey = 'starlight_favorites_v1';

  final SharedPreferences prefs;

  FavoriteDataSource(this.prefs);

  Future<List<FavoriteModel>> loadFavorites() async {
    AppLog.debug('loadFavorites: reading key "$favoritesKey"');
    final raw = prefs.getString(favoritesKey);
    if (raw == null || raw.isEmpty) {
      AppLog.debug('loadFavorites: no saved favorites');
      return const [];
    }
    try {
      final List<dynamic> json = jsonDecode(raw) as List<dynamic>;
      return json
          .map((e) => FavoriteModel.fromMap(Map<String, dynamic>.from(e)))
          .toList();
    } catch (e) {
      AppLog.warn('loadFavorites: failed to decode, returning empty: $e');
      return const [];
    }
  }

  Future<void> saveFavorites(List<FavoriteModel> favorites) async {
    final json = favorites.map((f) => f.toMap()).toList();
    await prefs.setString(favoritesKey, jsonEncode(json));
    AppLog.debug('saveFavorites: saved ${favorites.length} favorite(s)');
  }

  Future<void> addFavorite(FavoriteModel favorite) async {
    final favorites = await loadFavorites();
    final index = favorites.indexWhere(
      (f) => f.type == favorite.type && f.itemId == favorite.itemId,
    );
    if (index >= 0) {
      favorites[index] = favorite;
    } else {
      favorites.add(favorite);
    }
    await saveFavorites(favorites);
  }

  Future<void> removeFavorite(String type, String itemId) async {
    final favorites = await loadFavorites();
    favorites.removeWhere((f) => f.type == type && f.itemId == itemId);
    await saveFavorites(favorites);
  }

  Future<bool> isFavorite(String type, String itemId) async {
    final favorites = await loadFavorites();
    return favorites.any((f) => f.type == type && f.itemId == itemId);
  }
}
