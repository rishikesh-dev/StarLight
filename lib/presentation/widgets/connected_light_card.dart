import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:starlight/domain/entities/rgb_color.dart';
import 'package:starlight/presentation/bloc/ble/ble_bloc.dart';
import 'package:starlight/presentation/bloc/ble/ble_state.dart';
import 'package:starlight/presentation/bloc/light/light_bloc.dart';
import 'package:starlight/presentation/bloc/light/light_event.dart';
import 'package:starlight/presentation/bloc/light/light_state.dart';
import 'package:starlight/presentation/widgets/power_button.dart';
import 'package:starlight/presentation/widgets/quick_color_picker.dart';

/// Premium home card for the connected StarLight device.
class ConnectedLightCard extends StatelessWidget {
  const ConnectedLightCard({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<BleBloc, BleState>(
      buildWhen: (p, c) => c is BleConnected || p is BleConnected,
      builder: (context, bleState) {
        final device = (bleState is BleConnected) ? bleState.device : null;
        if (device == null) return const SizedBox.shrink();

        return BlocBuilder<LightBloc, LightState>(
          buildWhen: (p, c) =>
              c is LightOn || c is LightOff || c is PresetsLoaded ||
              p is LightOn || p is LightOff || p is PresetsLoaded,
          builder: (context, lightState) {
            final isOn = switch (lightState) {
              LightOn() => true,
              LightOff() => false,
              PresetsLoaded(:final isOn) => isOn,
              _ => true,
            };
            final brightness = switch (lightState) {
              LightOn(:final brightness) => brightness,
              LightOff(:final brightness) => brightness,
              PresetsLoaded(:final brightness) => brightness,
              _ => 1000,
            };
            final color = switch (lightState) {
              LightOn(:final color) => color,
              PresetsLoaded(:final color) => color,
              _ => const RGBColor(255, 0, 0),
            };

            final brightnessPercent = (brightness / 10).round().clamp(0, 100);

            return Semantics(
              label: 'Open ${device.name} controller',
              button: true,
              child: InkResponse(
                onTap: () => Navigator.of(context).pushNamed('/controller'),
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1A1F),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFF2A2A32), width: 1),
                    boxShadow: [
                      BoxShadow(
                        color: Color((color.red << 16) | (color.green << 8) | color.blue)
                            .withValues(alpha: 0.4),
                        blurRadius: 16,
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: const Color(0xFF8E6CFF).withValues(alpha: 0.2),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.light, color: Color(0xFF8E6CFF), size: 24),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  device.name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 18,
                                  ),
                                ),
                                Text(
                                  isOn ? 'ON  •  Connected' : 'OFF  •  Connected',
                                  style: TextStyle(
                                    color: isOn ? const Color(0xFF4CAF50) : const Color(0xFF9A9AA8),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Icon(Icons.chevron_right, color: Color(0xFF9A9AA8)),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          PowerButton(
                            isOn: isOn,
                            isConnected: true,
                            onTap: () => context.read<LightBloc>().add(TogglePower(!isOn)),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '$brightnessPercent%',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 16,
                                  ),
                                ),
                                Slider(
                                  value: brightnessPercent.toDouble(),
                                  min: 0,
                                  max: 100,
                                  divisions: 100,
                                  label: '$brightnessPercent%',
                                  onChanged: (v) {
                                    context.read<LightBloc>().add(
                                      ChangeBrightness((v * 10).round()),
                                    );
                                  },
                                  onChangeEnd: (v) {
                                    context.read<LightBloc>().add(
                                      ChangeBrightness((v * 10).round()),
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      QuickColorPicker(
                        currentColor: color,
                        isConnected: true,
                        onColorSelected: (c) => context.read<LightBloc>().add(
                          ChangeColor(c),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}