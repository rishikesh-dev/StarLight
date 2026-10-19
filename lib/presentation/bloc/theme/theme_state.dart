// SPDX-License-Identifier: Apache-2.0

import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';

import 'package:starlight/presentation/theme/app_theme.dart';

/// The active appearance: a built-in [theme] plus an optional [customAccent].
///
/// When [customAccent] is `null` the theme's own accent is used. Selecting a
/// built-in theme clears the custom accent (see `ThemeCubit.selectTheme`) so the
/// result is always predictable.
@immutable
class ThemeState extends Equatable {
  final AppThemeOption theme;
  final Color? customAccent;

  const ThemeState({required this.theme, this.customAccent});

  /// The accent actually in effect.
  Color get accent => customAccent ?? theme.tokens.primary;

  bool get hasCustomAccent => customAccent != null;

  ThemeState copyWith({AppThemeOption? theme, Color? customAccent}) {
    return ThemeState(
      theme: theme ?? this.theme,
      customAccent: customAccent ?? this.customAccent,
    );
  }

  @override
  List<Object?> get props => [theme.id, customAccent];
}
