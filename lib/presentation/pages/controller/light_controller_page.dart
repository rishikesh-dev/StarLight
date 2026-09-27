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
import 'package:starlight/presentation/widgets/debug_panel.dart';

/// Consumer-grade StarLight controller.
class LightControllerPage extends StatefulWidget {
  const LightControllerPage({super.key});

  @override
  State<LightControllerPage> createState() => _LightControllerPageState();
}

class _LightControllerPageState extends State<LightControllerPage> {
  RGBColor _currentColor = const RGBColor(255, 0, 0);
  int _brightness = 1000;
  bool _isOn = true;

  void _syncFromState(LightState state) {
    final color = switch (state) {
      LightOn(:final color) => color,
      PresetsLoaded(:final color) => color,
      _ => null,
    };
    final brightness = switch (state) {
      LightOn(:final brightness) => brightness,
      LightOff(:final brightness) => brightness,
      PresetsLoaded(:final brightness) => brightness,
      _ => null,
    };
    final isOn = switch (state) {
      LightOn() => true,
      LightOff() => false,
      PresetsLoaded(:final isOn) => isOn,
      _ => null,
    };
    if (color != null) _currentColor = color;
    if (brightness != null) _brightness = brightness;
    if (isOn != null) _isOn = isOn;
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('StarLight'),
        actions: [
          BlocBuilder<BleBloc, BleState>(
            builder: (context, state) {
              if (state is BleConnected || state is BleConnecting) {
                return IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () {
                    context.read<BleBloc>().add(DisconnectRequested());
                    Navigator.of(context).pop();
                  },
                  tooltip: 'Disconnect',
                );
              }
              return const SizedBox.shrink();
            },
          ),
        ],
      ),
      body: BlocListener<LightBloc, LightState>(
        listener: (context, state) => _syncFromState(state),
        child: BlocBuilder<LightBloc, LightState>(
          builder: (context, lightState) {
            final isConnected = switch (lightState) {
              LightOn(:final isConnected) => isConnected,
              LightOff(:final isConnected) => isConnected,
              PresetsLoaded(:final isConnected) => isConnected,
              _ => true,
            };
            _syncFromState(lightState);
            return games;
          },
        ),
      ),
    );
  }
}
