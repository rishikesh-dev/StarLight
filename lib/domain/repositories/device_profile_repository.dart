// SPDX-License-Identifier: Apache-2.0

import '../entities/device_profile.dart';

/// Persists user-created [DeviceProfile]s locally.
///
/// The built-in MR Star profile is never stored; it is always available and is
/// returned first by [loadProfiles] so the UI can show it alongside custom
/// profiles.
abstract class DeviceProfileRepository {
  /// Loads every stored custom profile plus the built-in MR Star profile.
  ///
  /// Malformed or unsupported-schema entries are skipped (never coerced into a
  /// valid-looking profile) and reported through [AppLog].
  Future<List<DeviceProfile>> loadProfiles();

  /// Inserts or replaces [profile] by id. The built-in profile is ignored.
  Future<void> saveProfile(DeviceProfile profile);

  /// Removes the profile with [id]. The built-in profile cannot be removed.
  Future<void> deleteProfile(String id);
}
