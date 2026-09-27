import 'package:flutter/material.dart';

import 'package:starlight/domain/entities/rgb_color.dart';
import 'package:starlight/presentation/theme/app_theme.dart';

/// A compact color swatch grid for quick color selection.
class QuickColorPicker extends StatelessWidget {
  final RGBColor currentColor;
  final bool isConnected;
  final ValueChanged<RGBColor> onColorSelected;

  static const List<RGBColor> _quickColors = [
    RGBColor(255, 0, 0),
    RGBColor(0, 255, 0),
    RGBColor(0, 0, 255),
    RGBColor(255, 0, 255),
    RGBColor(255, 255, 0),
    RGBColor(255, 255, 255),
    RGBColor(255, 245, 228),
    RGBColor(0, 255, 255),
  ];

  const QuickColorPicker({
    super.key,
    required this.currentColor,
    this.isConnected = true,
    required this.onColorSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final color in _quickColors)
          _ColorSwatch(
            color: color,
            isSelected: color == currentColor,
            isEnabled: isConnected,
            onTap: () => onColorSelected(color),
          ),
      ],
    );
  }
}

class _ColorSwatch extends StatelessWidget {
  final RGBColor color;
  final bool isSelected;
  final bool isEnabled;
  final VoidCallback onTap;

  const _ColorSwatch({
    required this.color,
    required this.isSelected,
    required this.isEnabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final flutterColor = Color(
      (color.red << 16) | (color.green << 8) | color.blue,
    );
    return Semantics(
      label: 'Color ${color.toHexStr()}',
      button: true,
      enabled: isEnabled,
      selected: isSelected,
      child: InkResponse(
        onTap: isEnabled ? onTap : null,
        radius: 30,
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: flutterColor,
            shape: BoxShape.circle,
            border: Border.all(
              color: isSelected
                  ? Colors.white
                  : flutterColor == Colors.white
                      ? AppColors.border
                      : Colors.transparent,
              width: isSelected ? 3 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: flutterColor.withValues(alpha: 0.5),
                blurRadius: 8,
              ),
              if (isSelected)
                BoxShadow(
                  color: Colors.white.withValues(alpha: 0.6),
                  blurRadius: 0,
                  spreadRadius: 1,
                ),
            ],
          ),
          child: isSelected
              ? const Icon(Icons.check, color: Colors.black, size: 18)
              : null,
        ),
      ),
    );
  }
}