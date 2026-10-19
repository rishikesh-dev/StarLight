// SPDX-License-Identifier: Apache-2.0

import 'package:starlight/domain/entities/device_capability.dart';
import 'package:starlight/domain/entities/effect.dart';
import 'package:starlight/domain/entities/preset.dart';
import 'package:starlight/domain/entities/rgb_color.dart';

import 'light_state.dart';

/// Read-only projections of [LightState] used by the Home dashboard and the
/// Lighting Studio.
///
/// Centralised so every widget derives the same values from the same state
/// (rather than re-implementing the switch and drifting apart).
extension LightStateView on LightState {
  /// Whether the light is on. Optimistic command states are treated as "on".
  bool get isLightOn => switch (this) {
    LightOn() => true,
    LightOff() => false,
    PresetsLoaded(:final isOn) => isOn,
    ColorChanged() => true,
    BrightnessChanged() => true,
    EffectChanged(:final isOn) => isOn,
    _ => false,
  };

  /// Brightness in the device's 0–1000 range.
  int get lightBrightness => switch (this) {
    LightOn(:final brightness) => brightness,
    LightOff(:final brightness) => brightness,
    ColorChanged(:final brightness) => brightness,
    BrightnessChanged(:final brightness) => brightness,
    PresetsLoaded(:final brightness) => brightness,
    EffectChanged(:final brightness) => brightness,
    _ => 0,
  };

  /// Brightness as a 0–100 percentage.
  int get brightnessPercent => (lightBrightness / 10).round().clamp(0, 100);

  /// Last known colour.
  RGBColor get lightColor => switch (this) {
    LightOn(:final color) => color,
    ColorChanged(:final color) => color,
    BrightnessChanged(:final color) => color,
    PresetsLoaded(:final color) => color,
    EffectChanged(:final color) => color,
    _ => const RGBColor(255, 255, 255),
  };

  /// Configured presets (empty until loaded).
  List<Preset> get lightPresets => switch (this) {
    LightOn(:final presets) => presets,
    LightOff(:final presets) => presets,
    ColorChanged(:final presets) => presets,
    BrightnessChanged(:final presets) => presets,
    PresetsLoaded(:final presets) => presets,
    EffectChanged(:final presets) => presets,
    _ => const <Preset>[],
  };

  /// Whether the transport currently reports a live connection.
  bool get lightIsConnected => switch (this) {
    LightOn(:final isConnected) => isConnected,
    LightOff(:final isConnected) => isConnected,
    ColorChanged(:final isConnected) => isConnected,
    BrightnessChanged(:final isConnected) => isConnected,
    PresetsLoaded(:final isConnected) => isConnected,
    EffectChanged(:final isConnected) => isConnected,
    _ => false,
  };

  /// Last confirmed effect command name, or `null` when none is known.
  ///
  /// "Confirmed" here means the command write completed without a reported
  /// failure — the same standard every other light control in this app uses.
  String? get lightEffect => switch (this) {
    LightOn(:final effect) => effect,
    LightOff(:final effect) => effect,
    ColorChanged(:final effect) => effect,
    BrightnessChanged(:final effect) => effect,
    PresetsLoaded(:final effect) => effect,
    EffectChanged(:final effect) => effect,
    _ => null,
  };

  /// Last confirmed effect speed (raw device value), or `null`.
  int? get lightSpeed => switch (this) {
    LightOn(:final speed) => speed,
    LightOff(:final speed) => speed,
    ColorChanged(:final speed) => speed,
    BrightnessChanged(:final speed) => speed,
    PresetsLoaded(:final speed) => speed,
    EffectChanged(:final speed) => speed,
    _ => null,
  };

  /// Id of the custom effect last started by the player, or `null`.
  String? get lightCustomEffectId => switch (this) {
    EffectChanged(:final customEffectId) => customEffectId,
    _ => null,
  };

  /// Whether the custom-effect player is currently streaming.
  bool get lightCustomPlaying => switch (this) {
    EffectChanged(:final customPlaying) => customPlaying,
    _ => false,
  };

  /// Custom-effect speed parameter (0–100), or `null` when none is set.
  int? get lightCustomSpeed => switch (this) {
    EffectChanged(:final customSpeed) => customSpeed,
    _ => null,
  };

  /// Custom-effect intensity parameter (0–100), or `null`.
  int? get lightCustomIntensity => switch (this) {
    EffectChanged(:final customIntensity) => customIntensity,
    _ => null,
  };

  /// Selected palette id for the active custom effect.
  String? get lightCustomPaletteId => switch (this) {
    EffectChanged(:final customPaletteId) => customPaletteId,
    _ => null,
  };

  /// Catalogue id of whatever is active on the device right now: the streaming
  /// custom effect, otherwise the last confirmed device pattern.
  String? get lightActiveEffectId {
    final custom = lightCustomEffectId;
    if (custom != null) return custom;
    return effectByCommandName(lightEffect)?.id;
  }

  /// Capabilities the UI may expose for the current device/profile.
  ///
  /// Empty while a custom profile is assigned but not verified, so controls
  /// that cannot actually be executed are never shown.
  Set<DeviceCapability> get lightCapabilities => capabilities;
}
