// SPDX-License-Identifier: Apache-2.0

import 'dart:math' as math;

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

import '../entities/effect_palette.dart';
import '../entities/rgb_color.dart';

/// A single rendered frame of a custom effect.
///
/// [pixels] is a preview strip (left → right); [global] is the single colour a
/// device without per-pixel control would receive. For addressable-only effects
/// [global] is a dim representative colour and physical playback is refused —
/// the renderer must never imply a capability the transport lacks.
@immutable
class CustomEffectSample extends Equatable {
  final List<RGBColor> pixels;
  final RGBColor global;

  const CustomEffectSample(this.pixels, this.global);

  @override
  List<Object?> get props => [pixels, global];
}

/// Everything a renderer may depend on. Time is an explicit input (never
/// `DateTime.now()` inside a renderer) so identical inputs — including the
/// [seed] — always produce identical output and can be asserted in tests.
@immutable
class CustomEffectInput {
  /// Elapsed time in seconds.
  final double time;

  /// Number of preview segments to produce (≥ 1).
  final int pixels;

  /// Speed in 0..1.
  final double speed;

  /// Intensity in 0..1.
  final double intensity;

  /// Palette to sample.
  final EffectPalette palette;

  /// Seed for deterministic pseudo-random variation.
  final int seed;

  const CustomEffectInput({
    required this.time,
    required this.pixels,
    required this.speed,
    required this.intensity,
    required this.palette,
    this.seed = 0,
  });

  CustomEffectInput copyWith({
    double? time,
    int? pixels,
    double? speed,
    double? intensity,
    EffectPalette? palette,
    int? seed,
  }) => CustomEffectInput(
    time: time ?? this.time,
    pixels: pixels ?? this.pixels,
    speed: speed ?? this.speed,
    intensity: intensity ?? this.intensity,
    palette: palette ?? this.palette,
    seed: seed ?? this.seed,
  );
}

/// Pure function rendering one frame for a given [CustomEffectInput].
typedef CustomEffectRender = CustomEffectSample Function(CustomEffectInput i);

// --- Math helpers (all outputs bounded) ---

double _speedFactor(double speed) => 0.25 + 1.75 * speed.clamp(0.0, 1.0);

/// Linear interpolation.
double _lerp(double a, double b, double t) => a + (b - a) * t.clamp(0.0, 1.0);

/// Sine wave mapped to 0..1.
double _wave(double t, double freq, double phase) =>
    0.5 + 0.5 * math.sin(2 * math.pi * (t * freq + phase));

/// Deterministic integer hash → value in [0, 1).
double _hash01(int a, int b) {
  var h = (0x811c9dc5 ^ (a & 0x7fffffff)) & 0xffffffff;
  h = (h ^ (b & 0x7fffffff)) & 0xffffffff;
  h = (h * 0x01000193) & 0xffffffff;
  h ^= h >> 15;
  h = (h * 0x2c1b3c6d) & 0xffffffff;
  h ^= h >> 12;
  return (h & 0xffffff) / 0x1000000;
}

/// 1D simplex-like noise for organic variation.
double _noise1d(double x, int seed) {
  final i = x.floor();
  final f = x - i;
  final u = f * f * (3.0 - 2.0 * f);
  return _lerp(_hash01(seed, i), _hash01(seed, i + 1), u);
}

// --- Renderers ---

