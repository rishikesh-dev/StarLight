import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:starlight/core/utils/app_logger.dart';
import '../models/scene_model.dart';

/// Data source for persisting scenes to SharedPreferences.
class SceneDataSource {
  static const String scenesKey = 'starlight_scenes_v1';

  final SharedPreferences prefs;

  SceneDataSource(this.prefs);

  Future<List<SceneModel>> loadScenes() async {
    AppLog.debug('loadScenes: reading key "$scenesKey"');
    final raw = prefs.getString(scenesKey);
    if (raw == null || raw.isEmpty) {
      AppLog.debug('loadScenes: no saved scenes');
      return const [];
    }
    try {
      final List<dynamic> json = jsonDecode(raw) as List<dynamic>;
      return json
          .map((e) => SceneModel.fromMap(Map<String, dynamic>.from(e)))
          .toList();
    } catch (e) {
      AppLog.warn('loadScenes: failed to decode, returning empty: $e');
      return const [];
    }
  }

  Future<void> saveScenes(List<SceneModel> scenes) async {
    final json = scenes.map((s) => s.toMap()).toList();
    await prefs.setString(scenesKey, jsonEncode(json));
    AppLog.debug('saveScenes: saved ${scenes.length} scene(s)');
  }

  Future<void> saveScene(SceneModel scene) async {
    final scenes = await loadScenes();
    final index = scenes.indexWhere((s) => s.id == scene.id);
    if (index >= 0) {
      scenes[index] = scene;
    } else {
      scenes.add(scene);
    }
    await saveScenes(scenes);
  }

  Future<void> removeScene(String sceneId) async {
    final scenes = await loadScenes();
    scenes.removeWhere((s) => s.id == sceneId);
    await saveScenes(scenes);
  }
}