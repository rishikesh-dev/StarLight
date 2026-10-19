// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';

import 'package:starlight/presentation/theme/app_theme.dart';

/// Compact, dependency-free RGB picker for a *custom accent* colour.
///
/// Returns the chosen [Color] on confirmation, or `null` when cancelled. The
/// embedded preview is re-themed live with the draft colour so the user can see
/// how buttons, selected chips and sliders will look before applying.
class AccentColorPickerDialog extends StatefulWidget {
  final Color initial;
  final AppThemeOption option;

  const AccentColorPickerDialog({
    super.key,
    required this.initial,
    required this.option,
  });

  static Future<Color?> show(
    BuildContext context, {
    required Color initial,
    required AppThemeOption option,
  }) {
    return showDialog<Color>(
      context: context,
      builder: (_) => AccentColorPickerDialog(initial: initial, option: option),
    );
  }

  @override
  State<AccentColorPickerDialog> createState() =>
      _AccentColorPickerDialogState();
}

class _AccentColorPickerDialogState extends State<AccentColorPickerDialog> {
  late double _red;
  late double _green;
  late double _blue;

  @override
  void initState() {
    super.initState();
    _red = widget.initial.r * 255;
    _green = widget.initial.g * 255;
    _blue = widget.initial.b * 255;
  }

  Color get _color =>
      Color.fromARGB(255, _red.round(), _green.round(), _blue.round());

  String get _hex =>
      '#${_color.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final draftTheme = buildAppTheme(
      option: widget.option,
      accentOverride: _color,
    );

    return AlertDialog(
      title: const Text('Custom accent'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              height: 56,
              decoration: BoxDecoration(
                color: _color,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: tokens.border),
              ),
            ),
            const SizedBox(height: 12),
            _channel('Red', _red, (v) => setState(() => _red = v)),
            _channel('Green', _green, (v) => setState(() => _green = v)),
            _channel('Blue', _blue, (v) => setState(() => _blue = v)),
            const SizedBox(height: 4),
            Text(
              _hex,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: tokens.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            // Live preview of the accent in context.
            Theme(
              data: draftTheme,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: draftTheme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: draftTheme.colorScheme.outline),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        FilledButton(
                          onPressed: () {},
                          child: const Text('Button'),
                        ),
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
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_color),
          child: const Text('Apply'),
        ),
      ],
    );
  }

  Widget _channel(String label, double value, ValueChanged<double> onChanged) {
    return Row(
      children: [
        SizedBox(
          width: 48,
          child: Text(label, style: Theme.of(context).textTheme.bodySmall),
        ),
        Expanded(
          child: Slider(
            value: value,
            min: 0,
            max: 255,
            divisions: 255,
            label: value.round().toString(),
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 34,
          child: Text(
            value.round().toString(),
            textAlign: TextAlign.end,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}
