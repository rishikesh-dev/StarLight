// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';

import 'package:starlight/domain/entities/rgb_color.dart';

/// Presentation helpers for converting domain [RGBColor] values into Flutter
/// [Color]s. Centralised so widgets never hand-roll ARGB bit-twiddling (which
/// silently drops the alpha channel and renders transparent swatches).
extension RGBColorX on RGBColor {
  /// Opaque Flutter color for this RGB value.
  Color toColor() => Color(0xFF000000 | toHexInt());

  /// HSV representation, used by the color wheel for hue/saturation maths.
  HSVColor toHsvColor() => HSVColor.fromColor(toColor());

  /// Builds an [RGBColor] from HSV components (hue 0..360, saturation and
  /// value 0..1). Counterpart of [toHsvColor], kept here so the domain entity
  /// never depends on Flutter types.
  static RGBColor fromHsv(double hue, double saturation, double value) {
    final color = HSVColor.fromAHSV(1, hue, saturation, value).toColor();
    return RGBColor(
      (color.r * 255.0).round().clamp(0, 255),
      (color.g * 255.0).round().clamp(0, 255),
      (color.b * 255.0).round().clamp(0, 255),
    );
  }
}
