import 'package:equatable/equatable.dart';

import 'package:starlight/domain/entities/preset.dart';
import 'package:starlight/domain/entities/rgb_color.dart';

/// States for the Light Bloc.
abstract class LightState extends Equatable {
  const LightState();

  @override
  List<Object?> get props => [];
}

/// Initial state.
class LightInitial extends LightState {}

/// Light is on with the given color and brightness.
class LightOn extends LightState {
  final RGBColor color;
  final int brightness;
  final List<Preset> presets;
  final bool isConnected;

  const LightOn({
    required this.color,
    required this.brightness,
    required this.presets,
    required this.isConnected,
  });

  @override
  List<Object?> get props => [color, brightness, presets, isConnected];
}

/// Light is off.
class LightOff extends LightState {
  final int brightness;
  final List<Preset> presets;
  final bool isConnected;

  const LightOff({
    required this.brightness,
    required this.presets,
    required this.isConnected,
  });

  @override
  List<Object?> get props => [brightness, presets, isConnected];
}

/// Color changed.
class ColorChanged extends LightState {
  final RGBColor color;
  final int brightness;
  final List<Preset> presets;
  final bool isConnected;

  const ColorChanged({
    required this.color,
    required this.brightness,
    required this.presets,
    required this.isConnected,
  });

  @override
  List<Object?> get props => [color, brightness, presets, isConnected];
}

/// Brightness changed.
class BrightnessChanged extends LightState {
  final RGBColor color;
  final int brightness;
  final List<Preset> presets;
  final bool isConnected;

  const BrightnessChanged({
    required this.color,
    required this.brightness,
    required this.presets,
    required this.isConnected,
  });

  @override
  List<Object?> get props => [color, brightness, presets, isConnected];
}

/// Presets loaded.
class PresetsLoaded extends LightState {
  final RGBColor color;
  final int brightness;
  final List<Preset> presets;
  final bool isOn;
  final bool isConnected;

  const PresetsLoaded({
    required this.color,
    required this.brightness,
    required this.presets,
    required this.isOn,
    required this.isConnected,
  });

  @override
  List<Object?> get props => [color, brightness, presets, isOn, isConnected];
}

/// Error state.
class LightError extends LightState {
  final String message;

  const LightError(this.message);

  @override
  List<Object?> get props => [message];
}
