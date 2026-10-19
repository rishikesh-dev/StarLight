// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';

/// Brightness slider for LED brightness control.
///
/// The original APK uses a SeekBar with max=1000 (fragment_adjust.xml).
/// Minimum brightness is clamped to 3.
class BrightnessSlider extends StatelessWidget {
  final int brightness;
  final bool isConnected;
  final ValueChanged<int> onChanged;
  final ValueChanged<int> onChangeEnd;

  const BrightnessSlider({
    super.key,
    required this.brightness,
    required this.isConnected,
    required this.onChanged,
    required this.onChangeEnd,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final normalizedBrightness = (brightness / 1000).clamp(0.0, 1.0);

    return Semantics(
      label: 'Brightness $brightness',
      value: brightness.toString(),
      slider: true,
      enabled: isConnected,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Brightness', style: theme.textTheme.titleMedium),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF8E6CFF).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '$brightness',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF8E6CFF),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              thumbColor: const Color(0xFF8E6CFF),
              activeTrackColor: const Color(0xFF8E6CFF),
              inactiveTrackColor: Colors.grey.shade800,
              overlayColor: const Color(0xFF8E6CFF).withValues(alpha: 0.2),
              trackShape: const RectangularSliderTrackShape(),
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
            ),
            child: Slider(
              value: normalizedBrightness.toDouble(),
              min: 0.0,
              max: 1.0,
              onChanged: isConnected
                  ? (v) => onChanged((v * 1000).round())
                  : null,
              onChangeEnd: (v) => onChangeEnd((v * 1000).round()),
            ),
          ),
        ],
      ),
    );
  }
}
