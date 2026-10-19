// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import '../../core/utils/app_logger.dart';
import '../entities/device_command.dart';
import '../entities/effect.dart';
import '../entities/effect_palette.dart';
import 'command_router.dart';
import 'custom_effect_renderer.dart';
import 'effect_engine.dart';

/// Streams a [EffectKind.custom] effect to the active device as a bounded
/// sequence of **global** colour writes.
///
/// Safety and honesty rules this class enforces:
/// * It never opens a connection and never writes directly to BLE — every frame
///   goes through the shared [CommandRouter], so `BleDataSource` stays the
///   single transport owner and the serialized queue still applies.
/// * It refuses effects that need per-pixel output ([EffectPlayback.previewOnly])
///   instead of faking them with colour/brightness commands.
/// * Frames are rate-bounded ([frameInterval], never faster than 20 fps) and
///   coalesced: while a write is in flight the next tick is skipped, so a slow
///   link can never grow an unbounded command backlog.
/// * Exactly one timer exists; it is cancelled on [stop] and on [invalidate]
///   (device change / disconnect). A stale in-flight result is discarded.
///
/// **Hardware reality check**: The MR Star controller is a single-zone RGB
/// device. It can only display one colour at a time. The preview in Effects
/// Studio renders a 16-pixel spatial simulation, but the hardware receives
/// only [CustomEffectSample.global] — one colour per frame. This means:
/// - Effects with spatial patterns (Meteor, Starlight) are preview-only.
/// - Global-RGB effects (Aurora, Ember, Ocean Drift, Prism Flow, Soft Breath,
///   Color Bloom) appear as **temporal colour sequences** on the device.
/// - The preview's spatial animation does not exist on the physical light.
/// - A successful BLE write only means the colour packet was accepted by the
///   transport, NOT that the effect is visibly running on the hardware.
///
/// **Update rate assumptions** (no physical validation performed):
/// - Default [frameInterval] = 90 ms (~11 fps).
/// - Minimum allowed = 50 ms (20 fps) — values below are clamped.
/// - The controller's actual sustainable write rate is UNKNOWN.
/// - If the BLE link is slow, frames are coalesced (dropped) to avoid backlog.
/// - The [targetFrameRate] parameter can be overridden for testing or when
///   hardware validation provides a real number.
class CustomEffectPlayer {
  final CommandRouter _router;

  /// How often a frame may be produced. Values below 50 ms are clamped up so
  /// the player can never flood the transport.
  ///
  /// **Default: 90 ms (~11 fps). This is an assumption, not a verified rate.**
  /// Override with a verified value if hardware testing provides one.
  final Duration frameInterval;

  Timer? _timer;
  int _epoch = 0;
  bool _inFlight = false;

  String? _effectId;
  int _speed = 50;
  int _intensity = 70;
  EffectPalette? _palette;
  int _seed = 0;
  final Stopwatch _clock = Stopwatch();

  /// Invoked when playback stops by itself (a frame failed, the device
  /// disconnected, …). Not invoked for an explicit [stop] or [invalidate].
  void Function(EffectCommandResult result)? onStopped;

  CustomEffectPlayer(
    this._router, {
    Duration frameInterval = const Duration(milliseconds: 90),
  }) : frameInterval = frameInterval < const Duration(milliseconds: 50)
           ? const Duration(milliseconds: 50)
           : frameInterval;

  /// Whether a playback timer is currently running.
  bool get isPlaying => _timer != null;

  /// The id of the effect currently playing, or `null`.
  String? get effectId => _effectId;

  /// Validates [effect] and the parameters without starting playback.
  ///
  /// Returns `null` when the request is valid, otherwise a typed failure.
  EffectCommandResult? validate(
    EffectDefinition effect, {
    int? speed,
    int? intensity,
    String? paletteId,
  }) {
    if (effect.kind != EffectKind.custom) {
      return const EffectCommandResult.unsupported(
        'That effect is not a StarLight custom effect.',
      );
    }
    if (effect.playback != EffectPlayback.colorSequence) {
      return const EffectCommandResult.unsupported(
        'This effect needs addressable LEDs, so it can only be previewed.',
      );
    }
    for (final required in effect.requires) {
      if (!_router.capabilities.contains(required)) {
        return const EffectCommandResult.unsupported(
          'Custom effects are not available on the active route.',
        );
      }
    }
    final resolvedSpeed = speed ?? _speed;
    final speedRange = effect.speedRange;
    if (speedRange != null && !speedRange.contains(resolvedSpeed)) {
      return EffectCommandResult.invalidParameter(
        'speed_out_of_range',
        'Speed must be between ${speedRange.min} and ${speedRange.max}.',
      );
    }
    final resolvedIntensity = intensity ?? _intensity;
    final intensityRange = effect.intensityRange;
    if (intensityRange != null && !intensityRange.contains(resolvedIntensity)) {
      return EffectCommandResult.invalidParameter(
        'intensity_out_of_range',
        'Intensity must be between ${intensityRange.min} and '
            '${intensityRange.max}.',
      );
    }
    return null;
  }

