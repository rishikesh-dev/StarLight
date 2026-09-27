import 'package:flutter/material.dart';

/// Design system tokens for the StarLight app.
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

List<BoxShadow> glowShadow({Color color = AppColors.primary, double radius = 12}) {
  return [
    BoxShadow(
      color: color.withValues(alpha: 0.45),
      blurRadius: radius,
      offset: const Offset(0, 0),
    ),
  ];
}

ThemeData buildAppTheme() {
  const primary = AppColors.primary;
  return ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: AppColors.background,
    cardColor: AppColors.surface,
    colorScheme: const ColorScheme.dark(
      primary: primary,
      secondary: AppColors.primaryDim,
      surface: AppColors.surface,
      onSurface: AppColors.onSurface,
      error: AppColors.error,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.background,
      foregroundColor: AppColors.onSurface,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: AppColors.surfaceElevated,
      barrierColor: Colors.black54,
    ),
    sliderTheme: SliderThemeData(
      thumbColor: primary,
      activeTrackColor: primary,
      inactiveTrackColor: AppColors.disabled,
      overlayColor: primary.withValues(alpha: 0.2),
      trackShape: const StadiumSliderTrackShape(),
      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
      overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return primary;
        return AppColors.disabled;
      }),
      trackColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return primary.withValues(alpha: 0.4);
        }
        return AppColors.disabled.withValues(alpha: 0.4);
      }),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: primary,
      foregroundColor: Colors.white,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: primary,
        foregroundColor: Colors.white,
        minimumSize: const Size(0, 48),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: primary),
    ),
    iconTheme: const IconThemeData(color: AppColors.onSurfaceVariant, size: 22),
    useMaterial3: true,
  );
}