/// Aurora: Slow, multi-layer colour ribbons drifting like a night sky.
/// Global: Cycles through the full palette as the dominant ribbon moves.
CustomEffectSample _aurora(CustomEffectInput i) {
  final n = math.max(1, i.pixels);
  final sf = _speedFactor(i.speed);
  final ff = i.intensity.clamp(0.0, 1.0);
  final pixels = <RGBColor>[];
  for (var idx = 0; idx < n; idx++) {
    final x = n == 1 ? 0.5 : idx / (n - 1);
    // Multiple noise octaves for rich texture
    final n1 = _noise1d(x * 3.0 + i.time * 0.11 * sf, i.seed);
    final n2 = _noise1d(x * 6.0 - i.time * 0.07 * sf, i.seed + 1000);
    final n3 = _noise1d(x * 1.5 + i.time * 0.03 * sf, i.seed + 2000);
    final v = (0.5 * n1 + 0.3 * n2 + 0.2 * n3).clamp(0.0, 1.0);
    final pos = 0.15 + 0.7 * v;
    pixels.add(scaleRgb(i.palette.sample(pos), (0.25 + 0.75 * v) * ff));
  }
  // Global: follows the center-of-mass of the brightest ribbon
  final centerPos =
      0.15 +
      0.7 *
          ((0.5 * _noise1d(0.5 * 3.0 + i.time * 0.11 * sf, i.seed) +
                  0.3 *
                      _noise1d(0.5 * 6.0 - i.time * 0.07 * sf, i.seed + 1000) +
                  0.2 * _noise1d(0.5 * 1.5 + i.time * 0.03 * sf, i.seed + 2000))
              .clamp(0.0, 1.0));
  return CustomEffectSample(pixels, scaleRgb(i.palette.sample(centerPos), ff));
}

/// Ember: Warm embers with a slow, deterministic flicker.
/// Global: Flickers with the same stochastic rhythm as the strip.
CustomEffectSample _ember(CustomEffectInput i) {
  final n = math.max(1, i.pixels);
  final sf = _speedFactor(i.speed);
  final ff = i.intensity.clamp(0.0, 1.0);
  final tick = (i.time * (4 + 10 * sf)).floor();
  final pixels = <RGBColor>[];
  for (var idx = 0; idx < n; idx++) {
    // Per-pixel deterministic flicker using hash
    final flicker = _hash01(i.seed, idx + tick * 131);
    // Slow spatial wave for ember movement
    final slow = _wave(i.time, 0.5 * sf, idx * 0.13);
    // Combine: flicker dominates, slow wave modulates
    final level =
        (0.2 + 0.8 * (0.7 * flicker + 0.3 * slow)).clamp(0.0, 1.0) * ff;
    // Sample from warm palette region (0.0 to 0.4)
    final pos = 0.05 + 0.35 * level;
    pixels.add(scaleRgb(i.palette.sample(pos), level));
  }
  // Global: uses the same tick-based flicker as pixel 0 (deterministic, no spatial avg)
  final globalFlicker = _hash01(i.seed, tick * 131);
  final globalSlow = _wave(i.time, 0.5 * sf, 0.13);
  final globalLevel =
      (0.2 + 0.8 * (0.7 * globalFlicker + 0.3 * globalSlow)).clamp(0.0, 1.0) *
      ff;
  final globalPos = 0.05 + 0.35 * globalLevel;
  return CustomEffectSample(
    pixels,
    scaleRgb(i.palette.sample(globalPos), globalLevel),
  );
}

/// Ocean Drift: Slow blue/teal swell, like light through deep water.
/// Global: Follows the interference pattern's phase at center.
CustomEffectSample _oceanDrift(CustomEffectInput i) {
  final n = math.max(1, i.pixels);
  final sf = _speedFactor(i.speed);
  final ff = i.intensity.clamp(0.0, 1.0);
  final pixels = <RGBColor>[];
  for (var idx = 0; idx < n; idx++) {
    final x = n == 1 ? 0.5 : idx / (n - 1);
    // Two waves with different spatial frequencies and time offsets
    final v1 = _wave(i.time, 0.09 * sf, x * 0.7 + 0.15);
    final v2 = _wave(i.time, 0.05 * sf, 0.4 - x * 0.3);
    // Interference pattern
    final v = (0.6 * v1 + 0.4 * v2).clamp(0.0, 1.0);
    final pos = 0.1 + 0.55 * v;
    pixels.add(scaleRgb(i.palette.sample(pos), (0.4 + 0.6 * v) * ff));
  }
  // Global: interference at center (x=0.5)
  final centerV1 = _wave(i.time, 0.09 * sf, 0.5 * 0.7 + 0.15);
  final centerV2 = _wave(i.time, 0.05 * sf, 0.4 - 0.5 * 0.3);
  final centerV = (0.6 * centerV1 + 0.4 * centerV2).clamp(0.0, 1.0);
  final centerPos = 0.1 + 0.55 * centerV;
  return CustomEffectSample(
    pixels,
    scaleRgb(i.palette.sample(centerPos), (0.4 + 0.6 * centerV) * ff),
  );
}

