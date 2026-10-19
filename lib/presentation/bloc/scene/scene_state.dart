// SPDX-License-Identifier: Apache-2.0

import 'package:equatable/equatable.dart';

import 'package:starlight/domain/entities/execution_result.dart';
import 'package:starlight/domain/entities/scene.dart';

abstract class SceneState extends Equatable {
  const SceneState();

  /// A message describing why the last operation was rejected, or null.
  ///
  /// Declared on the base class so every branch of the UI (including the
  /// loading and fatal states) can render a reason without narrowing first.
  String? get error => null;

  @override
  List<Object?> get props => [];
}

class SceneLoading extends SceneState {
  const SceneLoading();
}

class SceneLoaded extends SceneState {
  final List<Scene> scenes;

  /// Id of the scene currently being run, or null.
  final String? runningSceneId;

  /// The most recent per-device execution report.
  final ExecutionReport? lastReport;

  /// The scene [lastReport] belongs to.
  final String? lastReportSceneId;

  final String? error;

  const SceneLoaded({
    this.scenes = const [],
    this.runningSceneId,
    this.lastReport,
    this.lastReportSceneId,
    this.error,
  });

  bool get isEmpty => scenes.isEmpty;

  bool isRunning(String sceneId) => runningSceneId == sceneId;

  bool get isRunningAny => runningSceneId != null;

  Scene? byId(String id) => scenes.where((s) => s.id == id).firstOrNull;

  /// Favourite scenes first, then everything else; both alphabetical.
  List<Scene> get ordered {
    final byFavourite = <Scene>[];
    final rest = <Scene>[];
    for (final scene in scenes) {
      (scene.favorite ? byFavourite : rest).add(scene);
    }
    int byName(Scene a, Scene b) =>
        a.name.toLowerCase().compareTo(b.name.toLowerCase());
    byFavourite.sort(byName);
    rest.sort(byName);
    return [...byFavourite, ...rest];
  }

  SceneLoaded copyWith({
    List<Scene>? scenes,
    String? runningSceneId,
    bool clearRunning = false,
    ExecutionReport? lastReport,
    bool clearReport = false,
    String? lastReportSceneId,
    String? error,
    bool clearError = false,
  }) {
    return SceneLoaded(
      scenes: scenes ?? this.scenes,
      runningSceneId: clearRunning
          ? null
          : (runningSceneId ?? this.runningSceneId),
      lastReport: clearReport ? null : (lastReport ?? this.lastReport),
      lastReportSceneId: clearReport
          ? null
          : (lastReportSceneId ?? this.lastReportSceneId),
      error: clearError ? null : (error ?? this.error),
    );
  }

  @override
  List<Object?> get props => [
    scenes,
    runningSceneId,
    lastReport,
    lastReportSceneId,
    error,
  ];
}

class SceneError extends SceneState {
  final String message;

  const SceneError(this.message);

  @override
  String? get error => message;

  @override
  List<Object?> get props => [message];
}
