// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:starlight/core/utils/app_logger.dart';
import 'package:starlight/data/datasources/theme_preferences.dart';
import 'package:starlight/presentation/theme/app_theme.dart';

import 'theme_state.dart';

/// Owns the application's appearance (built-in theme + optional custom accent).
///
/// The initial state is restored *synchronously* from [ThemePreferences] so the
/// first frame already renders the persisted theme — no flash of the default
/// palette on startup. Changes are emitted immediately (so the UI restyles at
/// once) and persisted in the background.
class ThemeCubit extends Cubit<ThemeState> {
  final ThemePreferences _preferences;

  ThemeCubit(this._preferences) : super(_restore(_preferences));

  static ThemeState _restore(ThemePreferences prefs) {
    final theme = appThemeById(prefs.readThemeId()) ?? kDefaultAppTheme;
    final argb = prefs.readAccent();
    if (argb == null) return ThemeState(theme: theme);
    return ThemeState(theme: theme, customAccent: Color(argb));
  }

  /// Applies a built-in theme by [themeId].
  ///
  /// Selecting a built-in theme resets any custom accent: each theme is a
  /// complete, hand-tuned palette, and this keeps the outcome obvious. An
  /// unknown id is ignored.
  void selectTheme(String themeId) {
    final theme = appThemeById(themeId);
    if (theme == null) {
      AppLog.warn('ThemeCubit: ignoring unknown theme id "$themeId"');
      return;
    }
    if (theme.id == state.theme.id && !state.hasCustomAccent) return;
    emit(ThemeState(theme: theme));
    _persist(() async {
      await _preferences.writeThemeId(theme.id);
      await _preferences.removeAccent();
    });
  }

  /// Applies a custom accent colour on top of the active built-in theme.
  void setCustomAccent(Color color) {
    if (state.customAccent == color) return;
    emit(state.copyWith(customAccent: color));
    _persist(() => _preferences.writeAccent(color.toARGB32()));
  }

  /// Clears the custom accent, returning to the active theme's own accent.
  void clearCustomAccent() {
    if (!state.hasCustomAccent) return;
    emit(ThemeState(theme: state.theme));
    _persist(_preferences.removeAccent);
  }

  /// Restores the default theme (Graphite + Purple) and clears the accent.
  void resetToDefault() {
    if (state.theme.id == kDefaultThemeId && !state.hasCustomAccent) return;
    emit(const ThemeState(theme: kDefaultAppTheme));
    _persist(_preferences.clear);
  }

  void _persist(Future<void> Function() action) {
    unawaited(
      action().catchError((Object e) {
        AppLog.warn('ThemeCubit: failed to persist theme preference: $e');
      }),
    );
  }
}
