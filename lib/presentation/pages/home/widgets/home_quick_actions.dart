// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';

import 'package:starlight/presentation/pages/home/widgets/home_section_header.dart';
import 'package:starlight/presentation/theme/app_theme.dart';

/// Quick actions for the destinations that genuinely exist.
///
/// Nothing is listed here unless tapping it reaches a real, implemented
/// surface: pairing a device, the Effects Studio and Settings.
class HomeQuickActions extends StatelessWidget {
  final VoidCallback onAddDevice;
  final VoidCallback? onOpenSettings;

  const HomeQuickActions({
    super.key,
    required this.onAddDevice,
    this.onOpenSettings,
  });

  @override
  Widget build(BuildContext context) {
    final actions = <_QuickAction>[
      _QuickAction(
        icon: Icons.add_circle_outline,
        label: 'Add Device',
        onTap: onAddDevice,
      ),
      _QuickAction(
        icon: Icons.auto_awesome_outlined,
        label: 'Effects Studio',
        onTap: () => Navigator.of(context).pushNamed('/effects'),
      ),
      if (onOpenSettings != null)
        _QuickAction(
          icon: Icons.tune_outlined,
          label: 'Settings',
          onTap: onOpenSettings!,
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        HomeSectionHeader(title: 'Quick actions'),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                for (var i = 0; i < actions.length; i++) ...[
                  if (i > 0) const SizedBox(width: 12),
                  _QuickActionTile(action: actions[i]),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _QuickAction {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _QuickAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });
}

class _QuickActionTile extends StatelessWidget {
  final _QuickAction action;

  const _QuickActionTile({required this.action});

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final theme = Theme.of(context);
    return Material(
      color: tokens.surfaceHigh,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: tokens.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: action.onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(action.icon, color: tokens.primary, size: 20),
              const SizedBox(width: 8),
              Text(
                action.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: tokens.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
