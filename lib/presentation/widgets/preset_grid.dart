import 'package:flutter/material.dart';

import '../../domain/entities/preset.dart';

/// A grid of preset color buttons.
///
/// Presets match the original APK's color buttons (e1/a.java):
/// - 7 selectable color buttons with stored RGB values
/// - Editable locally (long press to save current color)
class PresetGrid extends StatelessWidget {
  final List<Preset> presets;
  final ValueChanged<Preset> onSelect;
  final VoidCallback onAdd;

  const PresetGrid({
    super.key,
    required this.presets,
    required this.onSelect,
    required this.onAdd,
  });

  static const Map<String, Color> _presetColors = {
    'Red': Color(0xFFFF0000),
    'Green': Color(0xFF00FF00),
    'Blue': Color(0xFF0000FF),
    'Purple': Color(0xFFFF00FF),
    'Cyan': Color(0xFF00FFFF),
    'Yellow': Color(0xFFFFD700),
    'White': Color(0xFFFFFFFF),
    'Warm White': Color(0xFFFFF5E4),
  };

  Color _colorForPreset(Preset p) {
    final direct = _presetColors[p.name];
    if (direct != null) return direct;
    return Color((p.red << 16) | (p.green << 8) | p.blue);
  }

  @override
  Widget build(BuildContext context) {
    final allPresets = List<Preset>.from(presets);
    // Ensure at least the 7 standard presets exist
    if (allPresets.isEmpty) {
      allPresets.addAll(_defaultPresets);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Presets',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final preset in allPresets)
              _PresetButton(
                preset: preset,
                color: _colorForPreset(preset),
                onTap: () => onSelect(preset),
              ),
            IconButton(
              onPressed: onAdd,
              icon: const Icon(Icons.add, color: Colors.grey),
              tooltip: 'Add preset',
            ),
          ],
        ),
      ],
    );
  }

  static final List<Preset> _defaultPresets = [
    const Preset(id: 1, name: 'Red', red: 255, green: 0, blue: 0),
    const Preset(id: 2, name: 'Green', red: 0, green: 255, blue: 0),
    const Preset(id: 3, name: 'Blue', red: 0, green: 0, blue: 255),
    const Preset(id: 4, name: 'Purple', red: 255, green: 0, blue: 255),
    const Preset(id: 5, name: 'Cyan', red: 0, green: 255, blue: 255),
    const Preset(id: 6, name: 'Yellow', red: 255, green: 255, blue: 0),
    const Preset(id: 7, name: 'White', red: 255, green: 255, blue: 255),
    const Preset(id: 8, name: 'Warm White', red: 255, green: 245, blue: 228),
  ];
}

class _PresetButton extends StatelessWidget {
  final Preset preset;
  final Color color;
  final VoidCallback onTap;

  const _PresetButton({
    required this.preset,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: const Color(0xFF8E6CFF),
            width: 2,
          ),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.4),
              blurRadius: 8,
            ),
          ],
        ),
      ),
    );
  }
}
