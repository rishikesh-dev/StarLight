// SPDX-License-Identifier: Apache-2.0

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

import 'device_capability.dart';

/// Groups an [EffectDefinition] for browsing in the Effects Studio.
///
/// Categories are presentation-level groupings only: they carry no protocol
/// meaning and never influence command generation.
enum EffectCategory {
  /// Effects that hold a steady output (e.g. Solid).
  static('Static'),

  /// Effects whose pattern travels along the strip (e.g. Rainbow, Chase).
  motion('Motion'),

  /// Effects based on pulsing or flashing (e.g. Breath, Flash).
  rhythm('Rhythm'),

  /// Effects that emulate ambient phenomena (e.g. Lava, Fireworks).
  ambient('Ambient');

  const EffectCategory(this.label);

  /// Display name used by the Effects Studio.
  final String label;
}

/// How an effect is produced. This is the core honesty boundary of the studio:
/// a *device pattern* is rendered by the controller firmware, a *custom effect*
/// is computed by StarLight and streamed as colours.
enum EffectKind {
  /// A pattern built into the controller, selected by a mode packet.
  hardwareNative('Device'),

  /// An algorithm in StarLight's own engine.
  custom('Custom');

  const EffectKind(this.label);

  /// Short label used in the studio (for badges and filters).
  final String label;
}

/// What the studio may claim about an effect's execution.
enum EffectPlayback {
  /// Sent to the device as a native mode packet. The pattern itself is the
  /// controller's; StarLight only selects it. A successful write only means
  /// the packet was accepted by the transport — not that the effect is visibly
  /// running on the hardware.
  deviceMode,

  /// Streamed by StarLight as a sequence of global colours. Valid only where
  /// the transport can write colours; never presented as per-pixel output.
  /// A successful frame write only means the colour packet was accepted.
  colorSequence,

  /// Rendered as a software preview only, because the effect needs per-pixel
  /// control the transport cannot provide. Physical playback is refused.
  previewOnly,
}

/// The execution route an [EffectDefinition] is compatible with.
///
/// This is an *explicit compatibility declaration*, not an inference: only the
/// route named here may ever encode the effect. Built-in effects are addressed
/// by the MR Star controller's native mode packet; custom effects are not
/// encoded here at all (they stream colours through the active colour route).
enum EffectExecutionRoute {
  /// Encoded by the built-in MR Star `ProtocolEncoder` mode packet
  /// (`BC 06 02 id/255 id%255 55`).
  mrStar('MR Star controller');

  const EffectExecutionRoute(this.label);

  final String label;
}

/// An inclusive integer range used to validate a parameter value.
///
/// Ranges describe the *app-advertised* contract for a parameter. They are not
/// a statement about what the physical hardware accepts — see
/// [kMrStarSpeedRange].
@immutable
class IntRange extends Equatable {
  final int min;
  final int max;

  const IntRange(this.min, this.max) : assert(min <= max, 'min must be <= max');

  /// Whether [value] lies inside the inclusive range.
  bool contains(int value) => value >= min && value <= max;

  @override
  List<Object?> get props => [min, max];

  @override
  String toString() => '$min–$max';
}

/// The MR Star effect-speed range the app exposes (0–100).
///
/// **Hardware validation pending.** The wire field for the mode-speed command
/// is a single byte (0–255), but the controller's *usable* range has not been
/// verified against hardware or the decompiled firmware. Rather than invent a
/// universal range, the app advertises the conservative 0–100 the existing UI
/// always used; values outside it are rejected rather than silently clamped or
/// wrapped. [ProtocolEncoder.setSpeed] separately rejects anything outside the
/// byte field so a wrapped value can never reach the wire.
const IntRange kMrStarSpeedRange = IntRange(0, 100);

/// Validated range for a custom effect's speed parameter (0–100).
///
/// This is a *rendering* parameter, not a wire value: it scales the algorithm's
/// time/frequency. It never reaches `ProtocolEncoder.setSpeed`.
const IntRange kEffectSpeedRange = IntRange(0, 100);

/// Validated range for a custom effect's intensity parameter (0–100).
const IntRange kEffectIntensityRange = IntRange(0, 100);

/// A typed, versioned description of one selectable effect.
///
/// An effect definition is *data*: it declares what the effect is, what the
/// device must support, and (for device patterns) the exact protocol command
/// used on the wire. It never executes anything itself — execution goes through
/// `LightBloc` → engine/player → `CommandRouter`, exactly like every other light
/// command, so a single BLE owner and the serialized write queue are preserved.
///
/// Two kinds share one catalogue and one set of lookups:
/// * [EffectKind.hardwareNative] — carries a [protocolModeId] and is encoded by
///   the MR Star controller route.
/// * [EffectKind.custom] — carries no protocol id; its pixels come from a
///   renderer keyed by [id] and it is (optionally) streamed as colours.
///
/// Versioning: [schemaVersion] describes the shape of this definition so
/// persisted or packaged effect references (Phase 5C+) can be validated before
/// use. Unknown versions must be rejected rather than guessed.
@immutable
class EffectDefinition extends Equatable {
  /// Schema version of [EffectDefinition]. Bump on breaking shape changes.
  static const int schemaVersion = 3;

