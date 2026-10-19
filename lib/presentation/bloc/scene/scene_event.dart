// SPDX-License-Identifier: Apache-2.0

import 'package:equatable/equatable.dart';

import 'package:starlight/domain/entities/scene.dart';

/// Events for the scene feature.
///
/// Every mutation is expressed as data so the bloc — not the widgets — owns
/// validation, persistence and execution ordering.
abstract class SceneEvent extends Equatable {
  const SceneEvent();

  @override
  List<Object?> get props => [];
}

/// (Re)loads scenes from local storage.
class LoadScenes extends SceneEvent {
  const LoadScenes();
}

/// Creates a new scene. The bloc assigns the id and timestamps.
class CreateScene extends SceneEvent {
  final String name;
  final String? description;
  final String? iconName;

  const CreateScene({required this.name, this.description, this.iconName});

  @override
  List<Object?> get props => [name, description, iconName];
}

/// Saves edits to an existing scene. The scene is stored with an updated
/// `updatedAt`; `createdAt` is preserved.
class SaveScene extends SceneEvent {
  final Scene scene;

  const SaveScene(this.scene);

  @override
  List<Object?> get props => [scene];
}

/// Deletes a scene after the UI has confirmed.
class DeleteScene extends SceneEvent {
  final String sceneId;

  const DeleteScene(this.sceneId);

  @override
  List<Object?> get props => [sceneId];
}

/// Copies a scene, including its actions, under a new id.
class DuplicateScene extends SceneEvent {
  final String sceneId;

  const DuplicateScene(this.sceneId);

  @override
  List<Object?> get props => [sceneId];
}

/// Marks/unmarks a scene as a favourite.
class ToggleSceneFavorite extends SceneEvent {
  final String sceneId;

  const ToggleSceneFavorite(this.sceneId);

  @override
  List<Object?> get props => [sceneId];
}

/// Runs a scene. Overlapping runs are refused; the in-flight one owns the
/// devices until it finishes.
class RunScene extends SceneEvent {
  final String sceneId;

  const RunScene(this.sceneId);

  @override
  List<Object?> get props => [sceneId];
}

/// Requests that an in-flight run stops at its next target boundary.
class StopSceneRun extends SceneEvent {
  const StopSceneRun();
}

/// Drops actions whose target no longer exists, keeping the rest of the scene.
///
/// Offered explicitly in the UI: an unavailable target is never silently
/// retargeted at another device, and scene definitions are preserved until the
/// user chooses to repair them.
class PruneUnavailableTargets extends SceneEvent {
  final String sceneId;

  const PruneUnavailableTargets(this.sceneId);

  @override
  List<Object?> get props => [sceneId];
}

/// Acknowledges the last execution report (hides its banner).
class ClearSceneReport extends SceneEvent {
  const ClearSceneReport();
}
