// SPDX-License-Identifier: Apache-2.0

import 'dart:math';

import 'package:bloc/bloc.dart';

import 'package:starlight/core/utils/app_logger.dart';
import 'package:starlight/domain/entities/device_profile.dart';
import 'package:starlight/domain/entities/profile_verification.dart';
import 'package:starlight/domain/repositories/device_profile_repository.dart';
import 'package:starlight/domain/repositories/profile_assignment_repository.dart';
import 'package:starlight/domain/services/command_router.dart';
import 'package:starlight/domain/services/profile_executor.dart';
import 'package:starlight/domain/services/profile_validator.dart';

import 'profile_state.dart';

/// Outcome of attempting to save a profile from the editor.
class ProfileSaveResult {
  /// Field key → message. Empty when the save succeeded.
  final Map<String, String> fieldErrors;

  /// A non-field error (storage), or null.
  final String? error;

  const ProfileSaveResult({this.fieldErrors = const {}, this.error});

  bool get isSaved => fieldErrors.isEmpty && error == null;
}

/// Loads/saves custom device profiles and keeps their assignment to the
/// connected device in sync with the [CommandRouter].
///
/// All BLE work is delegated to a [ProfileExecutor] (which itself routes
/// through the single BLE datasource) — this cubit never touches hardware.
class ProfileCubit extends Cubit<ProfileState> {
  late final DeviceProfileRepository _repository;
  late final ProfileAssignmentRepository _assignments;
  late final ProfileExecutor _executor;
  late final CommandRouter _router;
  late final String Function() _generateId;

  ProfileCubit({
    required DeviceProfileRepository repository,
    required ProfileAssignmentRepository assignments,
    required ProfileExecutor executor,
    required CommandRouter router,
    String Function()? idGenerator,
  }) : super(const ProfileState.initial()) {
    _repository = repository;
    _assignments = assignments;
    _executor = executor;
    _router = router;
    _generateId = idGenerator ?? _randomId;
  }

  static String _randomId() {
    final random = Random();
    final buffer = StringBuffer();
    for (var i = 0; i < 12; i++) {
      buffer.write(random.nextInt(256).toRadixString(16).padLeft(2, '0'));
    }
    return 'profile_$buffer';
  }

  // --- Loading ------------------------------------------------------------

  Future<void> load() async {
    emit(state.copyWith(loading: true, clearError: true));
    try {
      final profiles = await _repository.loadProfiles();
      final rawAssignments = await _assignments.loadAssignments();
      final validIds = profiles.map((p) => p.id).toSet();
      final assignments = <String, String>{};
      rawAssignments.forEach((deviceId, profileId) {
        if (profileId == kMrStarProfileId || validIds.contains(profileId)) {
          assignments[deviceId] = profileId;
        } else {
          AppLog.warn(
            'profiles: dropping assignment for device $deviceId to missing '
            'profile $profileId',
          );
        }
      });
      emit(
        state.copyWith(
          loading: false,
          profiles: profiles,
          assignments: assignments,
        ),
      );
      await _syncRouting();
    } catch (e) {
      AppLog.error('profiles: failed to load', e);
      emit(state.copyWith(loading: false, error: 'Could not load profiles.'));
    }
  }

  // --- Connection ---------------------------------------------------------

  /// Called when the connected device changes (by the app-level BLE listener).
  Future<void> onActiveDeviceChanged(String? deviceId) async {
    if (deviceId == state.activeDeviceId) return;

    if (deviceId == null) {
      emit(state.copyWith(clearActiveDeviceId: true, verifications: const {}));
      await _syncRouting();
      return;
    }

    emit(state.copyWith(activeDeviceId: deviceId));
    await _reverifyAssigned();
  }

  // --- Assignment ---------------------------------------------------------

  /// Assigns [profileId] to [deviceId], or clears the assignment when null.
  Future<void> assignProfile(String deviceId, String? profileId) async {
    if (deviceId.trim().isEmpty) return;
    if (profileId == null || profileId == kMrStarProfileId) {
      await _assignments.unassign(deviceId);
    } else {
      await _assignments.assign(deviceId, profileId);
    }
    final assignments = await _assignments.loadAssignments();
    emit(state.copyWith(assignments: assignments));
    await _reverifyAssigned();
  }

