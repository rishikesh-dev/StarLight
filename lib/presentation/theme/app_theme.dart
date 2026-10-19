// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';

import 'app_tokens.dart';

export 'app_tokens.dart';

/// Backwards-compatible aliases for the default (Graphite + Purple) palette.
///
/// New code should read the *active* palette through [AppTokensContext.tokens]
/// so it follows the selected theme. These constants are retained for the
/// handful of screens that are not reachable yet and still render with the
/// fixed default palette.
class AppColors {
  AppColors._();

  static const Color primary = Color(0xFF8E6CFF);
  static const Color primaryDim = Color(0xFF6B4FD8);
  static const Color background = Color(0xFF0E0E12);
  static const Color surface = Color(0xFF1A1A1F);
  static const Color surfaceElevated = Color(0xFF25252C);
  static const Color surfaceHigh = Color(0xFF2F2F38);
  static const Color onSurface = Color(0xFFE8E8F0);
  static const Color onSurfaceVariant = Color(0xFF9A9AA8);
  static const Color border = Color(0xFF2A2A32);
  static const Color success = Color(0xFF4CAF50);
  static const Color warning = Color(0xFFFFA726);
  static const Color error = Color(0xFFE53935);
  static const Color disabled = Color(0xFF4A4A55);

  static Color withAlpha(Color color, double a) => color.withValues(alpha: a);
}

/// Restrained glow used sparingly around active controls.
List<BoxShadow> glowShadow({
  Color color = AppColors.primary,
  double radius = 12,
}) {
  return [
    BoxShadow(
      color: color.withValues(alpha: 0.45),
      blurRadius: radius,
      offset: const Offset(0, 0),
    ),
  ];
}

/// A selectable built-in theme: a stable [id] (persisted), a display [name] and
/// the [tokens] palette that defines every colour in the theme.
@immutable
class AppThemeOption {
  final String id;
  final String name;
  final AppTokens tokens;

  const AppThemeOption({
    required this.id,
    required this.name,
    required this.tokens,
  });

  bool get isDark => tokens.brightness == Brightness.dark;

  /// Short description shown next to the theme name in Settings.
  String get description => isDark ? 'Dark surfaces' : 'Light surfaces';
}

/// Graphite + Purple — the StarLight default.
const AppThemeOption kGraphiteTheme = AppThemeOption(
  id: 'graphite',
  name: 'Graphite + Purple',
  tokens: AppTokens.graphite,
);

/// Midnight Blue — cool blue accent.
const AppThemeOption kMidnightTheme = AppThemeOption(
  id: 'midnight',
  name: 'Midnight Blue',
  tokens: AppTokens.midnight,
);

/// Forest — accessible green accent.
const AppThemeOption kForestTheme = AppThemeOption(
  id: 'forest',
  name: 'Forest',
  tokens: AppTokens.forest,
);

/// Warm Amber — warm amber accent.
const AppThemeOption kWarmAmberTheme = AppThemeOption(
  id: 'amber',
  name: 'Warm Amber',
  tokens: AppTokens.amber,
);

/// Light — light surfaces with dark, readable text.
const AppThemeOption kLightTheme = AppThemeOption(
  id: 'light',
  name: 'Light',
  tokens: AppTokens.light,
);

/// All built-in themes, in display order.
const List<AppThemeOption> kAppThemes = <AppThemeOption>[
  kGraphiteTheme,
  kMidnightTheme,
  kForestTheme,
  kWarmAmberTheme,
  kLightTheme,
];

/// The theme id used when nothing valid is stored.
const String kDefaultThemeId = 'graphite';

/// The default theme option.
const AppThemeOption kDefaultAppTheme = kGraphiteTheme;

/// Resolves a persisted theme [id] to a built-in option, or `null` when the id
/// is missing/unknown (callers fall back to [kDefaultAppTheme]).
AppThemeOption? appThemeById(String? id) {
  if (id == null) return null;
  for (final option in kAppThemes) {
    if (option.id == id) return option;
  }
  return null;
}

/// A curated set of accent colours offered in Settings. Every built-in theme's
/// accent is included so the active accent is always representable.
const List<Color> kAccentPresets = <Color>[
  Color(0xFF8E6CFF),
  Color(0xFF5B8DEF),
  Color(0xFF26A69A),
  Color(0xFF4CAF7D),
  Color(0xFF4CAF50),
  Color(0xFFFFB74D),
  Color(0xFFFF7043),
  Color(0xFFEC407A),
];

/// Picks a readable foreground for [background] (used for custom accents,
/// where no hand-tuned `onPrimary` is available).
Color onColorFor(Color background) {
  return ThemeData.estimateBrightnessForColor(background) == Brightness.dark
      ? Colors.white
      : const Color(0xFF15161A);
}

