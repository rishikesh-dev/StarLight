// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';

import 'package:starlight/presentation/theme/app_theme.dart';

/// A tiny, non-interactive swatch that shows the actual colours of a built-in
/// [AppThemeOption]: its background, a surface panel, the accent and the
/// semantic success/warning dots.
///
/// It is deliberately text-free and fixed-size so it can never overflow under
/// large text scales or on narrow screens. Colours are taken from the option's
/// own palette (not the active theme), so every preview is truthful before the
/// theme is applied.
class ThemePreview extends StatelessWidget {
  final AppThemeOption option;
  final double width;
  final double height;

  const ThemePreview({
    super.key,
    required this.option,
    this.width = 54,
    this.height = 40,
  });

  @override
  Widget build(BuildContext context) {
    final t = option.tokens;
    return Semantics(
      label: '${option.name} preview',
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: t.background,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: t.border),
        ),
        padding: const EdgeInsets.all(4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: t.surface,
                        borderRadius: BorderRadius.circular(5),
                        border: Border.all(color: t.border),
                      ),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          height: 5,
                          decoration: BoxDecoration(
                            color: t.primary,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ),
                      const SizedBox(width: 3),
                      _Dot(color: t.success, size: 5),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 3),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _Dot(color: t.primary, size: 7),
                const SizedBox(height: 4),
                _Dot(color: t.warning, size: 7),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  final Color color;
  final double size;

  const _Dot({required this.color, required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}
