// SPDX-License-Identifier: Apache-2.0

import 'package:equatable/equatable.dart';

import 'device_capability.dart';

/// A single, validated instruction in a [Scene].
///
/// An action targets exactly one of a device ([deviceId]) or a group
/// ([groupId]); a group target is expanded to its real members at execution
/// time. [value] is the command parameter and is always type-checked before a
/// command is built — malformed scene data can never reach the transport.
class SceneAction extends Equatable {
  /// Stable schema version for the action payload. Bumped when the JSON shape
  /// changes in a way that needs migration.
  static const int currentSchemaVersion = 2;

  /// Target device id, or null when [groupId] is set.
  final String? deviceId;

  /// Target group id, or null when [deviceId] is set.
  final String? groupId;

  /// Canonical action name: `power`, `brightness`, `color`, `effect`, `speed`
  /// or `colorTemperature`.
  final String action;

  /// Action parameter. `bool` for power, `int` for brightness/speed/
  /// colorTemperature, `{red,green,blue}` for colour, `String` for effect.
  final dynamic value;

  const SceneAction({
    this.deviceId,
    this.groupId,
    required this.action,
    required this.value,
  });

  bool get targetsGroup => groupId != null;

  /// The single resolved target id (group or device), or null when invalid.
  String? get targetId => groupId ?? deviceId;

  /// The device capability this action needs, or null for an unknown action.
  DeviceCapability? get requiredCapability => switch (action) {
    'power' => DeviceCapability.power,
    'brightness' => DeviceCapability.brightness,
    'color' => DeviceCapability.color,
    'colorTemperature' => DeviceCapability.colorTemperature,
    'effect' => DeviceCapability.effect,
    'speed' => DeviceCapability.speed,
    _ => null,
  };

  /// Returns null when the action is well-formed, otherwise a human-readable
  /// reason. Used by both the editor and the executor.
  String? get validationError {
    if ((deviceId == null || deviceId!.isEmpty) &&
        (groupId == null || groupId!.isEmpty)) {
      return 'The action has no target.';
    }
    if (deviceId != null && groupId != null) {
      return 'An action cannot target a device and a group at once.';
    }
    switch (action) {
      case 'power':
        if (value is! bool) return 'Power must be on or off.';
      case 'brightness':
        final v = value;
        if (v is! int || v < 0 || v > 1000) {
          return 'Brightness must be between 0 and 1000.';
        }
      case 'speed':
        final v = value;
        if (v is! int || v < 0 || v > 100) {
          return 'Speed must be between 0 and 100.';
        }
      case 'colorTemperature':
        final v = value;
        if (v is! int || v < 1000 || v > 10000) {
          return 'Colour temperature must be between 1000K and 10000K.';
        }
      case 'color':
        if (value is! Map) return 'Colour must have red, green and blue.';
        final map = Map<String, dynamic>.from(value as Map);
        for (final channel in const ['red', 'green', 'blue']) {
          final v = map[channel];
          if (v is! int || v < 0 || v > 255) {
            return 'Colour channels must be between 0 and 255.';
          }
        }
      case 'effect':
        if (value is! String || (value as String).isEmpty) {
          return 'Choose an effect.';
        }
      default:
        return 'Unknown action "$action".';
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
    'deviceId': deviceId,
    'groupId': groupId,
    'action': action,
    'value': value,
  };

  factory SceneAction.fromJson(Map<String, dynamic> map) => SceneAction(
    deviceId: map['deviceId'] as String?,
    groupId: map['groupId'] as String?,
    action: map['action'] as String,
    value: map['value'],
  );

  @override
  List<Object?> get props => [deviceId, groupId, action, value];
}

/// A named, ordered collection of device/group actions that can be run
/// together.
class Scene extends Equatable {
  /// Current persisted schema version. Version 1 payloads omitted
  /// [schemaVersion]; they are read as 1 and remain executable.
  static const int currentSchemaVersion = 2;

  final String id;
  final String name;
  final String? description;
  final String? iconName;
  final List<SceneAction> actions;
  final bool favorite;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final int schemaVersion;

  const Scene({
    required this.id,
    required this.name,
    this.description,
    this.iconName,
    required this.actions,
    this.favorite = false,
    this.createdAt,
    this.updatedAt,
    this.schemaVersion = currentSchemaVersion,
  });

  Scene copyWith({
    String? id,
    String? name,
    String? description,
    String? iconName,
    List<SceneAction>? actions,
    bool? favorite,
    DateTime? createdAt,
    DateTime? updatedAt,
    int? schemaVersion,
  }) {
    return Scene(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      iconName: iconName ?? this.iconName,
      actions: actions ?? this.actions,
      favorite: favorite ?? this.favorite,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      schemaVersion: schemaVersion ?? this.schemaVersion,
    );
  }

  /// Number of explicit device/group targets in the scene.
  int get targetCount =>
      actions.map((a) => a.targetId).whereType<String>().toSet().length;

  /// Returns the first malformed action, or null when every action is valid.
  SceneAction? get firstInvalidAction =>
      actions.where((a) => a.validationError != null).firstOrNull;

  @override
  List<Object?> get props => [
    id,
    name,
    description,
    iconName,
    actions,
    favorite,
    createdAt,
    updatedAt,
    schemaVersion,
  ];
}
