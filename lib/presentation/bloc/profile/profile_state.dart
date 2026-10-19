// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/foundation.dart';

import 'package:starlight/domain/entities/device_profile.dart';
import 'package:starlight/domain/entities/profile_verification.dart';

/// State of the saved custom device profiles and their device assignments.
@immutable
class ProfileState {
  /// True while the initial load is in flight.
  final bool loading;

  /// Every known profile, built-in first.
  final List<DeviceProfile> profiles;

  /// `deviceId → profileId`. A device with no entry uses built-in behaviour.
  final Map<String, String> assignments;

  /// Verification results keyed by profile id (never persisted).
  final Map<String, ProfileVerification> verifications;

  /// The id of the currently connected device, or null.
  final String? activeDeviceId;

  /// A load/save error to surface, if any.
  final String? error;

  const ProfileState({
    this.loading = false,
    this.profiles = const [],
    this.assignments = const {},
    this.verifications = const {},
    this.activeDeviceId,
    this.error,
  });

  const ProfileState.initial() : this();

  /// Custom (non built-in) profiles only.
  List<DeviceProfile> get customProfiles =>
      profiles.where((p) => !p.isBuiltIn).toList(growable: false);

  /// The profile assigned to [deviceId], or null when none is.
  DeviceProfile? assignedProfile(String deviceId) {
    final id = assignments[deviceId];
    if (id == null) return null;
    return profileById(id);
  }

  DeviceProfile? profileById(String id) {
    for (final p in profiles) {
      if (p.id == id) return p;
    }
    return null;
  }

  ProfileVerification verificationFor(String profileId) =>
      verifications[profileId] ?? const ProfileVerification.unverified();

  bool isAssignedButUnverified(String deviceId) {
    final id = assignments[deviceId];
    if (id == null || id == kMrStarProfileId) return false;
    return !verificationFor(id).isVerified;
  }

  ProfileState copyWith({
    bool? loading,
    List<DeviceProfile>? profiles,
    Map<String, String>? assignments,
    Map<String, ProfileVerification>? verifications,
    String? activeDeviceId,
    bool clearActiveDeviceId = false,
    String? error,
    bool clearError = false,
  }) {
    return ProfileState(
      loading: loading ?? this.loading,
      profiles: profiles ?? this.profiles,
      assignments: assignments ?? this.assignments,
      verifications: verifications ?? this.verifications,
      activeDeviceId: clearActiveDeviceId
          ? null
          : (activeDeviceId ?? this.activeDeviceId),
      error: clearError ? null : (error ?? this.error),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ProfileState &&
      other.loading == loading &&
      listEquals(other.profiles, profiles) &&
      mapEquals(other.assignments, assignments) &&
      mapEquals(other.verifications, verifications) &&
      other.activeDeviceId == activeDeviceId &&
      other.error == error;

  @override
  int get hashCode => Object.hash(
    loading,
    Object.hashAll(profiles),
    Object.hashAll(assignments.entries.map((e) => Object.hash(e.key, e.value))),
    Object.hashAll(verifications.entries),
    activeDeviceId,
    error,
  );
}
