import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../core/utils/app_logger.dart';
import '../models/preset_model.dart';

/// Data source for preset storage using SharedPreferences.
///
/// The original APK stores presets in SharedPreferences with the name "data",
/// using keys like "[id]r", "[id]g", "[id]b" for RGB values.
/// This implementation stores them as JSON for simplicity while maintaining
/// compatibility with the original color values.
class PresetDataSource {
  static const String presetsKey = 'starlight_presets_v2';

  final SharedPreferences prefs;

  PresetDataSource(this.prefs);

  /// Default presets matching the original APK first-time setup.
  /// Source: AdjustFragment.java line 113-118
  static List<PresetModel> defaultPresets() {
    return [
      const PresetModel(id: 1, name: 'Green', red: 0, green: 255, blue: 0),
      const PresetModel(id: 2, name: 'Red', red: 255, green: 0, blue: 0),
      const PresetModel(id: 3, name: 'Cyan', red: 0, green: 255, blue: 255),
      const PresetModel(id: 4, name: 'Purple', red: 255, green: 0, blue: 255),
      const PresetModel(id: 5, name: 'Yellow', red: 255, green: 255, blue: 0),
      const PresetModel(id: 6, name: 'White', red: 255, green: 255, blue: 255),
      const PresetModel(id: 7, name: 'Warm White', red: 255, green: 245, blue: 228),
    ];
  }

  Future<List<PresetModel>> loadPresets() async {
    AppLog.debug('loadPresets: reading key "$presetsKey"');
    final raw = prefs.getString(presetsKey);
    if (raw == null || raw.isEmpty) {
      AppLog.debug('loadPresets: no saved presets, returning defaults');
      return defaultPresets();
    }
    try {
      final List<dynamic> json = jsonDecode(raw) as List<dynamic>;
      final presets = json
          .map((e) => PresetModel.fromMap(Map<String, dynamic>.from(e)))
          .toList();
      if (presets.isEmpty) {
        AppLog.debug('loadPresets: saved list empty, returning defaults');
        return defaultPresets();
      }
      AppLog.debug('loadPresets: loaded ${presets.length} preset(s)');
      return presets;
    } catch (e) {
      AppLog.warn('loadPresets: failed to decode, using defaults: $e');
      return defaultPresets();
    }
  }

  Future<void> savePresets(List<PresetModel> presets) async {
    final json = presets.map((p) => p.toMap()).toList();
    await prefs.setString(presetsKey, jsonEncode(json));
    AppLog.debug('savePresets: saved ${presets.length} preset(s)');
  }

  Future<void> savePreset(PresetModel preset) async {
    AppLog.debug(
      'savePreset: id=${preset.id} name="${preset.name}" '
      'rgb=${preset.red},${preset.green},${preset.blue}',
    );
    final presets = await loadPresets();
    final index = presets.indexWhere((p) => p.id == preset.id);
    if (index >= 0) {
      presets[index] = preset;
    } else {
      presets.add(preset);
    }
    await savePresets(presets);
  }

  Future<void> deletePreset(int id) async {
    AppLog.debug('deletePreset: id=$id');
    final presets = await loadPresets();
    presets.removeWhere((p) => p.id == id);
    await savePresets(presets);
  }
}
