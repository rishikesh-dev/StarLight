// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';

/// Semantic design tokens for the StarLight application.
///
/// Every built-in theme is expressed as one [AppTokens] palette. Widgets read
/// the *active* palette through [AppTokensContext.tokens] (or
/// `Theme.of(context).extension<AppTokens>()`) instead of hardcoding colors, so
/// switching themes restyles the whole app without touching widget code.
///
/// Tokens are intentionally semantic rather than literal: `success` stays green
/// in every theme (with a light-appropriate shade for the light theme) because
/// it communicates connection state, while `surface`, `border` and `primary`
/// carry the theme's identity.
@immutable
class AppTokens extends ThemeExtension<AppTokens> {
  /// Whether the surrounding theme is dark or light. Drives default text
  /// rendering and the tone of derived shadows.
  final Brightness brightness;

  /// App background (scaffold) colour.
  final Color background;

  /// Card / panel surface.
  final Color surface;

  /// Raised surface used by sheets, dialogs and nested panels.
  final Color surfaceElevated;

  /// Highest surface elevation (menus, snackbars, tonal fills).
  final Color surfaceHigh;

  /// Primary text and icon colour.
  final Color onSurface;

  /// Secondary / muted text and icons.
  final Color onSurfaceVariant;

  /// Hairline borders and dividers.
  final Color border;

  /// Brand / accent colour used for primary controls and selected states.
  final Color primary;

  /// A darker companion to [primary] (secondary elements, pressed states).
  final Color primaryDim;

  /// Foreground drawn on top of [primary] (button labels, filled icons).
  final Color onPrimary;

  /// Semantic: connected / on / success.
  final Color success;

  /// Semantic: caution / pending.
  final Color warning;

  /// Semantic: failure / destructive.
  final Color error;

  /// Disabled control fill and inactive track.
  final Color disabled;

  const AppTokens({
    required this.brightness,
    required this.background,
    required this.surface,
    required this.surfaceElevated,
    required this.surfaceHigh,
    required this.onSurface,
    required this.onSurfaceVariant,
    required this.border,
    required this.primary,
    required this.primaryDim,
    required this.onPrimary,
    required this.success,
    required this.warning,
    required this.error,
    required this.disabled,
  });

  /// The default StarLight theme: graphite surfaces with the #8E6CFF accent.
  static const AppTokens graphite = AppTokens(
    brightness: Brightness.dark,
    background: Color(0xFF0E0E12),
    surface: Color(0xFF1A1A1F),
    surfaceElevated: Color(0xFF25252C),
    surfaceHigh: Color(0xFF2F2F38),
    onSurface: Color(0xFFE8E8F0),
    onSurfaceVariant: Color(0xFF9A9AA8),
    border: Color(0xFF2A2A32),
    primary: Color(0xFF8E6CFF),
    primaryDim: Color(0xFF6B4FD8),
    onPrimary: Color(0xFFFFFFFF),
    success: Color(0xFF4CAF50),
    warning: Color(0xFFFFA726),
    error: Color(0xFFE53935),
    disabled: Color(0xFF4A4A55),
  );

  /// Cool, blue-tinted dark theme.
  static const AppTokens midnight = AppTokens(
    brightness: Brightness.dark,
    background: Color(0xFF0B1119),
    surface: Color(0xFF141C27),
    surfaceElevated: Color(0xFF1D2836),
    surfaceHigh: Color(0xFF283646),
    onSurface: Color(0xFFE6ECF5),
    onSurfaceVariant: Color(0xFF93A3B8),
    border: Color(0xFF26323F),
    primary: Color(0xFF5B8DEF),
    primaryDim: Color(0xFF3F6FD1),
    onPrimary: Color(0xFFFFFFFF),
    success: Color(0xFF4CC38A),
    warning: Color(0xFFFFB74D),
    error: Color(0xFFEF5350),
    disabled: Color(0xFF3A4757),
  );

  /// Accessible forest-green dark theme.
  static const AppTokens forest = AppTokens(
    brightness: Brightness.dark,
    background: Color(0xFF0B1410),
    surface: Color(0xFF13201A),
    surfaceElevated: Color(0xFF1C2C23),
    surfaceHigh: Color(0xFF273A2F),
    onSurface: Color(0xFFE6F1E9),
    onSurfaceVariant: Color(0xFF97B0A2),
    border: Color(0xFF27392E),
    primary: Color(0xFF4CAF7D),
    primaryDim: Color(0xFF37855D),
    onPrimary: Color(0xFF07130D),
    success: Color(0xFF66BB6A),
    warning: Color(0xFFFFB74D),
    error: Color(0xFFE5533D),
    disabled: Color(0xFF3C4A41),
  );

