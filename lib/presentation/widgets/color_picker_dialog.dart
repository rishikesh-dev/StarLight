// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';

import 'package:starlight/domain/entities/rgb_color.dart';
import 'package:starlight/presentation/theme/app_theme.dart';
import 'package:starlight/presentation/theme/rgb_color_x.dart';

/// Accessibility-friendly RGB picker.
///
/// The chosen colour is only returned on confirmation — the caller sends it to
/// the device, so a dismissed dialog never issues a command.
class ColorPickerDialog extends StatefulWidget {
  final RGBColor initial;

  const ColorPickerDialog({super.key, required this.initial});

  /// Shows the picker and resolves to the chosen colour, or `null` when the
  /// user cancels or dismisses it.
  static Future<RGBColor?> show(BuildContext context, RGBColor initial) {
    return showDialog<RGBColor>(
      context: context,
      builder: (_) => ColorPickerDialog(initial: initial),
    );
  }

  @override
  State<ColorPickerDialog> createState() => _ColorPickerDialogState();
}

class _ColorPickerDialogState extends State<ColorPickerDialog> {
  late double _red;
  late double _green;
  late double _blue;

  @override
  void initState() {
    super.initState();
    _red = widget.initial.red.toDouble();
    _green = widget.initial.green.toDouble();
    _blue = widget.initial.blue.toDouble();
  }

  RGBColor get _color => RGBColor(_red.round(), _green.round(), _blue.round());

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.tokens;
    final color = _color;

    return AlertDialog(
      title: const Text('Custom colour'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              height: 72,
              decoration: BoxDecoration(
                color: color.toColor(),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: tokens.border),
              ),
            ),
            const SizedBox(height: 16),
            _channel('Red', _red, (v) => setState(() => _red = v)),
            _channel('Green', _green, (v) => setState(() => _green = v)),
            _channel('Blue', _blue, (v) => setState(() => _blue = v)),
            const SizedBox(height: 4),
            Text(
              color.toHexStr(),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: tokens.onSurfaceVariant,
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
          onPressed: () => Navigator.of(context).pop(color),
          child: const Text('Apply'),
        ),
      ],
    );
  }

  Widget _channel(String label, double value, ValueChanged<double> onChanged) {
    return Row(
      children: [
        SizedBox(
          width: 52,
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
          width: 36,
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
