import 'package:bloc/bloc.dart';

import 'package:starlight/core/utils/app_logger.dart';
import 'package:starlight/domain/entities/scene.dart';
import 'package:starlight/domain/repositories/scene_repository.dart';
import 'package:starlight/domain/usecases/execute_scene.dart';

import 'scene_event.dart';
import 'scene_state.dart';

class SceneBloc extends Bloc<SceneEvent, SceneState> {
  final SceneRepository _sceneRepository;
  final ExecuteScene _executeScene;

  SceneBloc(this._sceneRepository, this._executeScene) : super(SceneLoading()) {
    on<LoadScenes>(_onLoadScenes);
    on<ActivateScene>(_onActivateScene);
    on<SaveScene>(_onSaveScene);
    on<DeleteScene>(_onDeleteScene);
  }

  Future<void> _onLoadScenes(LoadScenes event, Emitter<SceneState> emit) async {
    try {
      final scenes = await _sceneRepository.loadScenes();
      emit(SceneLoaded(scenes));
    } catch (e) {
      emit(SceneError(e.toString()));
    }
  }

  Future<void> _onActivateScene(ActivateScene event, Emitter<SceneState> emit) async {
    final current = state;
    Scene? scene;
    if (current is SceneLoaded) {
      scene = current.scenes.where((s) => s.id == event.sceneId).firstOrNull;
    }
    scene ??= (await _sceneRepository.loadScenes())
        .where((s) => s.id == event.sceneId)
        .firstOrNull;
    if (scene == null) {
      emit(const SceneError('Scene not found'));
      return;
    }
    try {
      final result = await _executeScene(scene);
      if (result.success) {
        emit(SceneActivated(scene, true));
      } else {
        emit(SceneActivated(scene, false, result.failures.join('; ')));
      }
    } catch (e) {
      emit(SceneActivated(scene, false, e.toString()));
    }
  }

  Future<void> _onSaveScene(SaveScene event, Emitter<SceneState> emit) async {
    try {
      await _sceneRepository.saveScene(event.scene);
      add(LoadScenes());
    } catch (e) {
      emit(SceneError(e.toString()));
    }
  }

  Future<void> _onDeleteScene(DeleteScene event, Emitter<SceneState> emit) async {
    try {
      await _sceneRepository.deleteScene(event.sceneId);
      add(LoadScenes());
    } catch (e) {
      emit(SceneError(e.toString()));
    }
  }
}
