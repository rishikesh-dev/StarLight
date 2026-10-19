// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';

import 'package:starlight/presentation/theme/app_theme.dart';

/// Home header: the StarLight wordmark, a concise time-aware greeting, and the
/// Settings action. No search, notifications, or decorative icons.
class HomeHeader extends StatelessWidget {
  final VoidCallback? onOpenSettings;

  const HomeHeader({super.key, this.onOpenSettings});

  /// Time-aware greeting, derived from [now].
  static String greetingFor(DateTime now) {
    final hour = now.hour;
    if (hour < 12) return 'Good morning';
    if (hour < 18) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.tokens;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'StarLight',
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                    color: tokens.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  greetingFor(DateTime.now()),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: tokens.onSurfaceVariant,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
          if (onOpenSettings != null)
            IconButton(
              onPressed: onOpenSettings,
              icon: const Icon(Icons.settings_outlined, size: 24),
              tooltip: 'Settings',
              style: IconButton.styleFrom(
                backgroundColor: tokens.surfaceHigh.withValues(alpha: 0.5),
                foregroundColor: tokens.onSurface,
              ),
            ),
        ],
      ),
    );
  }
}
