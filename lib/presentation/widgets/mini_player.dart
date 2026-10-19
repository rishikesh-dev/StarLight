// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:starlight/domain/entities/rgb_color.dart';
import 'package:starlight/presentation/bloc/ble/ble_bloc.dart';
import 'package:starlight/presentation/bloc/ble/ble_state.dart';
import 'package:starlight/presentation/bloc/light/light_bloc.dart';
import 'package:starlight/presentation/bloc/light/light_event.dart';
import 'package:starlight/presentation/bloc/light/light_state.dart';
import 'package:starlight/presentation/theme/app_theme.dart';

/// Persistent mini-player bar shown while a device is connected.
class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<BleBloc, BleState>(
      buildWhen: (p, c) =>
          c is BleConnected ||
          p is BleConnected ||
          c is BleConnecting ||
          p is BleConnecting ||
          c is BleDisconnected ||
          p is BleDisconnected,
      builder: (context, bleState) {
        final connected = bleState is BleConnected;
        if (!connected) return const SizedBox.shrink();

        return BlocBuilder<LightBloc, LightState>(
          buildWhen: (p, c) =>
              c is LightOn ||
              c is LightOff ||
              c is PresetsLoaded ||
              p is LightOn ||
              p is LightOff ||
              p is PresetsLoaded,
          builder: (context, lightState) {
            final tokens = context.tokens;
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

            return Semantics(
              label: 'Active device ${(bleState).device.name}',
              button: true,
              child: InkResponse(
                onTap: () => Navigator.of(context).pushNamed('/controller'),
                child: Container(
                  height: 56,
                  decoration: BoxDecoration(
                    color: tokens.surfaceElevated,
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black54,
                        blurRadius: 8,
                        offset: Offset(0, -2),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      const SizedBox(width: 12),
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: Color(
                            (color.red << 16) | (color.green << 8) | color.blue,
                          ),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              (bleState).device.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              isOn
                                  ? 'ON  •  ${(brightness / 10).round()}%  •  ${color.toHexStr()}'
                                  : 'OFF',
                              style: TextStyle(
                                fontSize: 12,
                                color: isOn
                                    ? tokens.success
                                    : tokens.onSurfaceVariant,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      InkResponse(
                        onTap: () {
                          final bloc = context.read<LightBloc>();
                          bloc.add(TogglePower(!isOn));
                        },
                        child: Icon(
                          isOn ? Icons.power : Icons.power_off,
                          color: isOn
                              ? tokens.success
                              : tokens.onSurfaceVariant,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 12),
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
