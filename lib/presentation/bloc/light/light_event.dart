import 'package:equatable/equatable.dart';

import 'package:starlight/domain/entities/rgb_color.dart';

/// Events for the Light Bloc.
abstract class LightEvent extends Equatable {
  const LightEvent();

  @override
  List<Object?> get props => [];
}

/// Power toggle on/off.
class TogglePower extends LightEvent {
  final bool on;

  const TogglePower(this.on);

  @override
  List<Object?> get props => [on];
}

/// Change the LED color.
class ChangeColor extends LightEvent {
  final RGBColor color;

  const ChangeColor(this.color);

  @override
  List<Object?> get props => [color];
}

/// Change the brightness.
class ChangeBrightness extends LightEvent {
  final int brightness;

  const ChangeBrightness(this.brightness);

  @override
  List<Object?> get props => [brightness];
}

/// Select a preset color.
class SelectPreset extends LightEvent {
  final int red;
  final int green;
  final int blue;

  const SelectPreset(this.red, this.green, this.blue);

  @override
  List<Object?> get props => [red, green, blue];
}

/// Load presets from local storage.
class LoadPresets extends LightEvent {}

/// Save a preset.
class SavePreset extends LightEvent {
  final int id;
  final String name;
  final int red;
  final int green;
  final int blue;

  const SavePreset(this.id, this.name, this.red, this.green, this.blue);

  @override
  List<Object?> get props => [id, name, red, green, blue];
}

/// Delete a preset.
class DeletePreset extends LightEvent {
  final int id;

  const DeletePreset(this.id);

  @override
  List<Object?> get props => [id];
}

/// Clear preset storage.
class ClearPresets extends LightEvent {}
