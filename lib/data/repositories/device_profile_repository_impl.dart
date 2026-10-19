// SPDX-License-Identifier: Apache-2.0

import 'package:starlight/core/utils/app_logger.dart';
import 'package:starlight/data/datasources/profile_datasource.dart';
import 'package:starlight/domain/entities/device_profile.dart';
import 'package:starlight/domain/repositories/device_profile_repository.dart';

/// [DeviceProfileRepository] backed by [ProfileDataSource].
///
/// The built-in MR Star profile is always present and is never written to
/// storage.
class DeviceProfileRepositoryImpl implements DeviceProfileRepository {
  final ProfileDataSource dataSource;

  DeviceProfileRepositoryImpl(this.dataSource);

  @override
  Future<List<DeviceProfile>> loadProfiles() async {
    final custom = await dataSource.loadProfiles();
    return [DeviceProfile.mrStar, ...custom];
  }

  @override
  Future<void> saveProfile(DeviceProfile profile) async {
    if (profile.isBuiltIn || profile.id == kMrStarProfileId) {
      AppLog.warn('profiles: refusing to persist the built-in profile');
      return;
    }
    // The datasource may return a const/immutable list when empty, so copy
    // before mutating.
    final stored = List<DeviceProfile>.from(await dataSource.loadProfiles());
    final index = stored.indexWhere((p) => p.id == profile.id);
    if (index >= 0) {
      stored[index] = profile;
    } else {
      stored.add(profile);
    }
    await dataSource.saveProfiles(stored);
  }

  @override
  Future<void> deleteProfile(String id) async {
    if (id == kMrStarProfileId) {
      AppLog.warn('profiles: refusing to delete the built-in profile');
      return;
    }
    final stored = List<DeviceProfile>.from(await dataSource.loadProfiles());
    stored.removeWhere((p) => p.id == id);
    await dataSource.saveProfiles(stored);
  }
}