/// Meteor: A bright head with a fading trail travelling along the strip.
/// Needs per-pixel output, so it is preview-only on single-colour transports.
/// Global: Pulses when the meteor head crosses the center; dim between passes.
CustomEffectSample _meteor(CustomEffectInput i) {
  final n = math.max(1, i.pixels);
  final sf = _speedFactor(i.speed);
  final ff = i.intensity.clamp(0.0, 1.0);
  if (ff <= 0.0) {
    return CustomEffectSample(
      List<RGBColor>.filled(n, const RGBColor(0, 0, 0)),
      const RGBColor(0, 0, 0),
    );
  }
  final head = (i.time * (0.15 + 0.5 * sf)) % 1.0;
  final pixels = <RGBColor>[];
  for (var idx = 0; idx < n; idx++) {
    final x = n == 1 ? 0.5 : idx / (n - 1);
    var d = x - head;
    if (d < 0) d += 1.0;
    // Quadratic falloff for sharp trail
    final trail = math.pow(math.max(0.0, 1.0 - d * 3.0), 2).toDouble();
    // Add subtle noise to trail edges
    final noise = _noise1d(x * 10.0 + i.time * 0.5, i.seed + 500) * 0.1;
    pixels.add(
      scaleRgb(i.palette.sample(0.85), (trail * ff + noise).clamp(0.0, 1.0)),
    );
  }
  // Global: bright when head crosses center (x=0.5), dim otherwise
  var centerD = 0.5 - head;
  if (centerD < 0) centerD += 1.0;
  final centerTrail = math
      .pow(math.max(0.0, 1.0 - centerD * 3.0), 2)
      .toDouble();
  final centerNoise = _noise1d(0.5 * 10.0 + i.time * 0.5, i.seed + 500) * 0.1;
  return CustomEffectSample(
    pixels,
    scaleRgb(
      i.palette.sample(0.85),
      (centerTrail * ff + centerNoise).clamp(0.0, 1.0),
    ),
  );
}

/// Prism Flow: Continuous movement through a palette.
/// Global: Cycles through the full palette at the travelling wave's frequency.
CustomEffectSample _prismFlow(CustomEffectInput i) {
  final n = math.max(1, i.pixels);
  final sf = _speedFactor(i.speed);
  final ff = i.intensity.clamp(0.0, 1.0);
  final pixels = <RGBColor>[];
  for (var idx = 0; idx < n; idx++) {
    final x = n == 1 ? 0.5 : idx / (n - 1);
    // Travelling hue wave
    final hue = (x * 0.6 + i.time * 0.18 * sf) % 1.0;
    // Breathing intensity envelope
    final level = (0.7 + 0.3 * _wave(i.time, 0.5 * sf, x)).clamp(0.0, 1.0) * ff;
    pixels.add(scaleRgb(i.palette.sample(hue), level));
  }
  // Global: follows the wave at center (x=0.5)
  final centerHue = (0.5 * 0.6 + i.time * 0.18 * sf) % 1.0;
  final centerLevel =
      (0.7 + 0.3 * _wave(i.time, 0.5 * sf, 0.5)).clamp(0.0, 1.0) * ff;
  return CustomEffectSample(
    pixels,
    scaleRgb(i.palette.sample(centerHue), centerLevel),
  );
}

/// Soft Breath: Smooth, non-linear intensity breathing.
/// Global: Breathes with the same non-linear envelope as all pixels.
CustomEffectSample _softBreath(CustomEffectInput i) {
  final n = math.max(1, i.pixels);
  final sf = _speedFactor(i.speed);
  final ff = i.intensity.clamp(0.0, 1.0);
  // Squared sine for non-linear breathing (slow at peaks, fast through zero)
  final level = math.pow(_wave(i.time, 0.25 * sf, 0.0), 2).toDouble();
  final colour = scaleRgb(i.palette.sample(0.0), (0.06 + 0.94 * level) * ff);
  return CustomEffectSample(List<RGBColor>.filled(n, colour), colour);
}

