import 'package:flutter/material.dart';

/// Shared helpers for the app's text styles.
extension TextStyleX on TextStyle {
  /// Returns a copy of this style with [color] applied.
  TextStyle copyColor(Color color) => copyWith(color: color);
}
