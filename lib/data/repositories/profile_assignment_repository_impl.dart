// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:starlight/core/utils/app_logger.dart';
import 'package:starlight/domain/entities/device_profile.dart';
import 'package:starlight/domain/repositories/profile_assignment_repository.dart';

/// SharedPreferences-backed `deviceId → profileId` assignment store.
///
/// One JSON object under [assignmentsKey]. An assignment to the built-in MR
/// Star profile is stored as *no* assignment (the default behaviour).
class ProfileAssignmentRepositoryImpl implements ProfileAssignmentRepository {
  static const String assignmentsKey = 'starlight_profile_assignments_v1';

  final SharedPreferences prefs;

  ProfileAssignmentRepositoryImpl(this.prefs);

  @override
  Future<Map<String, String>> loadAssignments() async {
    final raw = prefs.getString(assignmentsKey);
    if (raw == null || raw.isEmpty) return const {};

    dynamic decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (e) {
      AppLog.warn('assignments: stored document is not valid JSON; ignoring');
      return const {};
    }
    if (decoded is! Map) {
      AppLog.warn('assignments: stored document is not an object; ignoring');
      return const {};
    }

    final assignments = <String, String>{};
    decoded.forEach((key, value) {
      if (key is String && key.isNotEmpty && value is String) {
        assignments[key] = value;
      }
    });
    return assignments;
  }

  @override
  Future<void> assign(String deviceId, String profileId) async {
    if (deviceId.trim().isEmpty) return;
    final assignments = Map<String, String>.from(await loadAssignments());
    if (profileId == kMrStarProfileId) {
      assignments.remove(deviceId);
    } else {
      assignments[deviceId] = profileId;
    }
    await _save(assignments);
  }

  @override
  Future<void> unassign(String deviceId) async {
    final assignments = Map<String, String>.from(await loadAssignments());
    assignments.remove(deviceId);
    await _save(assignments);
  }

  @override
  Future<String?> assignedProfileId(String deviceId) async {
    final assignments = await loadAssignments();
    return assignments[deviceId];
  }

  Future<void> _save(Map<String, String> assignments) async {
    await prefs.setString(assignmentsKey, jsonEncode(assignments));
  }
}
