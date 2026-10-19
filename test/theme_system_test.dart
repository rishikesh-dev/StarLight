import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starlight/presentation/theme/app_theme.dart';

/// Relative luminance (WCAG) of a Flutter [Color].
double _luminance(Color color) {
  double channel(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * channel(color.r) +
      0.7152 * channel(color.g) +
      0.0722 * channel(color.b);
}

double _contrast(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  final hi = math.max(la, lb);
  final lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  group('built-in themes', () {
    test('there are five distinct themes with unique ids and names', () {
      expect(kAppThemes.length, 5);
      expect(kAppThemes.map((t) => t.id).toSet(), {
        'graphite',
        'midnight',
        'forest',
        'amber',
        'light',
      });
      expect(kAppThemes.map((t) => t.name).toSet().length, 5);
    });

    test('each theme defines a complete, distinct palette', () {
      for (final option in kAppThemes) {
        final t = option.tokens;
        // Identity colours must be genuinely different; a theme is not just an
        // accent swap.
        expect(t.primary, isNot(t.background), reason: option.id);
        expect(t.surface, isNot(t.background), reason: option.id);
        expect(t.surfaceElevated, isNot(t.surface), reason: option.id);
        expect(t.onSurface, isNot(t.surface), reason: option.id);
        expect(t.border, isNot(t.surface), reason: option.id);
      }
    });

    test('every theme keeps text and accents readable', () {
      for (final option in kAppThemes) {
        final t = option.tokens;
        expect(
          _contrast(t.onSurface, t.background),
          greaterThan(4.5),
          reason: '${option.id} onSurface/background',
        );
        expect(
          _contrast(t.onSurfaceVariant, t.background),
          greaterThan(3.0),
          reason: '${option.id} onSurfaceVariant/background',
        );
        expect(
          _contrast(t.primary, t.surface),
          greaterThan(3.0),
          reason: '${option.id} primary/surface',
        );
      }
    });

    test('only the light theme is light', () {
      expect(kLightTheme.tokens.brightness, Brightness.light);
      for (final option in kAppThemes.where((t) => t.id != 'light')) {
        expect(option.tokens.brightness, Brightness.dark, reason: option.id);
      }
    });
  });

  group('appThemeById', () {
    test('resolves known ids', () {
      expect(appThemeById('graphite'), kGraphiteTheme);
      expect(appThemeById('midnight'), kMidnightTheme);
      expect(appThemeById('forest'), kForestTheme);
      expect(appThemeById('amber'), kWarmAmberTheme);
      expect(appThemeById('light'), kLightTheme);
    });

    test('returns null for missing/unknown ids so callers can fall back', () {
      expect(appThemeById(null), isNull);
      expect(appThemeById(''), isNull);
      expect(appThemeById('does-not-exist'), isNull);
      expect(kDefaultAppTheme, kGraphiteTheme);
      expect(kDefaultThemeId, 'graphite');
    });
  });

  group('buildAppTheme', () {
    test('attaches the palette and maps it onto the ColorScheme', () {
      for (final option in kAppThemes) {
        final theme = buildAppTheme(option: option);
        final tokens = theme.extension<AppTokens>();
        expect(tokens, isNotNull, reason: option.id);
        expect(tokens, option.tokens, reason: option.id);
        expect(theme.colorScheme.primary, option.tokens.primary);
        expect(theme.colorScheme.onPrimary, option.tokens.onPrimary);
        expect(theme.colorScheme.surface, option.tokens.surface);
        expect(theme.scaffoldBackgroundColor, option.tokens.background);
        expect(theme.brightness, option.tokens.brightness);
      }
    });

    test('defaults to the Graphite theme', () {
      final theme = buildAppTheme();
      expect(theme.extension<AppTokens>(), AppTokens.graphite);
      expect(theme.colorScheme.primary, AppTokens.graphite.primary);
    });

    test('a custom accent overrides only the accent', () {
      const accent = Color(0xFF00C2A8);
      final theme = buildAppTheme(option: kLightTheme, accentOverride: accent);
      final tokens = theme.extension<AppTokens>()!;
      expect(tokens.primary, accent);
      expect(theme.colorScheme.primary, accent);
      // The rest of the palette is untouched.
      expect(tokens.surface, kLightTheme.tokens.surface);
      expect(tokens.background, kLightTheme.tokens.background);
      expect(tokens.onSurface, kLightTheme.tokens.onSurface);
      expect(tokens.success, kLightTheme.tokens.success);
    });

    test('onColorFor picks a readable foreground', () {
      expect(onColorFor(const Color(0xFF000000)), Colors.white);
      expect(onColorFor(const Color(0xFFFFFFFF)), isNot(Colors.white));
    });
  });

  testWidgets('the palette is reachable from a widget context', (tester) async {
    late AppTokens tokens;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(option: kForestTheme),
        home: Builder(
          builder: (context) {
            tokens = context.tokens;
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    expect(tokens, kForestTheme.tokens);
  });
}
