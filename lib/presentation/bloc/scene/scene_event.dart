import 'package:equatable/equatable.dart';

import 'package:starlight/domain/entities/scene.dart';

abstract class SceneEvent extends Equatable {
  const SceneEvent();
  @override
  List<Object?> get props => [];
}

class LoadScenes extends SceneEvent {}

class ActivateScene extends SceneEvent {
  final String sceneId;
  const ActivateScene(this.sceneId);
  @override
  List<Object?> get props => [sceneId];
}

class SaveScene extends SceneEvent {
  final Scene scene;
  const SaveScene(this.scene);
  @override
  List<Object?> get props => [scene];
}

class DeleteScene extends SceneEvent {
  final String sceneId;
  const DeleteScene(this.sceneId);
  @override
  List<Object?> get props => [sceneId];
}
