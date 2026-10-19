// SPDX-License-Identifier: Apache-2.0

import 'package:equatable/equatable.dart';

import 'package:starlight/domain/entities/device_capability.dart';
import 'package:starlight/domain/entities/preset.dart';
import 'package:starlight/domain/entities/rgb_color.dart';

/// States for the Light Bloc.
///
/// Every "real" state carries the [capabilities] the UI is allowed to expose
/// for the connected device. They default to the built-in MR Star set and are
/// replaced by an assigned, verified custom profile. When a custom profile is
/// assigned but not verified the set is empty, so no control is offered that
/// could not actually be executed.
///
/// [effect] and [speed] (present on every real state) carry the last
/// *confirmed* device-native effect selection — i.e. the last value whose
/// command write completed without failure. They are `null` when no effect has
/// been confirmed yet; they are never invented from local UI state.
abstract class LightState extends Equatable {
  const LightState();

  /// Capabilities the UI may render for the connected device.
  Set<DeviceCapability> get capabilities => kDefaultLightCapabilities;

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
  final String? effect;
  final int? speed;
  @override
  final Set<DeviceCapability> capabilities;

  const LightOn({
    required this.color,
    required this.brightness,
    required this.presets,
    required this.isConnected,
    this.effect,
    this.speed,
    this.capabilities = kDefaultLightCapabilities,
  });

  @override
  List<Object?> get props => [
    color,
    brightness,
    presets,
    isConnected,
    effect,
    speed,
    capabilities,
  ];
}

/// Light is off.
class LightOff extends LightState {
  final int brightness;
  final List<Preset> presets;
  final bool isConnected;
  final String? effect;
  final int? speed;
  @override
  final Set<DeviceCapability> capabilities;

  const LightOff({
    required this.brightness,
    required this.presets,
    required this.isConnected,
    this.effect,
    this.speed,
    this.capabilities = kDefaultLightCapabilities,
  });

  @override
  List<Object?> get props => [
    brightness,
    presets,
    isConnected,
    effect,
    speed,
    capabilities,
  ];
}

/// Color changed.
class ColorChanged extends LightState {
  final RGBColor color;
  final int brightness;
  final List<Preset> presets;
  final bool isConnected;
  final String? effect;
  final int? speed;
  @override
  final Set<DeviceCapability> capabilities;

  const ColorChanged({
    required this.color,
    required this.brightness,
    required this.presets,
    required this.isConnected,
    this.effect,
    this.speed,
    this.capabilities = kDefaultLightCapabilities,
  });

  @override
  List<Object?> get props => [
    color,
    brightness,
    presets,
    isConnected,
    effect,
    speed,
    capabilities,
  ];
}

/// Brightness changed.
class BrightnessChanged extends LightState {
  final RGBColor color;
  final int brightness;
  final List<Preset> presets;
  final bool isConnected;
  final String? effect;
  final int? speed;
  @override
  final Set<DeviceCapability> capabilities;

  const BrightnessChanged({
    required this.color,
    required this.brightness,
    required this.presets,
    required this.isConnected,
    this.effect,
    this.speed,
    this.capabilities = kDefaultLightCapabilities,
  });

  @override
  List<Object?> get props => [
    color,
    brightness,
    presets,
    isConnected,
    effect,
    speed,
    capabilities,
  ];
}

/// Presets loaded.
class PresetsLoaded extends LightState {
  final RGBColor color;
  final int brightness;
  final List<Preset> presets;
  final bool isOn;
  final bool isConnected;
  final String? effect;
  final int? speed;
  @override
  final Set<DeviceCapability> capabilities;

  const PresetsLoaded({
    required this.color,
    required this.brightness,
    required this.presets,
    required this.isOn,
    required this.isConnected,
    this.effect,
    this.speed,
    this.capabilities = kDefaultLightCapabilities,
  });

  @override
  List<Object?> get props => [
    color,
    brightness,
    presets,
    isOn,
    isConnected,
    effect,
    speed,
    capabilities,
  ];
}

/// An effect-related command (mode selection or mode speed) completed
/// successfully on the transport.
///
/// Like every other light state this reflects a successful *write*, not an
/// observed device outcome — the UI must not present it as "the effect is
/// confirmed running on the hardware". [isOn] carries the bloc's current
/// known on/off value so connection/power projections stay accurate.
class EffectChanged extends LightState {
  final RGBColor color;
  final int brightness;
  final List<Preset> presets;
  final bool isOn;
  final bool isConnected;

  /// Last confirmed effect command name (null when only speed changed).
  final String? effect;

  /// Last confirmed effect speed (null when no speed has been sent yet).
  final int? speed;

  /// Id of the custom effect last started by the player, or `null`.
  final String? customEffectId;

  /// Whether the custom effect player is currently streaming.
  final bool customPlaying;

  /// Custom-effect rendering parameters (validated 0–100 / palette id).
  final int? customSpeed;
  final int? customIntensity;
  final String? customPaletteId;
  @override
  final Set<DeviceCapability> capabilities;

  const EffectChanged({
    required this.color,
    required this.brightness,
    required this.presets,
    required this.isOn,
    required this.isConnected,
    this.effect,
    this.speed,
    this.customEffectId,
    this.customPlaying = false,
    this.customSpeed,
    this.customIntensity,
    this.customPaletteId,
    this.capabilities = kDefaultLightCapabilities,
  });

  @override
  List<Object?> get props => [
    color,
    brightness,
    presets,
    isOn,
    isConnected,
    effect,
    speed,
    customEffectId,
    customPlaying,
    customSpeed,
    customIntensity,
    customPaletteId,
    capabilities,
  ];
}

/// Error state.
class LightError extends LightState {
  final String message;

  const LightError(this.message);

  @override
  List<Object?> get props => [message];
}
