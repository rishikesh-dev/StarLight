// SPDX-License-Identifier: Apache-2.0

import 'package:starlight/domain/entities/scene.dart';

abstract class SceneRepository {
  Future<List<Scene>> loadScenes();
  Future<void> saveScenes(List<Scene> scenes);
  Future<void> saveScene(Scene scene);
  Future<void> deleteScene(String sceneId);
}
