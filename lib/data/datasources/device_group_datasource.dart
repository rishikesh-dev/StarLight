// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:starlight/core/utils/app_logger.dart';

import '../models/device_group_model.dart';

/// Data source for persisting device groups to SharedPreferences.
class DeviceGroupDataSource {
  static const String groupsKey = 'starlight_groups_v1';

  final SharedPreferences prefs;

  DeviceGroupDataSource(this.prefs);

  Future<List<DeviceGroupModel>> loadGroups() async {
    AppLog.debug('loadGroups: reading key "$groupsKey"');
    final raw = prefs.getString(groupsKey);
    if (raw == null || raw.isEmpty) {
      AppLog.debug('loadGroups: no saved groups');
      return const [];
    }
    try {
      final List<dynamic> json = jsonDecode(raw) as List<dynamic>;
      return json
          .map((e) => DeviceGroupModel.fromMap(Map<String, dynamic>.from(e)))
          .toList();
    } catch (e) {
      AppLog.warn('loadGroups: failed to decode, returning empty: $e');
      return const [];
    }
  }

  Future<void> saveGroups(List<DeviceGroupModel> groups) async {
    final json = groups.map((g) => g.toMap()).toList();
    await prefs.setString(groupsKey, jsonEncode(json));
    AppLog.debug('saveGroups: saved ${groups.length} group(s)');
  }
}
