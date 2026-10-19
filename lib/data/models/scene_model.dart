// SPDX-License-Identifier: Apache-2.0

import 'package:starlight/domain/entities/scene.dart';

/// Serializable model for a persisted [Scene].
///
/// Handles the version-1 payload produced by earlier builds: it had no
/// `schemaVersion`, no `description` and no group targets. Those payloads are
/// read as schema version 1 and remain fully executable, so an upgrade never
/// discards a user's saved scenes.
class SceneModel {
  final String id;
  final String name;
  final String? description;
  final String? iconName;
  final List<SceneActionModel> actions;
  final bool favorite;
  final int createdAtMs;
  final int? updatedAtMs;
  final int schemaVersion;

  const SceneModel({
    required this.id,
    required this.name,
    this.description,
    this.iconName,
    this.actions = const [],
    this.favorite = false,
    this.createdAtMs = 0,
    this.updatedAtMs,
    this.schemaVersion = Scene.currentSchemaVersion,
  });

  Scene toEntity() => Scene(
    id: id,
    name: name,
    description: description,
    iconName: iconName,
    actions: actions.map((a) => a.toEntity()).toList(),
    favorite: favorite,
    createdAt: createdAtMs == 0
        ? null
        : DateTime.fromMillisecondsSinceEpoch(createdAtMs),
    updatedAt: updatedAtMs == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(updatedAtMs!),
    schemaVersion: schemaVersion,
  );

  factory SceneModel.fromEntity(Scene scene) => SceneModel(
    id: scene.id,
    name: scene.name,
    description: scene.description,
    iconName: scene.iconName,
    actions: scene.actions.map((a) => SceneActionModel.fromEntity(a)).toList(),
    favorite: scene.favorite,
    createdAtMs: scene.createdAt?.millisecondsSinceEpoch ?? 0,
    updatedAtMs: scene.updatedAt?.millisecondsSinceEpoch,
    schemaVersion: scene.schemaVersion,
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'description': description,
    'iconName': iconName,
    'actions': actions.map((a) => a.toMap()).toList(),
    'favorite': favorite,
    'createdAtMs': createdAtMs,
    'updatedAtMs': updatedAtMs,
    'schemaVersion': schemaVersion,
  };

  factory SceneModel.fromMap(Map<String, dynamic> map) => SceneModel(
    id: map['id'] as String,
    name: map['name'] as String,
    description: map['description'] as String?,
    iconName: map['iconName'] as String?,
    actions:
        (map['actions'] as List<dynamic>?)
            ?.map((e) => SceneActionModel.fromMap(Map<String, dynamic>.from(e)))
            .toList() ??
        const [],
    favorite: (map['favorite'] as bool?) ?? false,
    createdAtMs: (map['createdAtMs'] as int?) ?? 0,
    updatedAtMs: map['updatedAtMs'] as int?,
    // Absent in version-1 payloads.
    schemaVersion: (map['schemaVersion'] as int?) ?? 1,
  );
}

/// Serializable model for a [SceneAction].
class SceneActionModel {
  final String? deviceId;
  final String? groupId;
  final String action;
  final dynamic value;

  const SceneActionModel({
    this.deviceId,
    this.groupId,
    required this.action,
    required this.value,
  });

  SceneAction toEntity() => SceneAction(
    deviceId: deviceId,
    groupId: groupId,
    action: action,
    value: value,
  );

  factory SceneActionModel.fromEntity(SceneAction action) => SceneActionModel(
    deviceId: action.deviceId,
    groupId: action.groupId,
    action: action.action,
    value: action.value,
  );

  Map<String, dynamic> toMap() => {
    'deviceId': deviceId,
    'groupId': groupId,
    'action': action,
    'value': value,
  };

  factory SceneActionModel.fromMap(Map<String, dynamic> map) =>
      SceneActionModel(
        deviceId: map['deviceId'] as String?,
        groupId: map['groupId'] as String?,
        action: map['action'] as String,
        value: map['value'],
      );
}