  /// Warm amber dark theme.
  static const AppTokens amber = AppTokens(
    brightness: Brightness.dark,
    background: Color(0xFF14100A),
    surface: Color(0xFF201A11),
    surfaceElevated: Color(0xFF2B2317),
    surfaceHigh: Color(0xFF382E1F),
    onSurface: Color(0xFFF3E9D8),
    onSurfaceVariant: Color(0xFFB3A489),
    border: Color(0xFF3A2F1F),
    primary: Color(0xFFFFB74D),
    primaryDim: Color(0xFFD98B36),
    onPrimary: Color(0xFF201400),
    success: Color(0xFF66BB6A),
    warning: Color(0xFFFFCC80),
    error: Color(0xFFE5533D),
    disabled: Color(0xFF4A3E2C),
  );

  /// Light theme with dark, readable text and accessible accents.
  static const AppTokens light = AppTokens(
    brightness: Brightness.light,
    background: Color(0xFFF5F5F9),
    surface: Color(0xFFFFFFFF),
    surfaceElevated: Color(0xFFEFEFF4),
    surfaceHigh: Color(0xFFE4E4EC),
    onSurface: Color(0xFF1A1A22),
    onSurfaceVariant: Color(0xFF5C5C6B),
    border: Color(0xFFD8D8E2),
    primary: Color(0xFF6C4BD8),
    primaryDim: Color(0xFF5638BE),
    onPrimary: Color(0xFFFFFFFF),
    success: Color(0xFF2E7D32),
    warning: Color(0xFFB26A00),
    error: Color(0xFFC62828),
    disabled: Color(0xFFB9B9C6),
  );

  @override
  AppTokens copyWith({
    Brightness? brightness,
    Color? background,
    Color? surface,
    Color? surfaceElevated,
    Color? surfaceHigh,
    Color? onSurface,
    Color? onSurfaceVariant,
    Color? border,
    Color? primary,
    Color? primaryDim,
    Color? onPrimary,
    Color? success,
    Color? warning,
    Color? error,
    Color? disabled,
  }) {
    return AppTokens(
      brightness: brightness ?? this.brightness,
      background: background ?? this.background,
      surface: surface ?? this.surface,
      surfaceElevated: surfaceElevated ?? this.surfaceElevated,
      surfaceHigh: surfaceHigh ?? this.surfaceHigh,
      onSurface: onSurface ?? this.onSurface,
      onSurfaceVariant: onSurfaceVariant ?? this.onSurfaceVariant,
      border: border ?? this.border,
      primary: primary ?? this.primary,
      primaryDim: primaryDim ?? this.primaryDim,
      onPrimary: onPrimary ?? this.onPrimary,
      success: success ?? this.success,
      warning: warning ?? this.warning,
      error: error ?? this.error,
      disabled: disabled ?? this.disabled,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is AppTokens &&
        other.brightness == brightness &&
        other.background == background &&
        other.surface == surface &&
        other.surfaceElevated == surfaceElevated &&
        other.surfaceHigh == surfaceHigh &&
        other.onSurface == onSurface &&
        other.onSurfaceVariant == onSurfaceVariant &&
        other.border == border &&
        other.primary == primary &&
        other.primaryDim == primaryDim &&
        other.onPrimary == onPrimary &&
        other.success == success &&
        other.warning == warning &&
        other.error == error &&
        other.disabled == disabled;
  }

  @override
  int get hashCode => Object.hash(
    brightness,
    background,
    surface,
    surfaceElevated,
    surfaceHigh,
    onSurface,
    onSurfaceVariant,
    border,
    primary,
    primaryDim,
    onPrimary,
    success,
    warning,
    error,
    disabled,
  );

  @override
  AppTokens lerp(covariant AppTokens? other, double t) {
    if (other == null) return this;
    return AppTokens(
      brightness: t < 0.5 ? brightness : other.brightness,
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceElevated: Color.lerp(surfaceElevated, other.surfaceElevated, t)!,
      surfaceHigh: Color.lerp(surfaceHigh, other.surfaceHigh, t)!,
      onSurface: Color.lerp(onSurface, other.onSurface, t)!,
      onSurfaceVariant: Color.lerp(
        onSurfaceVariant,
        other.onSurfaceVariant,
        t,
      )!,
      border: Color.lerp(border, other.border, t)!,
      primary: Color.lerp(primary, other.primary, t)!,
      primaryDim: Color.lerp(primaryDim, other.primaryDim, t)!,
      onPrimary: Color.lerp(onPrimary, other.onPrimary, t)!,
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      error: Color.lerp(error, other.error, t)!,
      disabled: Color.lerp(disabled, other.disabled, t)!,
    );
  }
}

/// Reads the active [AppTokens] from the surrounding [Theme].
///
/// Falls back to the graphite palette when no StarLight theme is installed
/// (e.g. a widget pumped standalone in a test), so widgets never crash on a
/// missing extension.
extension AppTokensContext on BuildContext {
  AppTokens get tokens =>
      Theme.of(this).extension<AppTokens>() ?? AppTokens.graphite;
}
