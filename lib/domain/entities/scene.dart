import 'package:equatable/equatable.dart';

/// Represents an action to perform on a device as part of a scene.
class SceneAction extends Equatable {
  final String deviceId;
  final String action; // 'power', 'brightness', 'color', 'effect', 'speed', 'colorTemperature'
  final dynamic value; // bool, int, String, etc.

  const SceneAction({
    required this.deviceId,
    required this.action,
    required this.value,
  });

  @override
  List<Object?> get props => [deviceId, action, value];
}

/// Represents a scene - a collection of device actions that can be activated together.
class Scene extends Equatable {
  final String id;
  final String name;
  final String? iconName;
  final List<SceneAction> actions;
  final bool favorite;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const Scene({
    required this.id,
    required this.name,
    this.iconName,
    required this.actions,
    this.favorite = false,
    this.createdAt,
    this.updatedAt,
  });

  Scene copyWith({
    String? id,
    String? name,
    String? iconName,
    List<SceneAction>? actions,
    bool? favorite,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Scene(
      id: id ?? this.id,
      name: name ?? this.name,
      iconName: iconName ?? this.iconName,
      actions: actions ?? this.actions,
      favorite: favorite ?? this.favorite,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  List<Object?> get props => [id, name, iconName, actions, favorite, createdAt, updatedAt];
}

/// Default scenes for a new home.
class DefaultScenes {
  static List<Scene> get scenes => [
    Scene(
      id: 'coding',
      name: 'Coding',
      iconName: 'code',
      actions: [
        // StarLight will be configured when devices are added
      ],
      createdAt: DateTime.now(),
    ),
    Scene(
      id: 'gaming',
      name: 'Gaming',
      iconName: 'sports_esports',
      actions: [],
      createdAt: DateTime.now(),
    ),
    Scene(
      id: 'movie',
      name: 'Movie',
      iconName: 'movie',
      actions: [],
      createdAt: DateTime.now(),
    ),
    Scene(
      id: 'night',
      name: 'Night',
      iconName: 'nightlight',
      actions: [],
      createdAt: DateTime.now(),
    ),
    Scene(
      id: 'sunset',
      name: 'Sunset',
      iconName: 'wb_sunny',
      actions: [],
      createdAt: DateTime.now(),
    ),
    Scene(
      id: 'morning',
      name: 'Morning',
      iconName: 'wb_sunny_outlined',
      actions: [],
      createdAt: DateTime.now(),
    ),
  ];
}