/// Color Bloom: A palette-driven bloom that breathes from the centre outward.
/// Global: Breathes with the center brightness, palette cycles slowly.
CustomEffectSample _colorBloom(CustomEffectInput i) {
  final n = math.max(1, i.pixels);
  final sf = _speedFactor(i.speed);
  final ff = i.intensity.clamp(0.0, 1.0);
  final pixels = <RGBColor>[];
  for (var idx = 0; idx < n; idx++) {
    final x = n == 1 ? 0.5 : idx / (n - 1);
    // Radial distance from center
    final radial = (1.0 - (2.0 * x - 1.0).abs()).clamp(0.0, 1.0);
    // Bloom shape: sharper at center
    final bloom = math.pow(radial, 1.5).toDouble();
    // Palette position varies with spatial position
    final pos = 0.08 + 0.75 * x;
    // Breathing envelope modulates bloom intensity
    final level = (0.35 + 0.65 * bloom).clamp(0.0, 1.0) * ff;
    pixels.add(scaleRgb(i.palette.sample(pos), level));
  }
  // Center color for global representative: breathes, palette cycles
  final centerBreath =
      (0.5 + 0.5 * _wave(i.time, 0.2 * sf, 0.0)).clamp(0.0, 1.0) * ff;
  final centerPalettePos = (0.08 + 0.75 * 0.5 + i.time * 0.02 * sf) % 1.0;
  return CustomEffectSample(
    pixels,
    scaleRgb(i.palette.sample(centerPalettePos), centerBreath),
  );
}

/// Starlight: Sparse, independently fading points of light.
/// Each pixel has independent stochastic twinkle timing.
/// Needs per-pixel output, so it is preview-only on single-colour transports.
/// Global: Very dim average (most pixels are off at any moment).
CustomEffectSample _starlight(CustomEffectInput i) {
  final n = math.max(1, i.pixels);
  final sf = _speedFactor(i.speed);
  final ff = i.intensity.clamp(0.0, 1.0);
  final rate = 0.4 + 0.8 * sf;
  final pixels = <RGBColor>[];
  for (var idx = 0; idx < n; idx++) {
    final seed = _hash01(i.seed, idx);
    // Each pixel twinkles at its own phase
    final phase = seed * 10.0;
    final twinkleRaw = math.sin(2 * math.pi * (i.time * rate + phase));
    // High power for sharp on/off twinkle
    final twinkle = math.pow(math.max(0.0, twinkleRaw), 8).toDouble();
    final visible = twinkle > 0.02 ? 1.0 : 0.0;
    final level = (0.05 + 0.95 * twinkle).clamp(0.0, 1.0);
    pixels.add(
      scaleRgb(i.palette.sample(0.05 + 0.2 * seed), level * ff * visible),
    );
  }
  // Global: statistical average (very dim, since most pixels are off)
  // We use a fixed low level representative of the sparse twinkle
  return CustomEffectSample(pixels, scaleRgb(i.palette.sample(0.6), 0.08 * ff));
}

/// Registry of custom effect renderers, keyed by effect ID.
///
/// This is the single source of truth for which renderer implements which
/// custom effect. The keys must match the `id` field of each
/// [EffectDefinition] in `kCustomEffects`.
final Map<String, CustomEffectRender> kCustomEffectRenderers = {
  'custom-aurora': _aurora,
  'custom-ember': _ember,
  'custom-ocean-drift': _oceanDrift,
  'custom-meteor': _meteor,
  'custom-prism-flow': _prismFlow,
  'custom-soft-breath': _softBreath,
  'custom-color-bloom': _colorBloom,
  'custom-starlight': _starlight,
};

/// Renders a custom effect by [effectId] with the given [input].
///
/// Returns `null` if [effectId] is not a known custom effect.
CustomEffectSample? renderCustomEffect(
  String effectId,
  CustomEffectInput input,
) {
  final renderer = kCustomEffectRenderers[effectId];
  if (renderer == null) return null;
  return renderer(input);
}
