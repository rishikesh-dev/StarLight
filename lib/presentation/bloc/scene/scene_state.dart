import 'package:equatable/equatable.dart';

import 'package:starlight/domain/entities/scene.dart';

abstract class SceneState extends Equatable {
  const SceneState();
  @override
  List<Object?> get props => [];
}

class SceneLoading extends SceneState {}

class SceneLoaded extends SceneState {
  final List<Scene> scenes;
  const SceneLoaded(this.scenes);
  @override
  List<Object?> get props => [scenes];
}

class SceneError extends SceneState {
  final String message;
  const SceneError(this.message);
  @override
  List<Object?> get props => [message];
}

class SceneActivated extends SceneState {
  final Scene scene;
  final bool success;
  final String? errorMessage;
  const SceneActivated(this.scene, this.success, [this.errorMessage]);
  @override
  List<Object?> get props => [scene, success, errorMessage];
}
