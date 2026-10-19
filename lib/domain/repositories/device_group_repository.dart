// SPDX-License-Identifier: Apache-2.0

import 'package:starlight/domain/entities/device_group.dart';

/// Repository for logical device groups.
///
/// Groups are a convenience layer over the device registry, never a transport
/// concept. Membership is explicit and validated against the real registry: a
/// group can never reference a device that does not exist, and duplicate
/// members are rejected.
abstract class DeviceGroupRepository {
  /// Returns all groups, ordered by [DeviceGroup.sortOrder].
  Future<List<DeviceGroup>> getGroups();

  /// Returns a single group by id, or null.
  Future<DeviceGroup?> getGroup(String groupId);

  /// Creates a group, generating an id when [group] has none.
  Future<DeviceGroup> createGroup(DeviceGroup group);

  /// Updates name/icon/room/favorite/sort order (not membership).
  Future<void> updateGroup(DeviceGroup group);

  /// Removes a group. Its devices are untouched.
  Future<void> deleteGroup(String groupId);

  /// Adds an existing device to a group (no-op when already a member).
  Future<void> addDeviceToGroup(String groupId, String deviceId);

  /// Removes a device from a group (no-op when not a member).
  Future<void> removeDeviceFromGroup(String groupId, String deviceId);

  /// Replaces the full member list, validating every id and de-duplicating.
  Future<void> setGroupMembers(String groupId, List<String> deviceIds);
}
