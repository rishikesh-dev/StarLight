// SPDX-License-Identifier: Apache-2.0

import 'package:equatable/equatable.dart';

import 'package:starlight/domain/entities/device_state_update.dart';
import 'package:starlight/domain/entities/rgb_color.dart';
import 'package:starlight/domain/services/effect_engine.dart';

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

/// Select a device-native effect by its command name.
///
/// The name must be one the active transport understands (for the built-in
/// MR Star path: a name from `ProtocolEncoder`'s mode set, surfaced in the UI
/// through `EffectDefinition.commandName`). Routing decides whether it is
/// encoded by the MR Star encoder or the verified custom profile executor.
class ChangeEffect extends LightEvent {
  final String name;

  const ChangeEffect(this.name);

  @override
  List<Object?> get props => [name];
}

/// Set the device-native effect speed (raw device value, 0–100).
class ChangeSpeed extends LightEvent {
  final int value;

  const ChangeSpeed(this.value);

  @override
  List<Object?> get props => [value];
}

/// Start playing a StarLight custom effect by its stable catalogue id.
///
/// Custom effects are streamed as global colours through the same router the
/// other controls use; they are never selected through the device-mode path.
class PlayCustomEffect extends LightEvent {
  final String effectId;

  const PlayCustomEffect(this.effectId);

  @override
  List<Object?> get props => [effectId];
}

/// Stop the active custom-effect playback.
class StopCustomEffect extends LightEvent {
  const StopCustomEffect();
}

/// Update the rendering parameters of the custom effect (no device traffic on
/// its own; applied live when playback is active).
class ConfigureCustomEffect extends LightEvent {
  final int? speed;
  final int? intensity;
  final String? paletteId;

  const ConfigureCustomEffect({this.speed, this.intensity, this.paletteId});

  @override
  List<Object?> get props => [speed, intensity, paletteId];
}

/// Internal event: the custom-effect player stopped by itself (a frame write
/// failed or the device went away). Never emitted for an explicit stop.
class CustomEffectStopped extends LightEvent {
  final EffectCommandResult result;

  const CustomEffectStopped(this.result);

  @override
  List<Object?> get props => [result];
}

/// Load presets from local storage.
class LoadPresets extends LightEvent {}

/// Internal event: the device reported a state update over the notify
/// characteristic (FFF4). Only real device notifications feed this event;
/// command writes are never treated as confirmation.
class DeviceStateReceived extends LightEvent {
  final StateUpdateType type;
  final dynamic value;

  const DeviceStateReceived(this.type, this.value);

  @override
  List<Object?> get props => [type, value];
}

/// Internal event: BLE connection state changed.
/// Re-emits the current light state so `isConnected` stays accurate in the UI.
class ConnectionChanged extends LightEvent {
  final bool isConnected;

  const ConnectionChanged(this.isConnected);

  @override
  List<Object?> get props => [isConnected];
}

/// Internal event: the active route changed (a custom profile was assigned,
/// verified or cleared). Re-emits the current state so the UI's controls follow
/// the capabilities that can actually be executed.
class CapabilitiesChanged extends LightEvent {}

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
