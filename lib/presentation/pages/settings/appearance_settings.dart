// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:starlight/presentation/bloc/theme/theme_cubit.dart';
import 'package:starlight/presentation/bloc/theme/theme_state.dart';
import 'package:starlight/presentation/theme/app_theme.dart';
import 'package:starlight/presentation/widgets/accent_color_picker_dialog.dart';
import 'package:starlight/presentation/widgets/theme_preview.dart';

/// Appearance preferences: built-in theme selection plus an optional custom
/// accent colour.
///
/// Everything is applied immediately (the active [ThemeCubit] restyles the whole
/// app) and persisted. Selecting a built-in theme resets the accent to that
/// theme's default; a custom accent is layered on top of the current theme and
/// can be cleared with "Use theme accent" or "Reset to default".
class AppearanceSettings extends StatelessWidget {
  const AppearanceSettings({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<ThemeCubit>().state;
    final cubit = context.read<ThemeCubit>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final option in kAppThemes) ...[
          _ThemeTile(
            option: option,
            selected: option.id == state.theme.id,
            onTap: () => cubit.selectTheme(option.id),
          ),
          const SizedBox(height: 10),
        ],
        const SizedBox(height: 6),
        _AccentSection(state: state, cubit: cubit),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: cubit.resetToDefault,
            icon: const Icon(Icons.restart_alt, size: 20),
            label: const Text('Reset to default'),
          ),
        ),
      ],
    );
  }
}

class _ThemeTile extends StatelessWidget {
  final AppThemeOption option;
  final bool selected;
  final VoidCallback onTap;

  const _ThemeTile({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final accent = Theme.of(context).colorScheme.primary;

    return Semantics(
      button: true,
      selected: selected,
      label: '${option.name} theme, ${option.description}',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: tokens.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? accent : tokens.border,
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              ThemePreview(option: option),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      option.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: tokens.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      option.description,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: tokens.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                selected ? Icons.check_circle : Icons.circle_outlined,
                color: selected ? accent : tokens.onSurfaceVariant,
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AccentSection extends StatelessWidget {
  final ThemeState state;
  final ThemeCubit cubit;

  const _AccentSection({required this.state, required this.cubit});

  Future<void> _pickCustom(BuildContext context) async {
    final picked = await AccentColorPickerDialog.show(
      context,
      initial: state.accent,
      option: state.theme,
    );
    if (picked == null) return;
    cubit.setCustomAccent(picked);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final currentAccent = state.accent;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Accent colour',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: tokens.onSurface,
                ),
              ),
            ),
            if (state.hasCustomAccent)
              TextButton(
                onPressed: cubit.clearCustomAccent,
                child: const Text('Use theme accent'),
              ),
          ],
        ),
        Text(
          'Pick a preset or create a custom accent. Choosing a theme resets '
          'the accent to that theme\u2019s default.',
          style: TextStyle(fontSize: 12, color: tokens.onSurfaceVariant),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final color in kAccentPresets)
              _AccentSwatch(
                color: color,
                selected: currentAccent == color,
                onTap: () => cubit.setCustomAccent(color),
              ),
            _CustomAccentButton(
              selected:
                  state.hasCustomAccent &&
                  !kAccentPresets.contains(currentAccent),
              onTap: () => _pickCustom(context),
            ),
          ],
        ),
        const SizedBox(height: 18),
        const _ControlsPreview(),
      ],
    );
  }
}

class _AccentSwatch extends StatelessWidget {
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _AccentSwatch({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Semantics(
      button: true,
      selected: selected,
      label: 'Accent ${_hex(color)}',
      child: InkResponse(
        onTap: onTap,
        radius: 26,
        child: Container(
          width: 38,
          height: 36,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? tokens.onSurface : tokens.border,
              width: selected ? 3 : 1,
            ),
          ),
          child: selected
              ? Icon(Icons.check, size: 18, color: onColorFor(color))
              : null,
        ),
      ),
    );
  }
}

String _hex(Color color) =>
    '#${color.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';

/// Opens the custom accent picker. Styled as a swatch so it sits with the
/// presets without breaking the row.
class _CustomAccentButton extends StatelessWidget {
  final bool selected;
  final VoidCallback onTap;

  const _CustomAccentButton({required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final accent = Theme.of(context).colorScheme.primary;
    return Semantics(
      button: true,
      label: 'Custom accent colour',
      child: Tooltip(
        message: 'Custom accent',
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: tokens.surfaceElevated,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: selected ? accent : tokens.border,
                width: selected ? 2 : 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.colorize, size: 18, color: tokens.onSurfaceVariant),
                const SizedBox(width: 6),
                Text(
                  'Custom',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: tokens.onSurface,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A compact preview of the controls the accent affects: a filled button, a
/// selected chip and a slider. Because it is rendered with the live theme, it
/// reflects the current accent as soon as it changes.
class _ControlsPreview extends StatelessWidget {
  const _ControlsPreview();

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: tokens.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Preview',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: tokens.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FilledButton(onPressed: () {}, child: const Text('Primary')),
              FilterChip(
                label: const Text('Selected'),
                selected: true,
                onSelected: (_) {},
              ),
            ],
          ),
          Slider(value: 0.6, onChanged: (_) {}),
        ],
      ),
    );
  }
}
