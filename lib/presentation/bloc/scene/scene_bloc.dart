// SPDX-License-Identifier: Apache-2.0

import 'dart:math';

import 'package:bloc/bloc.dart';

import 'package:starlight/core/errors/exceptions.dart';
import 'package:starlight/core/utils/app_logger.dart';
import 'package:starlight/domain/entities/execution_result.dart';
import 'package:starlight/domain/entities/scene.dart';
import 'package:starlight/domain/repositories/scene_repository.dart';
import 'package:starlight/domain/usecases/execute_scene.dart';

import 'scene_event.dart';
import 'scene_state.dart';

/// Owns the persisted scene list, validation, execution and their reporting.
///
/// The bloc is the only writer: the editor hands it a complete [Scene] and it
/// decides whether that scene is safe to store. Execution goes through
/// [ExecuteScene], so nothing here encodes a command itself.
class SceneBloc extends Bloc<SceneEvent, SceneState> {
  final SceneRepository _repository;
  final ExecuteScene _executeScene;
  final Random _random;

  SceneBloc(this._repository, this._executeScene, {Random? random})
    : _random = random ?? Random(),
      super(const SceneLoading()) {
    on<LoadScenes>(_onLoadScenes);
    on<CreateScene>(_onCreateScene);
    on<SaveScene>(_onSaveScene);
    on<DeleteScene>(_onDeleteScene);
    on<DuplicateScene>(_onDuplicateScene);
    on<ToggleSceneFavorite>(_onToggleFavorite);
    on<RunScene>(_onRunScene);
    on<StopSceneRun>(_onStopSceneRun);
    on<PruneUnavailableTargets>(_onPruneUnavailableTargets);
    on<ClearSceneReport>(_onClearReport);
    add(const LoadScenes());
  }

  @override
  Future<void> close() {
    // A run must not outlive the bloc that owns it.
    _executeScene.stop();
    return super.close();
  }

  Future<void> _onLoadScenes(LoadScenes event, Emitter<SceneState> emit) async {
    try {
      final scenes = await _repository.loadScenes();
      if (isClosed) return;
      emit(_loaded(scenes));
    } catch (e) {
      AppLog.error('Scenes: load failed: $e');
      if (isClosed) return;
      emit(SceneError('Scenes could not be loaded.'));
    }
  }

  Future<void> _onCreateScene(
    CreateScene event,
    Emitter<SceneState> emit,
  ) async {
    final name = event.name.trim();
    if (name.isEmpty) {
      _emitError(emit, 'Enter a scene name.');
      return;
    }
    final existing = await _currentScenes();
    if (existing.any((s) => s.name.toLowerCase() == name.toLowerCase())) {
      _emitError(emit, 'A scene named "$name" already exists.');
      return;
    }
    final now = DateTime.now();
    final scene = Scene(
      id: _generateId(),
      name: name,
      description: event.description,
      iconName: event.iconName,
      actions: const [],
      createdAt: now,
      updatedAt: now,
    );
    await _persist(emit, [...existing, scene], scene);
  }

  Future<void> _onSaveScene(SaveScene event, Emitter<SceneState> emit) async {
    final existing = await _currentScenes();
    final index = existing.indexWhere((s) => s.id == event.scene.id);
    if (index < 0) {
      _emitError(emit, 'That scene no longer exists.');
      return;
    }
    final name = event.scene.name.trim();
    if (name.isEmpty) {
      _emitError(emit, 'Enter a scene name.');
      return;
    }
    if (existing.any(
      (s) =>
          s.id != event.scene.id && s.name.toLowerCase() == name.toLowerCase(),
    )) {
      _emitError(emit, 'A scene named "$name" already exists.');
      return;
    }
    final invalid = event.scene.firstInvalidAction;
    if (invalid != null) {
      _emitError(emit, invalid.validationError!);
      return;
    }
    final previous = existing[index];
    final updated = event.scene.copyWith(
      name: name,
      // `createdAt` and `updatedAt` are owned by the bloc, not the editor.
      createdAt: previous.createdAt ?? DateTime.now(),
      updatedAt: DateTime.now(),
      schemaVersion: Scene.currentSchemaVersion,
    );
    final next = [...existing]..[index] = updated;
    await _persist(emit, next, updated);
  }

  Future<void> _onDeleteScene(
    DeleteScene event,
    Emitter<SceneState> emit,
  ) async {
    final existing = await _currentScenes();
    if (!existing.any((s) => s.id == event.sceneId)) return;
    await _persist(
      emit,
      existing.where((s) => s.id != event.sceneId).toList(),
      null,
    );
  }

  Future<void> _onDuplicateScene(
    DuplicateScene event,
    Emitter<SceneState> emit,
  ) async {
    final existing = await _currentScenes();
    final source = existing.where((s) => s.id == event.sceneId).firstOrNull;
    if (source == null) {
      _emitError(emit, 'That scene no longer exists.');
      return;
    }
    final now = DateTime.now();
    final copy = source.copyWith(
      id: _generateId(),
      name: _uniqueName(existing, source.name),
      createdAt: now,
      updatedAt: now,
      favorite: false,
    );
    await _persist(emit, [...existing, copy], copy);
  }

  Future<void> _onToggleFavorite(
    ToggleSceneFavorite event,
    Emitter<SceneState> emit,
  ) async {
    final existing = await _currentScenes();
    final index = existing.indexWhere((s) => s.id == event.sceneId);
    if (index < 0) return;
    final updated = existing[index].copyWith(
      favorite: !existing[index].favorite,
      updatedAt: DateTime.now(),
    );
    final next = [...existing]..[index] = updated;
    await _persist(emit, next, updated);
  }

