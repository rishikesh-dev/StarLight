// SPDX-License-Identifier: Apache-2.0

import 'package:shared_preferences/shared_preferences.dart';

import '../../core/utils/app_logger.dart';

/// Persists the selected theme id and optional custom accent colour.
///
/// Theme preferences are stored separately from device/pairing data so the two
/// never interfere. Reads are defensive: a missing, wrong-typed or malformed
/// value returns `null` and the caller falls back to the default theme.
class ThemePreferences {
  /// Selected built-in theme id (e.g. `graphite`, `light`).
  static const String themeIdKey = 'starlight_theme_id';

  /// Optional custom accent colour, stored as a 32-bit ARGB integer.
  static const String accentKey = 'starlight_theme_accent';

  final SharedPreferences prefs;

  const ThemePreferences(this.prefs);

  /// The persisted theme id, or `null` when unset/malformed.
  String? readThemeId() {
    try {
      return prefs.getString(themeIdKey);
    } catch (e) {
      AppLog.warn('ThemePreferences: unreadable theme id: $e');
      return null;
    }
  }

  /// The persisted accent as ARGB, or `null` when unset/malformed.
  int? readAccent() {
    try {
      return prefs.getInt(accentKey);
    } catch (e) {
      AppLog.warn('ThemePreferences: unreadable accent: $e');
      return null;
    }
  }

  Future<void> writeThemeId(String id) async {
    await prefs.setString(themeIdKey, id);
  }

  Future<void> writeAccent(int argb) async {
    await prefs.setInt(accentKey, argb);
  }

  Future<void> removeAccent() async {
    await prefs.remove(accentKey);
  }

  /// Clears all theme preferences, returning the app to its defaults.
  Future<void> clear() async {
    await prefs.remove(themeIdKey);
    await prefs.remove(accentKey);
  }
}