  /// Verifies [profileId] against the connected device on demand.
  Future<ProfileVerification> verifyProfile(String profileId) async {
    final profile = state.profileById(profileId);
    if (profile == null) {
      return ProfileVerification.failed('Profile not found.');
    }
    final result = await _executor.verify(profile);
    final verifications = Map<String, ProfileVerification>.from(
      state.verifications,
    )..[profileId] = result;
    emit(state.copyWith(verifications: verifications));
    await _syncRouting();
    return result;
  }

  // --- Mutation -----------------------------------------------------------

  /// Validates and persists [profile]; a blank id creates a new profile.
  Future<ProfileSaveResult> saveProfile(DeviceProfile profile) async {
    final withId = profile.id.trim().isEmpty
        ? profile.copyWith(id: _generateId())
        : profile;
    final working = withId.copyWith(
      schemaVersion: kProfileSchemaVersion,
      isBuiltIn: false,
    );

    final errors = ProfileValidator.validate(working);
    if (errors.isNotEmpty) {
      return ProfileSaveResult(
        fieldErrors: {for (final e in errors) e.field: e.message},
      );
    }

    try {
      await _repository.saveProfile(working);
      final profiles = await _repository.loadProfiles();
      emit(state.copyWith(profiles: profiles, clearError: true));
      await _reverifyAssigned();
      return const ProfileSaveResult();
    } catch (e) {
      AppLog.error('profiles: failed to save', e);
      return const ProfileSaveResult(error: 'Could not save the profile.');
    }
  }

  /// Deletes [profileId], first detaching it from every device that uses it.
  Future<void> deleteProfile(String profileId) async {
    if (profileId == kMrStarProfileId) return;

    final inUse = state.assignments.entries
        .where((e) => e.value == profileId)
        .map((e) => e.key)
        .toList(growable: false);
    for (final deviceId in inUse) {
      AppLog.info(
        'profiles: detaching profile $profileId from device $deviceId before '
        'delete',
      );
      await _assignments.unassign(deviceId);
    }

    try {
      await _repository.deleteProfile(profileId);
      final profiles = await _repository.loadProfiles();
      final assignments = await _assignments.loadAssignments();
      final verifications = Map<String, ProfileVerification>.from(
        state.verifications,
      )..remove(profileId);
      emit(
        state.copyWith(
          profiles: profiles,
          assignments: assignments,
          verifications: verifications,
        ),
      );
      await _syncRouting();
    } catch (e) {
      AppLog.error('profiles: failed to delete', e);
      emit(state.copyWith(error: 'Could not delete the profile.'));
    }
  }

  /// Duplicates [profileId] as a new, unassigned profile.
  Future<ProfileSaveResult> duplicateProfile(String profileId) async {
    final source = state.profileById(profileId);
    if (source == null) {
      return const ProfileSaveResult(error: 'Profile not found.');
    }
    final copy = source.copyWith(
      id: '',
      name: _copyName(source.name),
      isBuiltIn: false,
    );
    return saveProfile(copy);
  }

  static String _copyName(String name) {
    final trimmed = name.trim();
    final candidate = '$trimmed (copy)';
    if (candidate.length <= ProfileValidator.maxNameLength) return candidate;
    final base = trimmed.substring(
      0,
      ProfileValidator.maxNameLength - ' (copy)'.length,
    );
    return '$base (copy)';
  }

  // --- Routing ------------------------------------------------------------

  Future<void> _reverifyAssigned() async {
    final deviceId = state.activeDeviceId;
    final profileId = deviceId == null ? null : state.assignments[deviceId];
    if (deviceId != null &&
        profileId != null &&
        profileId != kMrStarProfileId) {
      final profile = state.profileById(profileId);
      if (profile != null) {
        final result = await _executor.verify(profile);
        final verifications = Map<String, ProfileVerification>.from(
          state.verifications,
        )..[profileId] = result;
        emit(state.copyWith(verifications: verifications));
      }
    }
    await _syncRouting();
  }

  /// Points [CommandRouter] at the verified assigned profile, or back at the
  /// built-in path when nothing usable is assigned.
  Future<void> _syncRouting() async {
    final deviceId = state.activeDeviceId;
    if (deviceId == null) {
      _router.applyProfile(null);
      return;
    }
    final profileId = state.assignments[deviceId];
    if (profileId == null || profileId == kMrStarProfileId) {
      _router.applyProfile(null);
      return;
    }
    final profile = state.profileById(profileId);
    final verified = state.verificationFor(profileId).isVerified;
    if (profile != null && verified) {
      _router.applyProfile(profile);
    } else {
      // Assigned but not verified: expose no controls until it is verified.
      _router.applyProfile(null, capabilities: const {});
    }
  }
}