  Future<void> _onRunScene(RunScene event, Emitter<SceneState> emit) async {
    final existing = await _currentScenes();
    final scene = existing.where((s) => s.id == event.sceneId).firstOrNull;
    if (scene == null) {
      _emitError(emit, 'That scene no longer exists.');
      return;
    }

    final current = state;
    if (current is SceneLoaded && current.isRunningAny) {
      AppLog.info('Scenes: "${scene.name}" refused, a run is already active');
      _emitError(
        emit,
        'Another scene is still running. Wait for it to finish.',
        base: current,
      );
      return;
    }

    emit(
      (current is SceneLoaded ? current : _loaded(existing)).copyWith(
        runningSceneId: scene.id,
        clearReport: true,
      ),
    );

    final ExecutionReport report;
    try {
      report = await _executeScene(scene);
    } catch (e) {
      AppLog.error('Scenes: running "${scene.name}" failed: $e');
      if (!isClosed) {
        emit(
          _loaded(
            existing,
          ).copyWith(clearRunning: true, error: 'The scene could not be run.'),
        );
      }
      return;
    }
    if (isClosed) return;
    AppLog.info('Scenes: "${scene.name}" → ${report.summary}');
    emit(
      _loaded(existing).copyWith(
        clearRunning: true,
        lastReport: report,
        lastReportSceneId: scene.id,
      ),
    );
  }

  void _onStopSceneRun(StopSceneRun event, Emitter<SceneState> emit) {
    _executeScene.stop();
    final current = state;
    if (current is SceneLoaded && current.isRunningAny) {
      emit(current.copyWith(error: 'Stopping the scene…'));
    }
  }

  Future<void> _onPruneUnavailableTargets(
    PruneUnavailableTargets event,
    Emitter<SceneState> emit,
  ) async {
    final existing = await _currentScenes();
    final index = existing.indexWhere((s) => s.id == event.sceneId);
    if (index < 0) {
      _emitError(emit, 'That scene no longer exists.');
      return;
    }
    final scene = existing[index];
    final kept = <SceneAction>[];
    var removed = 0;
    for (final action in scene.actions) {
      if (action.targetsGroup) {
        // Group membership is validated by the group repository at execution
        // time; keep the action so the group can be restored later.
        kept.add(action);
        continue;
      }
      final device = await _deviceExists(action.deviceId);
      if (device) {
        kept.add(action);
      } else {
        removed++;
      }
    }
    if (removed == 0) {
      _emitError(emit, 'Every target in this scene is still available.');
      return;
    }
    final updated = scene.copyWith(actions: kept, updatedAt: DateTime.now());
    final next = [...existing]..[index] = updated;
    await _persist(
      emit,
      next,
      updated,
      message: 'Removed $removed unavailable action(s).',
    );
  }

  void _onClearReport(ClearSceneReport event, Emitter<SceneState> emit) {
    final current = state;
    if (current is SceneLoaded && current.lastReport != null) {
      emit(current.copyWith(clearReport: true));
    }
  }

  // --- Internals -------------------------------------------------------------

  /// Scene ids the executor can still resolve. Overridden by tests through
  /// [sceneExists]; defaults to "everything is available".
  Future<bool> Function(String deviceId)? existsOverride;

  Future<bool> _deviceExists(String? deviceId) async {
    if (deviceId == null || deviceId.isEmpty) return false;
    final override = existsOverride;
    if (override != null) return override(deviceId);
    return true;
  }

  Future<List<Scene>> _currentScenes() async {
    final current = state;
    if (current is SceneLoaded) return current.scenes;
    return _repository.loadScenes();
  }

  Future<void> _persist(
    Emitter<SceneState> emit,
    List<Scene> scenes,
    Scene? subject, {
    String? message,
  }) async {
    try {
      await _repository.saveScenes(scenes);
      if (isClosed) return;
      emit(_loaded(scenes, message: message));
    } on ValidationException catch (e) {
      _emitError(emit, e.message);
    } catch (e) {
      AppLog.error('Scenes: save failed: $e');
      _emitError(emit, 'The scene could not be saved.');
    }
  }

  SceneLoaded _loaded(List<Scene> scenes, {String? message}) =>
      SceneLoaded(scenes: scenes, error: message);

  void _emitError(
    Emitter<SceneState> emit,
    String message, {
    SceneState? base,
  }) {
    if (isClosed) return;
    final current = base ?? state;
    if (current is SceneLoaded) {
      emit(current.copyWith(error: message));
    } else {
      emit(SceneError(message));
    }
  }

  String _uniqueName(List<Scene> existing, String base) {
    final taken = existing.map((s) => s.name.toLowerCase()).toSet();
    if (!taken.contains(base.toLowerCase())) return base;
    for (var i = 2; i < 1000; i++) {
      final candidate = '$base $i';
      if (!taken.contains(candidate.toLowerCase())) return candidate;
    }
    return '$base ${_random.nextInt(1 << 20)}';
  }

  String _generateId() {
    final micros = DateTime.now().microsecondsSinceEpoch;
    final suffix = _random.nextInt(1 << 32).toRadixString(36);
    return 'scene_${micros.toRadixString(36)}_$suffix';
  }
}
