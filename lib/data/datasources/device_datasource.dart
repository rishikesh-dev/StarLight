// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:starlight/core/utils/app_logger.dart';

import '../models/device_model.dart';

/// Data source for persisting configured devices to SharedPreferences.
///
/// Uses a single JSON key so the entire device registry round-trips in one
/// read/write. On application restart previously configured devices are
/// restored with [DeviceConnectionState.disconnected] — the app never
/// assumes a device is connected merely because it was previously paired.
class DeviceDataSource {
  static const String devicesKey = 'starlight_devices_v1';

  final SharedPreferences prefs;

  DeviceDataSource(this.prefs);

  /// Loads all persisted devices, or an empty list when none are stored.
  Future<List<DeviceModel>> loadDevices() async {
    AppLog.debug('loadDevices: reading key "$devicesKey"');
    final raw = prefs.getString(devicesKey);
    if (raw == null || raw.isEmpty) {
      AppLog.debug('loadDevices: no saved devices');
      return const [];
    }
    try {
      final List<dynamic> json = jsonDecode(raw) as List<dynamic>;
      final devices = json
          .map((e) => DeviceModel.fromMap(Map<String, dynamic>.from(e)))
          .toList();
      AppLog.debug('loadDevices: loaded ${devices.length} device(s)');
      return devices;
    } catch (e) {
      AppLog.warn('loadDevices: failed to decode, returning empty: $e');
      return const [];
    }
  }

  /// Persists the full device list, replacing any previous snapshot.
  Future<void> saveDevices(List<DeviceModel> devices) async {
    final json = devices.map((d) => d.toMap()).toList();
    await prefs.setString(devicesKey, jsonEncode(json));
    AppLog.debug('saveDevices: saved ${devices.length} device(s)');
  }

  /// Adds or replaces a single device in the persisted registry.
  Future<void> saveDevice(DeviceModel device) async {
    final devices = await loadDevices();
    final index = devices.indexWhere((d) => d.id == device.id);
    if (index >= 0) {
      devices[index] = device;
    } else {
      devices.add(device);
    }
    await saveDevices(devices);
  }

  /// Removes a device by ID.
  Future<void> removeDevice(String deviceId) async {
    final devices = await loadDevices();
    devices.removeWhere((d) => d.id == deviceId);
    await saveDevices(devices);
  }
}