  /// Stable identifier (lowercase slug). Safe to persist and reference from
  /// packages; independent of display names.
  final String id;

  /// Human-readable name shown in the UI. Never used for command generation.
  final String name;

  /// Whether this is a controller pattern or a StarLight algorithm.
  final EffectKind kind;

  /// The exact name the active transport understands for a device pattern, used
  /// by `DeviceCommand.effect(name)` and `effectByCommandName`. It is the
  /// protocol-facing string, kept separate from the display [name]. `null` for
  /// custom effects, which are never selected by a mode name.
  final String? commandName;

  /// Canonical protocol command identifier for [EffectExecutionRoute.mrStar].
  ///
  /// For a device pattern this is the controller mode id encoded by
  /// `ProtocolEncoder.setMode`. This is the **single** authoritative mapping
  /// between an effect and its wire command — there is no second table to drift
  /// out of sync. `null` for custom effects.
  final int? protocolModeId;

  /// The execution route this effect is compatible with.
  final EffectExecutionRoute route;

  /// Human-readable description shown in the Effects Studio.
  final String description;

  /// Category used for browsing.
  final EffectCategory category;

  /// Capabilities the active route must expose before this effect may be sent.
  final Set<DeviceCapability> requires;

  /// Validated range for the effect's speed parameter, or `null` when the
  /// effect has no speed parameter at all.
  final IntRange? speedRange;

  /// Validated range for a custom effect's intensity parameter, or `null`.
  final IntRange? intensityRange;

  /// Whether the effect lets the user choose a colour palette.
  final bool supportsPalette;

  /// The palette selected when none has been chosen, or `null` when the effect
  /// does not use palettes.
  final String? defaultPaletteId;

  /// Whether the effect needs per-pixel output the transport cannot provide.
  ///
  /// Custom-only. When true the effect is available as a software preview but
  /// physical playback is refused rather than faked.
  final bool requiresAddressable;

  /// Whether this device-native effect has been verified against physical
  /// hardware. Only applies to [EffectKind.hardwareNative] effects.
  ///
  /// When false (the default for MR Star modes), the effect can be sent but
  /// the app cannot confirm the resulting visual pattern matches the name.
  final bool hardwareVerified;

  const EffectDefinition({
    required this.id,
    required this.name,
    required this.description,
    required this.category,
    this.kind = EffectKind.hardwareNative,
    this.commandName,
    this.protocolModeId,
    this.route = EffectExecutionRoute.mrStar,
    this.requires = const {DeviceCapability.effect},
    this.speedRange,
    this.intensityRange,
    this.supportsPalette = false,
    this.defaultPaletteId,
    this.requiresAddressable = false,
    this.hardwareVerified = false,
  });

  /// Whether this effect exposes a speed parameter.
  bool get supportsSpeed => speedRange != null;

  /// Whether this effect exposes an intensity parameter.
  bool get supportsIntensity => intensityRange != null;

  /// Whether the studio can render this effect algorithmically.
  bool get supportsPreview => kind == EffectKind.custom;

  /// What the studio may claim about execution.
  EffectPlayback get playback {
    if (kind == EffectKind.hardwareNative) return EffectPlayback.deviceMode;
    if (requiresAddressable) return EffectPlayback.previewOnly;
    return EffectPlayback.colorSequence;
  }

  /// Whether the transport can actually play this effect on a device.
  bool get supportsPhysicalPlayback => playback != EffectPlayback.previewOnly;

  @override
  List<Object?> get props => [
    id,
    name,
    kind,
    commandName,
    protocolModeId,
    route,
    description,
    category,
    requires,
    speedRange,
    intensityRange,
    supportsPalette,
    defaultPaletteId,
    requiresAddressable,
    hardwareVerified,
  ];
}

