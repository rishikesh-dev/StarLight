import 'package:starlight/domain/entities/scene.dart';

/// Serializable model for a persisted [Scene].
class SceneModel {
  final String id;
  final String name;
  final String? iconName;
  final List<SceneActionModel> actions;
  final bool favorite;
  final int createdAtMs;
  final int? updatedAtMs;

  const SceneModel({
    required this.id,
    required this.name,
    this.iconName,
    this.actions = const [],
    this.favorite = false,
    required this.createdAtMs,
    this.updatedAtMs,
  });

  Scene toEntity() => Scene(
        id: id,
        name: name,
        iconName: iconName,
        actions: actions.map((a) => a.toEntity()).toList(),
        favorite: favorite,
        createdAt: DateTime.fromMillisecondsSinceEpoch(createdAtMs),
        updatedAt:
            updatedAtMs != null ? DateTime.fromMillisecondsSinceEpoch(updatedAtMs) : null,
      );

  factory SceneModel.fromEntity(Scene scene) => SceneModel(
        id: scene.id,
        name: scene.name,
        iconName: scene.iconName,
        actions: scene.actions.map((a) => SceneActionModel.fromEntity(a)).toList(),
        favorite: scene.favorite,
        createdAtMs: scene.createdAt.millisecondsSinceEpoch,
        updatedAtMs: scene.updatedAt?.millisecondsSinceEpoch,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'iconName': iconName,
        'actions': actions.map((a) => a.toMap()).toList(),
        'favorite': favorite,
        'createdAtMs': createdAtMs,
        'updatedAtMs': updatedAtMs,
      };

  factory SceneModel.fromMap(Map<String, dynamic> map) => SceneModel(
        id: map['id'] as String,
        name: map['name'] as String,
        iconName: map['iconName'] as String?,
        actions: (map['actions'] as List<dynamic>?)
                ?.map((e) => SceneActionModel.fromMap(Map<String, dynamic>.from(e)))
                .toList() ??
            const [],
        favorite: (map['favorite'] as bool?) ?? false,
        createdAtMs: map['createdAtMs'] as int,
        updatedAtMs: map['updatedAtMs'] as int?,
      );
}

/// Serializable model for a [SceneAction].
class SceneActionModel {
  final String deviceId;
  final String action;
  final dynamic value;

  const SceneActionModel({
    required this.deviceId,
    required this.action,
    required this.value,
  });

  SceneAction toEntity() => SceneAction(
        deviceId: deviceId,
        action: action,
        value: value,
      );

  factory SceneActionModel.fromEntity(SceneAction action) => SceneActionModel(
        deviceId: action.deviceId,
        action: action.action,
        value: action.value,
      );

  Map<String, dynamic> toMap() => {
        'deviceId': deviceId,
        'action': action,
        'value': value,
      };

  factory SceneActionModel.fromMap(Map<String, dynamic> map) => SceneActionModel(
        deviceId: map['deviceId'] as String,
        action: map['action'] as String,
        value: map['value'],
      );
}