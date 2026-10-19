// SPDX-License-Identifier: Apache-2.0

/// Persists which profile is assigned to which device (by device id).
///
/// A missing assignment means the device uses its built-in behaviour.
abstract class ProfileAssignmentRepository {
  /// Returns every `deviceId → profileId` assignment.
  Future<Map<String, String>> loadAssignments();

  /// Assigns [profileId] to [deviceId] (replacing any previous assignment).
  Future<void> assign(String deviceId, String profileId);

  /// Removes any assignment for [deviceId].
  Future<void> unassign(String deviceId);

  /// The profile assigned to [deviceId], or null when none is.
  Future<String?> assignedProfileId(String deviceId);
}