/// Builds the Material [ThemeData] for [option], optionally overriding the
/// accent colour ([accentOverride]) for the custom-accent feature.
///
/// The resolved palette is attached as an [AppTokens] theme extension so the
/// whole app can read it via [AppTokensContext.tokens]. All component themes
/// are derived from the same palette, keeping surfaces, borders, controls and
/// semantic colours consistent.
ThemeData buildAppTheme({AppThemeOption? option, Color? accentOverride}) {
  final base = option ?? kDefaultAppTheme;
  final custom = accentOverride != null;

  final primary = accentOverride ?? base.tokens.primary;
  final onPrimary = custom ? onColorFor(primary) : base.tokens.onPrimary;
  final primaryDim = custom
      ? Color.lerp(primary, Colors.black, 0.24)!
      : base.tokens.primaryDim;

  final tokens = base.tokens.copyWith(
    primary: primary,
    primaryDim: primaryDim,
    onPrimary: onPrimary,
  );

  final scheme = ColorScheme(
    brightness: tokens.brightness,
    primary: tokens.primary,
    onPrimary: tokens.onPrimary,
    primaryContainer: tokens.primaryDim,
    onPrimaryContainer: tokens.onPrimary,
    secondary: tokens.primaryDim,
    onSecondary: tokens.onPrimary,
    error: tokens.error,
    onError: Colors.white,
    surface: tokens.surface,
    onSurface: tokens.onSurface,
    onSurfaceVariant: tokens.onSurfaceVariant,
    outline: tokens.border,
    outlineVariant: tokens.border,
    surfaceContainerLowest: tokens.background,
    surfaceContainerLow: tokens.surface,
    surfaceContainer: tokens.surfaceElevated,
    surfaceContainerHigh: tokens.surfaceHigh,
    surfaceContainerHighest: tokens.surfaceHigh,
  );

  final baseText = ThemeData(
    brightness: tokens.brightness,
    useMaterial3: true,
  ).textTheme;

  final buttonShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(12),
  );

  return ThemeData(
    useMaterial3: true,
    brightness: tokens.brightness,
    colorScheme: scheme,
    extensions: <ThemeExtension<dynamic>>[tokens],
    scaffoldBackgroundColor: tokens.background,
    canvasColor: tokens.background,
    cardColor: tokens.surface,
    dividerColor: tokens.border,
    disabledColor: tokens.disabled,
    splashColor: tokens.primary.withValues(alpha: 0.08),
    highlightColor: tokens.primary.withValues(alpha: 0.05),
    textTheme: baseText.apply(
      bodyColor: tokens.onSurface,
      displayColor: tokens.onSurface,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: tokens.background,
      foregroundColor: tokens.onSurface,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: tokens.surfaceElevated,
      surfaceTintColor: Colors.transparent,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: tokens.surfaceElevated,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: TextStyle(
        color: tokens.onSurface,
        fontSize: 20,
        fontWeight: FontWeight.w600,
      ),
      contentTextStyle: TextStyle(color: tokens.onSurfaceVariant, fontSize: 14),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: tokens.surfaceHigh,
      contentTextStyle: TextStyle(color: tokens.onSurface, fontSize: 14),
      actionTextColor: tokens.primary,
      behavior: SnackBarBehavior.floating,
    ),
    cardTheme: CardThemeData(
      color: tokens.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: tokens.border),
      ),
    ),
    dividerTheme: DividerThemeData(
      color: tokens.border,
      thickness: 1,
      space: 1,
    ),
    iconTheme: IconThemeData(color: tokens.onSurfaceVariant, size: 22),
    listTileTheme: ListTileThemeData(
      iconColor: tokens.onSurfaceVariant,
      textColor: tokens.onSurface,
    ),
    sliderTheme: SliderThemeData(
      thumbColor: tokens.primary,
      activeTrackColor: tokens.primary,
      inactiveTrackColor: tokens.disabled,
      overlayColor: tokens.primary.withValues(alpha: 0.2),
      valueIndicatorColor: tokens.primary,
      valueIndicatorTextStyle: TextStyle(color: tokens.onPrimary),
      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
      overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) return tokens.disabled;
        if (states.contains(WidgetState.selected)) return tokens.primary;
        return tokens.onSurfaceVariant;
      }),
      trackColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return tokens.primary.withValues(alpha: 0.35);
        }
        return tokens.disabled.withValues(alpha: 0.4);
      }),
      trackOutlineColor: const WidgetStatePropertyAll<Color>(
        Colors.transparent,
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: tokens.surfaceElevated,
      selectedColor: tokens.primary.withValues(alpha: 0.20),
      disabledColor: tokens.surfaceElevated,
      side: BorderSide(color: tokens.border),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      labelStyle: TextStyle(
        color: tokens.onSurface,
        fontWeight: FontWeight.w500,
      ),
      secondaryLabelStyle: TextStyle(color: tokens.primary),
      checkmarkColor: tokens.primary,
      showCheckmark: true,
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: tokens.primary,
      foregroundColor: tokens.onPrimary,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: tokens.primary,
        foregroundColor: tokens.onPrimary,
        disabledBackgroundColor: tokens.disabled.withValues(alpha: 0.4),
        disabledForegroundColor: tokens.onSurfaceVariant,
        minimumSize: const Size(0, 48),
        shape: buttonShape,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: tokens.primary,
        foregroundColor: tokens.onPrimary,
        disabledBackgroundColor: tokens.disabled.withValues(alpha: 0.4),
        disabledForegroundColor: tokens.onSurfaceVariant,
        minimumSize: const Size(0, 48),
        shape: buttonShape,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: tokens.primary,
        side: BorderSide(color: tokens.border),
        minimumSize: const Size(0, 48),
        shape: buttonShape,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: tokens.primary),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: tokens.surfaceElevated,
      hintStyle: TextStyle(color: tokens.onSurfaceVariant),
      labelStyle: TextStyle(color: tokens.onSurfaceVariant),
      prefixIconColor: tokens.onSurfaceVariant,
      suffixIconColor: tokens.onSurfaceVariant,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: tokens.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: tokens.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: tokens.primary, width: 1.5),
      ),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: tokens.primary,
      linearTrackColor: tokens.surfaceHigh,
      circularTrackColor: tokens.surfaceHigh,
    ),
  );
}
