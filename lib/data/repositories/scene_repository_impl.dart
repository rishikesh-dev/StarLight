// SPDX-License-Identifier: Apache-2.0

import 'package:starlight/domain/entities/scene.dart';
import 'package:starlight/domain/repositories/scene_repository.dart';
import 'package:starlight/data/datasources/scene_datasource.dart';
import 'package:starlight/data/models/scene_model.dart';

class SceneRepositoryImpl implements SceneRepository {
  final SceneDataSource dataSource;

  SceneRepositoryImpl(this.dataSource);

  @override
  Future<List<Scene>> loadScenes() async {
    final models = await dataSource.loadScenes();
    return models.map((m) => m.toEntity()).toList();
  }

  @override
  Future<void> saveScenes(List<Scene> scenes) {
    return dataSource.saveScenes(
      scenes.map((s) => SceneModel.fromEntity(s)).toList(),
    );
  }

  @override
  Future<void> saveScene(Scene scene) {
    return dataSource.saveScene(SceneModel.fromEntity(scene));
  }

  @override
  Future<void> deleteScene(String sceneId) {
    return dataSource.deleteScene(sceneId);
  }
}
