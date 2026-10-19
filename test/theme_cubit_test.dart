import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:starlight/data/datasources/theme_preferences.dart';
import 'package:starlight/presentation/bloc/theme/theme_cubit.dart';
import 'package:starlight/presentation/theme/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences prefs;

  Future<ThemeCubit> cubitWith(Map<String, Object> values) async {
    SharedPreferences.setMockInitialValues(values);
    prefs = await SharedPreferences.getInstance();
    final cubit = ThemeCubit(ThemePreferences(prefs));
    addTearDown(cubit.close);
    return cubit;
  }

  group('restore', () {
    test('defaults to Graphite with no custom accent', () async {
      final cubit = await cubitWith({});
      expect(cubit.state.theme.id, 'graphite');
      expect(cubit.state.hasCustomAccent, isFalse);
      expect(cubit.state.accent, AppTokens.graphite.primary);
    });

    test('restores a persisted theme id', () async {
      final cubit = await cubitWith({ThemePreferences.themeIdKey: 'forest'});
      expect(cubit.state.theme.id, 'forest');
    });

    test('restores a persisted custom accent', () async {
      final cubit = await cubitWith({
        ThemePreferences.themeIdKey: 'midnight',
        ThemePreferences.accentKey: 0xFF123456,
      });
      expect(cubit.state.theme.id, 'midnight');
      expect(cubit.state.customAccent, const Color(0xFF123456));
      expect(cubit.state.accent, const Color(0xFF123456));
    });

    test('an unknown theme id falls back to Graphite', () async {
      final cubit = await cubitWith({ThemePreferences.themeIdKey: 'nope'});
      expect(cubit.state.theme.id, 'graphite');
    });

    test('a malformed theme id falls back to Graphite', () async {
      final cubit = await cubitWith({ThemePreferences.themeIdKey: 42});
      expect(cubit.state.theme.id, 'graphite');
    });

    test('a malformed accent is ignored', () async {
      final cubit = await cubitWith({ThemePreferences.accentKey: 'not-an-int'});
      expect(cubit.state.hasCustomAccent, isFalse);
    });
  });

  group('mutations', () {
    test(
      'selectTheme applies immediately, persists and clears accent',
      () async {
        final cubit = await cubitWith({});
        cubit.setCustomAccent(const Color(0xFF00FF00));
        expect(cubit.state.hasCustomAccent, isTrue);

        cubit.selectTheme('forest');
        // Immediate: no await needed for the emitted state.
        expect(cubit.state.theme.id, 'forest');
        expect(cubit.state.hasCustomAccent, isFalse);

        await pumpEventQueue();
        expect(prefs.getString(ThemePreferences.themeIdKey), 'forest');
        expect(prefs.getInt(ThemePreferences.accentKey), isNull);
      },
    );

    test('setCustomAccent persists the ARGB value', () async {
      final cubit = await cubitWith({});
      cubit.setCustomAccent(const Color(0xFF26A69A));
      expect(cubit.state.customAccent, const Color(0xFF26A69A));
      await pumpEventQueue();
      expect(prefs.getInt(ThemePreferences.accentKey), 0xFF26A69A);
    });

    test('clearCustomAccent keeps the theme and removes the accent', () async {
      final cubit = await cubitWith({});
      cubit.selectTheme('amber');
      cubit.setCustomAccent(const Color(0xFF112233));
      cubit.clearCustomAccent();
      expect(cubit.state.theme.id, 'amber');
      expect(cubit.state.hasCustomAccent, isFalse);
      await pumpEventQueue();
      expect(prefs.getInt(ThemePreferences.accentKey), isNull);
    });

    test('resetToDefault returns to Graphite and clears storage', () async {
      final cubit = await cubitWith({
        ThemePreferences.themeIdKey: 'light',
        ThemePreferences.accentKey: 0xFFABCDEF,
      });
      expect(cubit.state.theme.id, 'light');

      cubit.resetToDefault();
      expect(cubit.state.theme.id, 'graphite');
      expect(cubit.state.hasCustomAccent, isFalse);

      await pumpEventQueue();
      expect(prefs.getString(ThemePreferences.themeIdKey), isNull);
      expect(prefs.getInt(ThemePreferences.accentKey), isNull);
    });

    test('an unknown theme id is ignored', () async {
      final cubit = await cubitWith({});
      cubit.selectTheme('not-a-theme');
      expect(cubit.state.theme.id, 'graphite');
    });
  });
}
