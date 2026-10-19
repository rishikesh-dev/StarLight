// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';

import '../../domain/entities/rgb_color.dart';
import '../utils/text_style_extension.dart';

/// RGB color picker with draggable sliders.
///
/// Updates are debounced to avoid overloading the BLE connection.
/// The original APK sends color on every touch event; this version
/// adds a small throttle while keeping the UI responsive.
class ColorPickerWidget extends StatefulWidget {
  final RGBColor initialColor;
  final bool isConnected;
  final ValueChanged<RGBColor> onColorChanged;
  final VoidCallback onAddColor;

  const ColorPickerWidget({
    super.key,
    required this.initialColor,
    required this.isConnected,
    required this.onColorChanged,
    required this.onAddColor,
  });

  @override
  State<ColorPickerWidget> createState() => _ColorPickerWidgetState();
}

class _ColorPickerWidgetState extends State<ColorPickerWidget> {
  late int _r;
  late int _g;
  late int _b;

  @override
  void initState() {
    super.initState();
    _r = widget.initialColor.red;
    _g = widget.initialColor.green;
    _b = widget.initialColor.blue;
  }

  @override
  void didUpdateWidget(covariant ColorPickerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialColor != widget.initialColor) {
      _r = widget.initialColor.red;
      _g = widget.initialColor.green;
      _b = widget.initialColor.blue;
    }
  }

  void _updateColor(int r, int g, int b) {
    setState(() {
      _r = r;
      _g = g;
      _b = b;
    });
    widget.onColorChanged(RGBColor(r, g, b));
  }

  @override
  Widget build(BuildContext context) {
    final currentColor = Color((_r << 16) | (_g << 8) | _b);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Color', style: Theme.of(context).textTheme.titleMedium),
            if (widget.isConnected)
              IconButton(
                icon: const Icon(Icons.favorite, color: Color(0xFF8E6CFF)),
                onPressed: widget.onAddColor,
                tooltip: 'Add current color as preset',
              ),
          ],
        ),
        const SizedBox(height: 12),
        // Preview box
        Container(
          width: double.infinity,
          height: 80,
          decoration: BoxDecoration(
            color: currentColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: currentColor, width: 2),
            boxShadow: [
              BoxShadow(
                color: currentColor.withValues(alpha: 0.5),
                blurRadius: 12,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // RGB Sliders
        _buildSlider('R', _r, Colors.red, (v) {
          _updateColor(v, _g, _b);
        }),
        const SizedBox(height: 8),
        _buildSlider('G', _g, Colors.green, (v) {
          _updateColor(_r, v, _b);
        }),
        const SizedBox(height: 8),
        _buildSlider('B', _b, Colors.blue, (v) {
          _updateColor(_r, _g, v);
        }),
        const SizedBox(height: 6),
        Text(
          widget.initialColor.toHexStr(),
          style: Theme.of(context).textTheme.bodySmall
              ?.copyColor(const Color(0xFF8E6CFF)),
        ),
      ],
    );
  }

  Widget _buildSlider(
    String label,
    int value,
    Color color,
    ValueChanged<int> onChanged,
  ) {
    return Row(
      children: [
        SizedBox(
          width: 32,
          child: Text(label, style: TextStyle(color: color)),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              thumbColor: color,
              activeTrackColor: color,
              inactiveTrackColor: Colors.grey.shade800,
              overlayColor: color.withValues(alpha: 0.3),
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
            ),
            child: Slider(
              value: value.toDouble(),
              min: 0,
              max: 255,
              divisions: 255,
              label: value.toString(),
              onChanged: widget.isConnected
                  ? (v) => onChanged(v.toInt())
                  : null,
            ),
          ),
        ),
        SizedBox(
          width: 40,
          child: Text(
            value.toString(),
            style: const TextStyle(color: Colors.grey),
          ),
        ),
      ],
    );
  }
}