  /// Starts playing [effect]. Any previous playback is stopped first, so there
  /// is at most one timer and one effect at a time.
  Future<EffectCommandResult> start(
    EffectDefinition effect, {
    int? speed,
    int? intensity,
    String? paletteId,
  }) async {
    stop();

    final invalid = validate(
      effect,
      speed: speed,
      intensity: intensity,
      paletteId: paletteId,
    );
    if (invalid != null) return invalid;

    if (speed != null) _speed = speed;
    if (intensity != null) _intensity = intensity;
    _palette =
        effectPaletteById(paletteId) ??
        effectPaletteById(effect.defaultPaletteId) ??
        _palette ??
        kEffectPalettes.first;
    _seed = effect.id.hashCode & 0x7fffffff;
    _effectId = effect.id;
    _clock
      ..reset()
      ..start();

    // Send the first frame promptly; a failure here means there is nothing to
    // play, so report it instead of leaving a half-started timer.
    final firstError = await _sendFrame(reportStopped: false);
    if (firstError != null) {
      return firstError;
    }

    final epoch = _epoch;
    _timer = Timer.periodic(frameInterval, (_) {
      if (_timer == null || epoch != _epoch) return;
      unawaited(_sendFrame());
    });
    AppLog.info(
      'CustomEffectPlayer: playing ${effect.id} '
      '(speed=$_speed intensity=$_intensity palette=${_palette?.id})',
    );
    return const EffectCommandResult.sent();
  }

  /// Stops playback. The effect stays selected in the bloc's bookkeeping.
  void stop() {
    if (_timer == null && _effectId == null) return;
    _stopInternal();
    AppLog.info('CustomEffectPlayer: stopped');
  }

  /// Invalidates any in-flight work and stops playback (device change or
  /// disconnect). The pending result of an in-flight write is discarded.
  void invalidate() {
    _epoch++;
    _stopInternal();
  }

  /// Applies new rendering parameters to an active playback without restarting.
  ///
  /// Values outside the advertised 0–100 range are ignored (not clamped), so a
  /// caller bug cannot silently distort the output.
  void updateParameters({int? speed, int? intensity, String? paletteId}) {
    if (speed != null && kEffectSpeedRange.contains(speed)) _speed = speed;
    if (intensity != null && kEffectIntensityRange.contains(intensity)) {
      _intensity = intensity;
    }
    if (paletteId != null) {
      _palette = effectPaletteById(paletteId) ?? _palette;
    }
  }

  void _stopInternal() {
    _timer?.cancel();
    _timer = null;
    _effectId = null;
    _inFlight = false;
    _clock.stop();
  }

  /// Renders and writes one frame.
  ///
  /// Returns a terminal error result when the write failed and playback was
  /// stopped; otherwise `null`. A frame that arrives while a previous write is
  /// still in flight is coalesced (dropped) rather than queued.
  Future<EffectCommandResult?> _sendFrame({bool reportStopped = true}) async {
    if (_inFlight) return null; // coalesce: never grow the write queue
    final id = _effectId;
    final palette = _palette;
    if (id == null || palette == null) return null;
    final renderer = kCustomEffectRenderers[id];
    if (renderer == null) return null;

    final epoch = _epoch;
    final sample = renderer(
      CustomEffectInput(
        time: _clock.elapsedMilliseconds / 1000.0,
        pixels: 16,
        speed: _speed / 100.0,
        intensity: _intensity / 100.0,
        palette: palette,
        seed: _seed,
      ),
    );

    _inFlight = true;
    EffectCommandResult? error;
    try {
      await _router.send(
        DeviceCommand.color(
          sample.global.red,
          sample.global.green,
          sample.global.blue,
        ),
      );
    } on CommandRoutingException catch (e) {
      error = _mapRoutingError(e);
    } catch (e) {
      error = EffectCommandResult.transportError('transport_error', '$e');
    } finally {
      _inFlight = false;
    }

    if (error != null && epoch == _epoch) {
      _stopInternal();
      if (reportStopped) onStopped?.call(error);
      return error;
    }
    return null;
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
        return EffectCommandResult.transportError(e.code, e.message);
    }
  }
}
