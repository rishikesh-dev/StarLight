// SPDX-License-Identifier: Apache-2.0

import 'package:starlight/core/errors/exceptions.dart';
import 'package:starlight/core/utils/app_logger.dart';
import 'package:starlight/domain/entities/connection_state.dart';
import 'package:starlight/domain/entities/device.dart';
import 'package:starlight/domain/entities/device_capability.dart';
import 'package:starlight/domain/entities/device_command.dart';
import 'package:starlight/domain/entities/execution_result.dart';
import 'package:starlight/domain/services/command_router.dart';

/// The single place where a high-level action (`power`, `brightness`, `color`,
/// `effect`, `speed`, `colorTemperature`) becomes a validated
/// [DeviceCommand] that is actually written to hardware.
///
/// Every group and scene run goes through here, which is what keeps the
/// invariants true for all of them:
///
/// * commands are validated and type-checked before anything is encoded, so
///   malformed stored data can never reach the transport;
/// * each device's capabilities are checked *independently*, so one capable
///   member never authorises a command for the rest of the group;
/// * the write goes through [CommandRouter], so the verified custom-profile
///   gate and the single BLE owner/serialised command queue are respected —
///   this class never opens a connection or writes a characteristic itself;
/// * execution is sequential. Nothing here claims concurrency.
class DeviceCommandDispatcher {
  final CommandRouter _router;

  DeviceCommandDispatcher(this._router);

  /// Validates and applies one action to one device.
  ///
  /// Never throws: every failure mode (unknown device, unsupported capability,
  /// not connected, invalid value, routing/transport rejection) is returned as a
  /// [DeviceActionResult] so callers can report per-device outcomes honestly.
  Future<DeviceActionResult> apply({
    required Device device,
    required String action,
    required Object? value,
  }) async {
    DeviceActionResult failure(ExecutionOutcome outcome, String message) =>
        DeviceActionResult(
          deviceId: device.id,
          deviceName: device.name,
          action: action,
          outcome: outcome,
          message: message,
        );

    final validation = validateAction(action, value);
    if (validation != null)
      return failure(ExecutionOutcome.invalid, validation);

    final capability = capabilityFor(action);
    if (capability == null) {
      return failure(ExecutionOutcome.unsupported, 'Unknown action "$action".');
    }
    if (!device.supports(capability)) {
      return failure(
        ExecutionOutcome.unsupported,
        '${device.name} does not support ${capability.label.toLowerCase()}.',
      );
    }
    if (device.connectionState != DeviceConnectionState.connected) {
      return failure(
        ExecutionOutcome.notConnected,
        '${device.name} is not connected.',
      );
    }

    final command = buildCommand(action, value);
    if (command == null) {
      return failure(
        ExecutionOutcome.invalid,
        'The value for "$action" is not valid.',
      );
    }

    try {
      await _router.send(command);
      return DeviceActionResult(
        deviceId: device.id,
        deviceName: device.name,
        action: action,
        outcome: ExecutionOutcome.success,
      );
    } on CommandRoutingException catch (e) {
      AppLog.warn('Dispatcher: ${device.name} rejected $action (${e.code})');
      return failure(_outcomeForCode(e.code), e.message);
    } on ValidationException catch (e) {
      return failure(ExecutionOutcome.invalid, e.message);
    } catch (e) {
      AppLog.error('Dispatcher: ${device.name} failed $action: $e');
      return failure(ExecutionOutcome.failed, 'The command could not be sent.');
    }
  }

  /// The device capability an action requires, or null for an unknown action.
  static DeviceCapability? capabilityFor(String action) => switch (action) {
    'power' => DeviceCapability.power,
    'brightness' => DeviceCapability.brightness,
    'color' => DeviceCapability.color,
    'colorTemperature' => DeviceCapability.colorTemperature,
    'effect' => DeviceCapability.effect,
    'speed' => DeviceCapability.speed,
    _ => null,
  };

  /// Checks an action's parameter shape without touching hardware.
  ///
  /// Returns null when valid, otherwise a message safe to show in the editor.
  static String? validateAction(String action, Object? value) {
    switch (action) {
      case 'power':
        if (value is! bool) return 'Power must be on or off.';
      case 'brightness':
        if (value is! int || value < 0 || value > 1000) {
          return 'Brightness must be between 0 and 1000.';
        }
      case 'speed':
        if (value is! int || value < 0 || value > 100) {
          return 'Speed must be between 0 and 100.';
        }
      case 'colorTemperature':
        if (value is! int || value < 1000 || value > 10000) {
          return 'Colour temperature must be between 1000K and 10000K.';
        }
      case 'color':
        final rgb = readColor(value);
        if (rgb == null) return 'Colour must have red, green and blue values.';
      case 'effect':
        if (value is! String || value.isEmpty) return 'Choose an effect.';
      default:
        return 'Unknown action "$action".';
    }
    return null;
  }

  /// Builds the command for a validated action, or null when the action is not
  /// one StarLight can send.
  static DeviceCommand? buildCommand(String action, Object? value) {
    switch (action) {
      case 'power':
        return value is bool ? DeviceCommand.power(value) : null;
      case 'brightness':
        return value is int ? DeviceCommand.brightness(value) : null;
      case 'speed':
        return value is int ? DeviceCommand.speed(value) : null;
      case 'colorTemperature':
        return value is int ? DeviceCommand.colorTemperature(value) : null;
      case 'color':
        final rgb = readColor(value);
        return rgb == null ? null : DeviceCommand.color(rgb.$1, rgb.$2, rgb.$3);
      case 'effect':
        return value is String && value.isNotEmpty
            ? DeviceCommand.effect(value)
            : null;
      default:
        return null;
    }
  }

  /// Reads an RGB triplet from loosely-typed stored data.
  ///
  /// Numbers arriving from JSON can be `int` or `double`, so both are accepted;
  /// anything else is rejected instead of being coerced to a wrong colour.
  static (int, int, int)? readColor(Object? value) {
    if (value is! Map) return null;
    int? channel(String key) {
      final raw = value[key];
      if (raw is int) return raw;
      if (raw is num && raw == raw.roundToDouble()) return raw.toInt();
      return null;
    }

    final r = channel('red');
    final g = channel('green');
    final b = channel('blue');
    if (r == null || g == null || b == null) return null;
    if (r < 0 || r > 255 || g < 0 || g > 255 || b < 0 || b > 255) return null;
    return (r, g, b);
  }

  static ExecutionOutcome _outcomeForCode(String code) => switch (code) {
    'unsupported_command' ||
    'profile_not_verified' => ExecutionOutcome.unsupported,
    'invalid_parameter' => ExecutionOutcome.invalid,
    'not_connected' => ExecutionOutcome.notConnected,
    _ => ExecutionOutcome.failed,
  };
}
