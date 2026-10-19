// SPDX-License-Identifier: Apache-2.0

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

import '../../core/utils/app_logger.dart';
import '../entities/device_capability.dart';
import '../entities/device_command.dart';
import '../entities/effect.dart';
import 'command_router.dart';

/// The outcome of an effect execution attempt.
enum EffectOutcome {
  /// The command was written to the transport without a reported failure.
  ///
  /// This is deliberately *not* "the effect is running": a successful write is
  /// only transport acceptance, never an observed hardware outcome.
  sent,

  /// The active route cannot execute the request (no effect/speed capability,
  /// an unverified profile, or a command the route has no mapping for).
  unsupported,

  /// A parameter (for example speed) was outside its validated range, or the
  /// effect has no such parameter.
  invalidParameter,

  /// The device is not connected, or disconnected before the write completed.
  notConnected,

  /// The active device changed while the request was in flight, so the result
  /// was discarded rather than applied to the wrong device.
  stale,

  /// The transport reported a failure (timeout, write error, …).
  transportError,
}

/// A typed result for an effect request.
///
/// Callers must branch on [outcome]; [isSent] is the only success case and it
/// still only means "the write completed".
@immutable
class EffectCommandResult extends Equatable {
  final EffectOutcome outcome;

  /// Stable machine-readable code (`unsupported`, `speed_out_of_range`,
  /// `not_connected`, …), or null when not applicable.
  final String? code;

  /// Human-readable message suitable for surfacing to the user.
  final String? message;

  const EffectCommandResult(this.outcome, [this.code, this.message]);

  const EffectCommandResult.sent() : this(EffectOutcome.sent, 'sent', null);

  const EffectCommandResult.unsupported([String? message])
    : this(EffectOutcome.unsupported, 'unsupported', message);

  const EffectCommandResult.invalidParameter(String code, [String? message])
    : this(EffectOutcome.invalidParameter, code, message);

  const EffectCommandResult.notConnected([String? message])
    : this(EffectOutcome.notConnected, 'not_connected', message);

  const EffectCommandResult.stale() : this(EffectOutcome.stale, 'stale', null);

  const EffectCommandResult.transportError(String code, [String? message])
    : this(EffectOutcome.transportError, code, message);

  /// Whether the transport accepted the write. Never implies an observed
  /// device outcome.
  bool get isSent => outcome == EffectOutcome.sent;

  @override
  List<Object?> get props => [outcome, code, message];

  @override
  String toString() => 'EffectCommandResult(${outcome.name}, $code)';
}

/// A small execution engine for device-native effects.
///
/// It is the *only* effect path: it validates a definition and its parameters
/// against the active route's capabilities, then dispatches through the shared
/// [CommandRouter] — so the single BLE owner, the serialized write queue and the
/// verified custom-profile executor are all respected. It never encodes bytes
/// itself and never sends an MR Star packet for a custom-profile route (that
/// decision belongs to the router).
///
/// Staleness: the engine is bound to the active device (or invalidated on
/// disconnect/route change). If the binding changes while a request is in
/// flight, the request resolves to [EffectOutcome.stale] instead of reporting a
/// success that belongs to a device the user has since left.
class EffectEngine {
  final CommandRouter _router;

  /// Monotonic token bumped whenever the active device/route changes.
  int _epoch = 0;
  String? _deviceId;

  EffectEngine(this._router);

  /// Capabilities the active route can execute (mirrors the router).
  Set<DeviceCapability> get capabilities => _router.capabilities;

  /// Binds the engine to the active device id. Any change invalidates in-flight
  /// work so a stale result is never applied to a different device.
  void bindDevice(String? deviceId) {
    if (deviceId == _deviceId) return;
    _deviceId = deviceId;
    _epoch++;
    AppLog.debug(
      'effects: bound to device=${deviceId ?? 'none'} epoch=$_epoch',
    );
  }

  /// Invalidates in-flight work without changing the device id (used on
  /// disconnect or route/capability changes).
  void invalidate() => _epoch++;

  /// Selects a device-pattern [effect], optionally setting its [speed] in the
  /// same request.
  ///
  /// Only [EffectKind.hardwareNative] effects can be applied here; custom
  /// effects are played by [CustomEffectPlayer], never by this method.
  ///
  /// Validation order: declared capabilities → parameter range → dispatch. The
  /// result is [EffectOutcome.stale] if the device changed mid-flight.
  Future<EffectCommandResult> apply(
    EffectDefinition effect, {
    int? speed,
  }) async {
    final commandName = effect.commandName;
    if (effect.kind != EffectKind.hardwareNative || commandName == null) {
      return const EffectCommandResult.unsupported(
        'That effect is not a device pattern.',
      );
    }

    for (final required in effect.requires) {
      if (!_router.capabilities.contains(required)) {
        return const EffectCommandResult.unsupported(
          'Effects are not available on the active route.',
        );
      }
    }

    if (speed != null) {
      final range = effect.speedRange;
      if (range == null) {
        return const EffectCommandResult.invalidParameter(
          'speed_not_supported',
          'This effect does not support a speed parameter.',
        );
      }
      if (!_router.capabilities.contains(DeviceCapability.speed)) {
        return const EffectCommandResult.unsupported(
          'Speed is not available on the active route.',
        );
      }
      if (!range.contains(speed)) {
        return EffectCommandResult.invalidParameter(
          'speed_out_of_range',
          'Speed must be between ${range.min} and ${range.max}.',
        );
      }
    }

    return _dispatch((router) async {
      await router.send(DeviceCommand.effect(commandName));
      if (speed != null) {
        await router.send(DeviceCommand.speed(speed));
      }
    });
  }

  /// Sets the mode speed for the currently active effect.
  ///
  /// Uses the app-wide [kMrStarSpeedRange]; per-effect ranges are applied by
  /// [apply] when an effect is selected together with a speed.
  Future<EffectCommandResult> setSpeed(int speed) async {
    if (!_router.capabilities.contains(DeviceCapability.speed)) {
      return const EffectCommandResult.unsupported(
        'Speed is not available on the active route.',
      );
    }
    if (!kMrStarSpeedRange.contains(speed)) {
      return EffectCommandResult.invalidParameter(
        'speed_out_of_range',
        'Speed must be between ${kMrStarSpeedRange.min} and '
            '${kMrStarSpeedRange.max}.',
      );
    }
    return _dispatch((router) => router.send(DeviceCommand.speed(speed)));
  }

  Future<EffectCommandResult> _dispatch(
    Future<void> Function(CommandRouter router) action,
  ) async {
    final epoch = _epoch;
    try {
      await action(_router);
    } on CommandRoutingException catch (e) {
      if (_epoch != epoch) return const EffectCommandResult.stale();
      return _mapRoutingError(e);
    } catch (e) {
      if (_epoch != epoch) return const EffectCommandResult.stale();
      AppLog.error('effects: unexpected send failure', e);
      return EffectCommandResult.transportError('transport_error', '$e');
    }
    if (_epoch != epoch) return const EffectCommandResult.stale();
    return const EffectCommandResult.sent();
  }

  EffectCommandResult _mapRoutingError(CommandRoutingException e) {
    switch (e.code) {
      case 'unsupported_command':
      case 'profile_not_verified':
        return EffectCommandResult.unsupported(e.message);
      case 'invalid_parameter':
        return EffectCommandResult.invalidParameter(e.code, e.message);
      case 'not_connected':
      case 'device_not_found':
        return EffectCommandResult.notConnected(e.message);
      default:
        // write_timeout, connection_timeout, transport_error, …
        return EffectCommandResult.transportError(e.code, e.message);
    }
  }
}
