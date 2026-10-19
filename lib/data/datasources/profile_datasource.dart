// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:starlight/core/utils/app_logger.dart';
import 'package:starlight/data/models/device_profile_model.dart';
import 'package:starlight/domain/entities/device_profile.dart';

/// SharedPreferences-backed store for custom [DeviceProfile]s.
///
/// One JSON array under [profilesKey]. Every entry is parsed independently:
/// a malformed or unsupported-schema document is skipped (and logged without
/// dumping the document) so one bad entry cannot lose the rest or crash
/// startup.
class ProfileDataSource {
  static const String profilesKey = 'starlight_profiles_v1';

  final SharedPreferences prefs;

  ProfileDataSource(this.prefs);

  /// Loads every valid stored profile (excluding the built-in one).
  Future<List<DeviceProfile>> loadProfiles() async {
    final raw = prefs.getString(profilesKey);
    if (raw == null || raw.isEmpty) {
      AppLog.debug('profiles: no stored profiles');
      return const [];
    }

    dynamic decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (e) {
      AppLog.warn('profiles: stored document is not valid JSON; ignoring');
      return const [];
    }
    if (decoded is! List) {
      AppLog.warn('profiles: stored document is not a list; ignoring');
      return const [];
    }

    final profiles = <DeviceProfile>[];
    for (final entry in decoded) {
      if (entry is! Map) {
        AppLog.warn('profiles: skipping non-object entry');
        continue;
      }
      try {
        profiles.add(
          DeviceProfileModel.fromJson(Map<String, dynamic>.from(entry)),
        );
      } on ProfileFormatException catch (e) {
        AppLog.warn('profiles: skipping invalid profile (${e.message})');
      } catch (e) {
        AppLog.warn('profiles: skipping profile that failed to parse: $e');
      }
    }
    AppLog.debug('profiles: loaded ${profiles.length} valid profile(s)');
    return profiles;
  }

  /// Replaces the stored set with [profiles] (built-in profiles are ignored).
  Future<void> saveProfiles(List<DeviceProfile> profiles) async {
    final custom = profiles.where((p) => !p.isBuiltIn).toList();
    final encoded = jsonEncode([
      for (final p in custom) DeviceProfileModel.toJson(p),
    ]);
    await prefs.setString(profilesKey, encoded);
  }
}
