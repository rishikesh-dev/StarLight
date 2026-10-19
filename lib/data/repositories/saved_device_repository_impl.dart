// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../core/utils/app_logger.dart';
import '../../domain/entities/saved_device.dart';
import '../../domain/repositories/saved_device_repository.dart';

/// SharedPreferences-backed [SavedDeviceRepository].
///
/// Stores a single `{"id": ..., "name": ...}` document. The MAC [id] is the
/// authoritative identifier; the name is metadata and re-derived on scan if
/// the device is ever re-found under a different name.
class SavedDeviceRepositoryImpl implements SavedDeviceRepository {
  static const String _key = 'starlight_paired_device_v1';

  final SharedPreferences _prefs;

  SavedDeviceRepositoryImpl(this._prefs);

  @override
  Future<SavedDevice?> load() async {
    final raw = _prefs.getString(_key);
    if (raw == null || raw.isEmpty) {
      AppLog.debug('SavedDevice: no paired device stored');
      return null;
    }
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final id = map['id'] as String?;
      if (id == null || id.isEmpty) return null;
      return SavedDevice(id: id, name: (map['name'] as String?) ?? id);
    } catch (e) {
      AppLog.warn('SavedDevice: failed to decode stored device: $e');
      return null;
    }
  }

  @override
  Future<void> save(SavedDevice device) async {
    await _prefs.setString(
      _key,
      jsonEncode({'id': device.id, 'name': device.name}),
    );
    AppLog.info('SavedDevice: saved ${device.id} (${device.name})');
  }

  @override
  Future<void> remove() async {
    await _prefs.remove(_key);
    AppLog.info('SavedDevice: removed');
  }
}