/// The built-in catalogue of device-native effects for the MR Star protocol.
///
/// Each entry owns its display metadata *and* its canonical protocol command
/// ([EffectDefinition.protocolModeId]). Every encode site resolves through
/// [effectByCommandName] / [effectById] and `ProtocolEncoder.setMode`, so there
/// is exactly one mapping to keep correct.
///
/// The mode ids come from the decompiled controller APK and are **not verified
/// against hardware**; the Effects Studio therefore describes these as
/// device-native controller modes whose exact pattern depends on firmware.
/// [hardwareVerified] is false for all entries — a successful write only means
/// the mode packet was accepted, not that the visual pattern matches the name.
const List<EffectDefinition> kMrStarEffects = <EffectDefinition>[
  EffectDefinition(
    id: 'solid',
    name: 'Solid',
    commandName: 'Solid',
    protocolModeId: 0,
    description: 'Steady light in the current colour.',
    category: EffectCategory.static,
    speedRange: null,
    hardwareVerified: false,
  ),
  EffectDefinition(
    id: 'fireworks',
    name: 'Fireworks',
    commandName: 'Fireworks',
    protocolModeId: 1,
    description: 'Bursts of colour along the strip.',
    category: EffectCategory.ambient,
    speedRange: kMrStarSpeedRange,
    hardwareVerified: false,
  ),
  EffectDefinition(
    id: 'rainbow',
    name: 'Rainbow',
    commandName: 'Rainbow',
    protocolModeId: 2,
    description: 'Colours cycling along the strip.',
    category: EffectCategory.motion,
    speedRange: kMrStarSpeedRange,
    hardwareVerified: false,
  ),
  EffectDefinition(
    id: 'breath',
    name: 'Breath',
    commandName: 'Breath',
    protocolModeId: 3,
    description: 'Gentle pulsing brightness.',
    category: EffectCategory.rhythm,
    speedRange: kMrStarSpeedRange,
    hardwareVerified: false,
  ),
  EffectDefinition(
    id: 'scan',
    name: 'Scan',
    commandName: 'Scan',
    protocolModeId: 4,
    description: 'Light sweeping back and forth.',
    category: EffectCategory.motion,
    speedRange: kMrStarSpeedRange,
    hardwareVerified: false,
  ),
  EffectDefinition(
    id: 'flash',
    name: 'Flash',
    commandName: 'Flash',
    protocolModeId: 5,
    description: 'Rapid on/off flashing.',
    category: EffectCategory.rhythm,
    speedRange: kMrStarSpeedRange,
    hardwareVerified: false,
  ),
  EffectDefinition(
    id: 'police',
    name: 'Police',
    commandName: 'Police',
    protocolModeId: 6,
    description: 'Alternating red/blue patrol pattern.',
    category: EffectCategory.rhythm,
    speedRange: kMrStarSpeedRange,
    hardwareVerified: false,
  ),
  EffectDefinition(
    id: 'chase',
    name: 'Chase',
    commandName: 'Chase',
    protocolModeId: 7,
    description: 'A light segment running along the strip.',
    category: EffectCategory.motion,
    speedRange: kMrStarSpeedRange,
    hardwareVerified: false,
  ),
  EffectDefinition(
    id: 'comet',
    name: 'Comet',
    commandName: 'Comet',
    protocolModeId: 8,
    description: 'A bright head with a fading trail.',
    category: EffectCategory.motion,
    speedRange: kMrStarSpeedRange,
    hardwareVerified: false,
  ),
  EffectDefinition(
    id: 'lava',
    name: 'Lava',
    commandName: 'Lava',
    protocolModeId: 9,
    description: 'Slow, molten colour movement.',
    category: EffectCategory.ambient,
    speedRange: kMrStarSpeedRange,
    hardwareVerified: false,
  ),
  EffectDefinition(
    id: 'ocean',
    name: 'Ocean',
    commandName: 'Ocean',
    protocolModeId: 10,
    description: 'Slow wave-like colour motion.',
    category: EffectCategory.motion,
    speedRange: kMrStarSpeedRange,
    hardwareVerified: false,
  ),
];

