// SPDX-License-Identifier: Apache-2.0

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

import 'rgb_color.dart';

/// Linearly interpolates between two colours for [t] in 0..1 (clamped).
///
/// Kept in the domain because palettes and custom-effect renderers are pure
/// data/algorithm code and must not depend on Flutter's painting layer.
RGBColor lerpRgb(RGBColor a, RGBColor b, double t) {
  final k = t.clamp(0.0, 1.0);
  int mix(int x, int y) => (x + (y - x) * k).round().clamp(0, 255);
  return RGBColor(
    mix(a.red, b.red),
    mix(a.green, b.green),
    mix(a.blue, b.blue),
  );
}

/// Scales a colour by [k] in 0..1 (clamped), used to apply intensity.
RGBColor scaleRgb(RGBColor c, double k) {
  final f = k.clamp(0.0, 1.0);
  return RGBColor(
    (c.red * f).round().clamp(0, 255),
    (c.green * f).round().clamp(0, 255),
    (c.blue * f).round().clamp(0, 255),
  );
}

/// A named colour ramp used as creative input by the custom effect renderers.
///
/// A palette is **not** protocol data: it never maps to a wire command on its
/// own. Renderers sample a palette to produce colours, and only the resulting
/// colour can be written for a single-colour device.
@immutable
class EffectPalette extends Equatable {
  /// Stable identifier (lowercase slug), safe to persist.
  final String id;

  /// Human-readable name shown in the UI.
  final String name;

  /// Ordered ramp. Sampling wraps, so the first and last colours should sit
  /// next to each other visually.
  final List<RGBColor> colors;

  const EffectPalette({
    required this.id,
    required this.name,
    required this.colors,
  });

  /// Samples the ramp at [t]. Values wrap, so callers may pass any increasing
  /// parameter (time, position) without clamping.
  RGBColor sample(double t) {
    if (colors.isEmpty) return const RGBColor(255, 255, 255);
    if (colors.length == 1) return colors.first;
    final wrapped = t - t.floorToDouble();
    final scaled = wrapped * colors.length;
    final index = scaled.floor();
    final fraction = scaled - index;
    final from = colors[index % colors.length];
    final to = colors[(index + 1) % colors.length];
    return lerpRgb(from, to, fraction);
  }

  @override
  List<Object?> get props => [id, name, colors];
}

/// The built-in palette rack. Deliberately small and curated so the studio
/// stays restrained rather than offering an unbounded colour picker.
const List<EffectPalette> kEffectPalettes = <EffectPalette>[
  EffectPalette(
    id: 'aurora',
    name: 'Aurora',
    colors: [
      RGBColor(0x14, 0xF1, 0xD9),
      RGBColor(0x00, 0xE0, 0xA4),
      RGBColor(0x4D, 0x7C, 0xFE),
      RGBColor(0x8E, 0x6C, 0xFF),
      RGBColor(0x14, 0xF1, 0xD9),
    ],
  ),
  EffectPalette(
    id: 'ember',
    name: 'Ember',
    colors: [
      RGBColor(0x2A, 0x0A, 0x00),
      RGBColor(0xB2, 0x20, 0x0A),
      RGBColor(0xFF, 0x7A, 0x18),
      RGBColor(0xFF, 0xC2, 0x4B),
      RGBColor(0x2A, 0x0A, 0x00),
    ],
  ),
  EffectPalette(
    id: 'ocean',
    name: 'Ocean',
    colors: [
      RGBColor(0x02, 0x1B, 0x33),
      RGBColor(0x0A, 0x5C, 0x8A),
      RGBColor(0x12, 0xC2, 0xE9),
      RGBColor(0x6F, 0xFF, 0xE9),
      RGBColor(0x02, 0x1B, 0x33),
    ],
  ),
  EffectPalette(
    id: 'neon',
    name: 'Neon',
    colors: [
      RGBColor(0xFF, 0x2D, 0x95),
      RGBColor(0x8E, 0x6C, 0xFF),
      RGBColor(0x00, 0xE5, 0xFF),
      RGBColor(0xFF, 0x2D, 0x95),
    ],
  ),
  EffectPalette(
    id: 'polar',
    name: 'Polar',
    colors: [
      RGBColor(0x08, 0x1B, 0x33),
      RGBColor(0x3F, 0xA9, 0xF5),
      RGBColor(0xAE, 0xE9, 0xFF),
      RGBColor(0xFF, 0xFF, 0xFF),
      RGBColor(0x08, 0x1B, 0x33),
    ],
  ),
  EffectPalette(
    id: 'sunset',
    name: 'Sunset',
    colors: [
      RGBColor(0x2B, 0x0A, 0x2A),
      RGBColor(0xC2, 0x18, 0x5B),
      RGBColor(0xFF, 0x7A, 0x45),
      RGBColor(0xFF, 0xD1, 0x66),
    ],
  ),
];

/// Convenience: the palette with [id], or `null` when unknown.
EffectPalette? effectPaletteById(String? id) {
  if (id == null) return null;
  for (final palette in kEffectPalettes) {
    if (palette.id == id) return palette;
  }
  return null;
}

/// Convenience: the palette with [id], falling back to the first built-in
/// palette only when [id] is missing/unknown. UI code uses this so a stale
/// persisted id never renders an empty preview.
EffectPalette effectPaletteOrDefault(String? id) =>
    effectPaletteById(id) ?? kEffectPalettes.first;
