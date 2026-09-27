import 'package:starlight/core/utils/app_logger.dart';
import 'package:starlight/domain/entities/scene.dart';
import 'package:starlight/domain/repositories/device_repository.dart';

/// Result of executing a scene.
class SceneExecutionResult {
  final bool success;
  final List<String> failures;
  final List<String> successes;

  const SceneExecutionResult({
    required this.success,
    this.failures = const [],
    this.successes = const [],
  });

  @override
  String toString() => 'SceneExecutionResult(success=$success, '
      'successes=${successes.length}, failures=${failures.length})';
}

/// Use case for executing a scene.
///
/// Validates each action against the target device's capabilities and
/// routes commands through the universal [DeviceRepository]. Does not
/// depend on any StarLight-specific types.
class ExecuteScene {
  final DeviceRepository repository;

  ExecuteScene(this.repository);

  Future<SceneExecutionResult> call(Scene scene) async {
    AppLog.info('ExecuteScene: ${scene.name} (${scene.actions.length} action(s))');
    final successes = <String>[];
    final failures = <String>[];

    for (final action in scene.actions) {
      final device = await repository.getDevice(action.deviceId);
      if (device == null) {
        failures.add('${action.deviceId}: device not found');
        continue;
      }

      final command = _commandFromAction(action);
      if (command == null) {
        failures.add('${action.deviceId}: unsupported action ${action.action}');
        continue;
      }

      try {
        await repository.sendCommand(action.deviceId, command);
        successes.add('${action.deviceId}:${action.action}');
      } catch (e) {
        failures.add('${action.deviceId}:${action.action} -> $e');
      }
    }

    return SceneExecutionResult(
      success: failures.isEmpty,
      successes: successes,
      failures: failures,
    );
  }

  DeviceCommand? _commandFromAction(SceneAction action) {
    switch (action.action) {
      case 'power':
        if (action.value is bool) {
          return DeviceCommand.power(action.value as bool);
        }
        return null;
      case 'brightness':
        if (action.value is num) {
          return DeviceCommand.brightness((action.value as num).toInt());
        }
        return null;
      case 'color':
        if (action.value is Map) {
          final map = action.value as Map;
          final r = (map['red'] as num?)?.toInt() ?? 0;
          final g = (map['green'] as num?)?.toInt() ?? 0;
          final b = (map['blue'] as num?)?.toInt() ?? 0;
          return DeviceCommand.color(r, g, b);
        }
        return null;
      case 'speed':
        if (action.value is num) {
          return DeviceCommand.speed((action.value as num).toInt());
        }
        return null;
      case 'colorTemperature':
        if (action.value is num) {
          return DeviceCommand.colorTemperature((action.value as num).toInt());
        }
        return null;
      case 'effect':
        if (action.value is String) {
          return DeviceCommand.effect(action.value as String);
        }
        return null;
      default:
        return DeviceCommand.custom(action.action, {'value': action.value});
    }
  }
}