/// StarLight's own algorithmic effects.
///
/// These are *not* controller modes: their pixels come from
/// [kCustomEffectRenderers] (keyed by [EffectDefinition.id]) and, where the
/// transport can write colours, they are streamed as a global-colour sequence.
/// Effects that need per-pixel control are marked [requiresAddressable] and are
/// preview-only — never faked through colour/brightness commands.
///
/// Requiring [DeviceCapability.color] (not `effect`) is deliberate: playback
/// needs to write colours, which a device may support even when it has no
/// native effect modes.
/// [hardwareVerified] is not applicable for custom effects (they are
/// StarLight-generated, not device-native).
const List<EffectDefinition> kCustomEffects = <EffectDefinition>[
  EffectDefinition(
    id: 'custom-aurora',
    name: 'Aurora',
    description: 'Slow ribbons of colour drifting like a night sky.',
    category: EffectCategory.ambient,
    kind: EffectKind.custom,
    requires: {DeviceCapability.color},
    speedRange: kEffectSpeedRange,
    intensityRange: kEffectIntensityRange,
    supportsPalette: true,
    defaultPaletteId: 'aurora',
    hardwareVerified: false,
  ),
  EffectDefinition(
    id: 'custom-ember',
    name: 'Ember',
    description: 'Warm coals flickering with a slow, ember glow.',
    category: EffectCategory.ambient,
    kind: EffectKind.custom,
    requires: {DeviceCapability.color},
    speedRange: kEffectSpeedRange,
    intensityRange: kEffectIntensityRange,
    supportsPalette: true,
    defaultPaletteId: 'ember',
    hardwareVerified: false,
  ),
  EffectDefinition(
    id: 'custom-ocean-drift',
    name: 'Ocean Drift',
    description: 'A slow blue-teal swell, like light under water.',
    category: EffectCategory.ambient,
    kind: EffectKind.custom,
    requires: {DeviceCapability.color},
    speedRange: kEffectSpeedRange,
    intensityRange: kEffectIntensityRange,
    supportsPalette: true,
    defaultPaletteId: 'ocean',
    hardwareVerified: false,
  ),
  EffectDefinition(
    id: 'custom-meteor',
    name: 'Meteor',
    description: 'A bright head with a long, fading trail.',
    category: EffectCategory.motion,
    kind: EffectKind.custom,
    requires: {DeviceCapability.color},
    speedRange: kEffectSpeedRange,
    intensityRange: kEffectIntensityRange,
    supportsPalette: true,
    defaultPaletteId: 'polar',
    requiresAddressable: true,
    hardwareVerified: false,
  ),
  EffectDefinition(
    id: 'custom-prism-flow',
    name: 'Prism Flow',
    description: 'Continuous movement through a chosen palette.',
    category: EffectCategory.motion,
    kind: EffectKind.custom,
    requires: {DeviceCapability.color},
    speedRange: kEffectSpeedRange,
    intensityRange: kEffectIntensityRange,
    supportsPalette: true,
    defaultPaletteId: 'neon',
    hardwareVerified: false,
  ),
  EffectDefinition(
    id: 'custom-soft-breath',
    name: 'Soft Breath',
    description: 'A smooth, non-linear breathing glow.',
    category: EffectCategory.rhythm,
    kind: EffectKind.custom,
    requires: {DeviceCapability.color},
    speedRange: kEffectSpeedRange,
    intensityRange: kEffectIntensityRange,
    defaultPaletteId: null,
    hardwareVerified: false,
  ),
  EffectDefinition(
    id: 'custom-color-bloom',
    name: 'Color Bloom',
    description: 'A palette transition that blooms from the centre.',
    category: EffectCategory.rhythm,
    kind: EffectKind.custom,
    requires: {DeviceCapability.color},
    speedRange: kEffectSpeedRange,
    intensityRange: kEffectIntensityRange,
    supportsPalette: true,
    defaultPaletteId: 'sunset',
    hardwareVerified: false,
  ),
  EffectDefinition(
    id: 'custom-starlight',
    name: 'Starlight',
    description: 'Sparse points of light, each fading on its own.',
    category: EffectCategory.ambient,
    kind: EffectKind.custom,
    requires: {DeviceCapability.color},
    speedRange: kEffectSpeedRange,
    intensityRange: kEffectIntensityRange,
    supportsPalette: true,
    defaultPaletteId: 'polar',
    requiresAddressable: true,
    hardwareVerified: false,
  ),
];

/// The single selectable catalogue: device patterns followed by StarLight's
/// custom effects. Lookups and the studio read this one list.
const List<EffectDefinition> kEffectCatalogue = <EffectDefinition>[
  ...kMrStarEffects,
  ...kCustomEffects,
];

/// Convenience: the catalogue effect with [id], or `null` when unknown.
EffectDefinition? effectById(String? id) {
  if (id == null) return null;
  for (final effect in kEffectCatalogue) {
    if (effect.id == id) return effect;
  }
  return null;
}

/// Convenience: the device-pattern effect whose
/// [EffectDefinition.commandName] equals [commandName], or `null` when unknown.
///
/// Only hardware-native effects have a command name, so custom effects can never
/// be selected through the device-mode path. Callers must treat `null` as an
/// explicit unknown-effect failure — there is no default fallback, by design.
EffectDefinition? effectByCommandName(String? commandName) {
  if (commandName == null || commandName.isEmpty) return null;
  for (final effect in kMrStarEffects) {
    if (effect.commandName == commandName) return effect;
  }
  return null;
}

/// Convenience: the device-pattern effect with the given [protocolModeId].
EffectDefinition? effectByModeId(int? modeId) {
  if (modeId == null) return null;
  for (final effect in kMrStarEffects) {
    if (effect.protocolModeId == modeId) return effect;
  }
  return null;
}
