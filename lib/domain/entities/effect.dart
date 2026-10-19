// SPDX-License-Identifier: Apache-2.0

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

import 'device_capability.dart';

/// Groups an [EffectDefinition] for browsing in the Effects Studio.
///
/// Categories are presentation-level groupings only: they carry no protocol
/// meaning and never influence command generation.
enum EffectCategory {
  /// Effects that hold a fixed colour arrangement — a steady colour or a
  /// fixed spatial gradient (e.g. Solid, the MR Star `… gradient` modes).
  static('Static'),

  /// Effects whose pattern travels along the strip (e.g. the MR Star
  /// `horse racing`, `trailing` and `running` modes).
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

/// The MR Star controller mode table, transcribed verbatim from the
/// decompiled MR Star APK (`res/values/strings.xml`, keys `cmode1` …
/// `cmode117`).
///
/// **Protocol convention — verified, not assumed.** The decompiled
/// `ModeFragment.f0(mode)` writes the mode packet
/// `BC 06 02 <mode/255> <mode%255> 55`, and the wheel index arithmetic in
/// `ModeFragment.P` maps every tab straight onto the *cmode number*:
///
/// | APK tab | wheel index → mode id |
/// |---------|-----------------------|
/// | Basic | 0–3 → 1–4, 4 → 7, 5 → 10, 6–7 → 26–27, 8–11 → 29–32 |
/// | Opening & closing | index → index + 35 |
/// | Transition | index → index + 45 |
/// | Running water | index → index + 55 |
/// | Tailing | index → index + 76 |
/// | Running | index → index + 84 |
///
/// Every offset is the first cmode number of its group, so the wire value of
/// a mode **is** its cmode number: `protocolModeId == cmode number` for all
/// modes 1…117. `ProtocolEncoder.setMode` therefore needs no shift and no
/// re-basing of the existing 0–255 byte field.
///
/// **Names are the APK's own**, copied verbatim — including the four pairs of
/// genuinely duplicated display names (`cmode65`/`cmode68`,
/// `cmode72`/`cmode74`, `cmode97`/`cmode112`, `cmode100`/`cmode114`). Those
/// duplicates are preserved: they are distinct controller modes that happen
/// to share a label, not a mapping defect. The per-mode `id`/`commandName`
/// are `cmodeN`, so the disambiguation lives in the id and never in the
/// user-visible name.
///
/// **Categories** are derived from the APK's own grouping and the mode's
/// described behaviour:
///
/// * [EffectCategory.static] — a fixed spatial colour arrangement
///   (the `… gradient` family, `cmode10`–`cmode15`).
/// * [EffectCategory.rhythm] — pulsing or flashing in place (`jumps`,
///   `strobe`, `opening-closing`, `light-dark transition`).
/// * [EffectCategory.motion] — a pattern that travels along the strip
///   (`horse racing`, `chasing`, `flow`, `trailing`, `running`, …).
/// * [EffectCategory.ambient] — the three showcase modes of the Basic tab
///   (`cmode1`–`cmode3`).
class _MrStarModeEntry {
  /// The controller mode id. Equal to the APK's `cmodeN` number.
  final int mode;

  /// The APK's display name for this mode, copied verbatim from
  /// `strings.xml`.
  final String name;

  /// Browsing category, derived from the mode's source group and behaviour.
  final EffectCategory category;

  /// The APK tab/group the mode belongs to, or `null` when the APK declares
  /// the mode in `strings.xml` but exposes it in no tab.
  final String? group;

  const _MrStarModeEntry(this.mode, this.name, this.category, this.group);
}

/// The full `cmode1`…`cmode117` table, in APK order.
const List<_MrStarModeEntry> _kMrStarModeTable = <_MrStarModeEntry>[
  _MrStarModeEntry(1, 'Automatic loop', EffectCategory.ambient, 'Basic'),
  _MrStarModeEntry(2, 'Symphony', EffectCategory.ambient, 'Basic'),
  _MrStarModeEntry(3, 'Colorful energy', EffectCategory.ambient, 'Basic'),
  _MrStarModeEntry(4, 'Colorful jumps', EffectCategory.rhythm, 'Basic'),
  _MrStarModeEntry(5, 'Red-green-blue jumps', EffectCategory.rhythm, null),
  _MrStarModeEntry(6, 'Yellow-blue-purple jumps', EffectCategory.rhythm, null),
  _MrStarModeEntry(7, '7 colors strobe', EffectCategory.rhythm, 'Basic'),
  _MrStarModeEntry(8, 'Red-green-blue strobe', EffectCategory.rhythm, null),
  _MrStarModeEntry(9, 'Yellow-purple-blue strobe', EffectCategory.rhythm, null),
  _MrStarModeEntry(10, '7 colors gradient', EffectCategory.static, 'Basic'),
  _MrStarModeEntry(
    11,
    'Alternate red-yellow gradient',
    EffectCategory.static,
    null,
  ),
  _MrStarModeEntry(
    12,
    'Alternate red-purple gradient',
    EffectCategory.static,
    null,
  ),
  _MrStarModeEntry(
    13,
    'Green-green alternate gradient',
    EffectCategory.static,
    null,
  ),
  _MrStarModeEntry(
    14,
    'Alternate green-yellow gradient',
    EffectCategory.static,
    null,
  ),
  _MrStarModeEntry(
    15,
    'Blue-purple alternating gradient',
    EffectCategory.static,
    null,
  ),
  _MrStarModeEntry(16, 'Red horse racing', EffectCategory.motion, null),
  _MrStarModeEntry(17, 'Green horse racing', EffectCategory.motion, null),
  _MrStarModeEntry(18, 'Blue horse racing', EffectCategory.motion, null),
  _MrStarModeEntry(19, 'Yellow horse racing', EffectCategory.motion, null),
  _MrStarModeEntry(20, 'Cyan horse racing', EffectCategory.motion, null),
  _MrStarModeEntry(21, 'Purple horse racing', EffectCategory.motion, null),
  _MrStarModeEntry(22, 'White horse racing', EffectCategory.motion, null),
  _MrStarModeEntry(23, 'Colorful chasing light', EffectCategory.motion, null),
  _MrStarModeEntry(24, 'Red-green-blue follow-up', EffectCategory.motion, null),
  _MrStarModeEntry(
    25,
    'Yellow-cyan-purple follow-up light',
    EffectCategory.motion,
    null,
  ),
  _MrStarModeEntry(26, 'Colorful fluttering', EffectCategory.motion, 'Basic'),
  _MrStarModeEntry(
    27,
    'Red-green-blue fluttering',
    EffectCategory.motion,
    'Basic',
  ),
  _MrStarModeEntry(
    28,
    'Yellow-cyan-purple fluttering',
    EffectCategory.motion,
    null,
  ),
  _MrStarModeEntry(29, 'Colorful brushing', EffectCategory.motion, 'Basic'),
  _MrStarModeEntry(
    30,
    'Red-green-blue color brushing',
    EffectCategory.motion,
    'Basic',
  ),
  _MrStarModeEntry(
    31,
    'Yellow-cyan-purple color brushing',
    EffectCategory.motion,
    'Basic',
  ),
  _MrStarModeEntry(
    32,
    'Colorful brush color brush closed-pull',
    EffectCategory.motion,
    'Basic',
  ),
  _MrStarModeEntry(
    33,
    'Red-green-blue color brush closed-pull',
    EffectCategory.motion,
    null,
  ),
  _MrStarModeEntry(
    34,
    'Yellow-cyan-purple color brush closed-pull',
    EffectCategory.motion,
    null,
  ),
  _MrStarModeEntry(
    35,
    '7 colors opening-closing',
    EffectCategory.rhythm,
    'Opening & closing',
  ),
  _MrStarModeEntry(
    36,
    'Red-green-blue opening-closing',
    EffectCategory.rhythm,
    'Opening & closing',
  ),
  _MrStarModeEntry(
    37,
    'Yellow-cyan-purple opening-closes',
    EffectCategory.rhythm,
    'Opening & closing',
  ),
  _MrStarModeEntry(
    38,
    'Red opening-closing',
    EffectCategory.rhythm,
    'Opening & closing',
  ),
  _MrStarModeEntry(
    39,
    'Green opening-closing',
    EffectCategory.rhythm,
    'Opening & closing',
  ),
  _MrStarModeEntry(
    40,
    'Blue opening-closing',
    EffectCategory.rhythm,
    'Opening & closing',
  ),
  _MrStarModeEntry(
    41,
    'Yellow opening-closing',
    EffectCategory.rhythm,
    'Opening & closing',
  ),
  _MrStarModeEntry(
    42,
    'Cyan opening-closing',
    EffectCategory.rhythm,
    'Opening & closing',
  ),
  _MrStarModeEntry(
    43,
    'purple opening-closing',
    EffectCategory.rhythm,
    'Opening & closing',
  ),
  _MrStarModeEntry(
    44,
    'White opening-closing',
    EffectCategory.rhythm,
    'Opening & closing',
  ),
  _MrStarModeEntry(
    45,
    '7 colors light-dark transition',
    EffectCategory.rhythm,
    'Transition',
  ),
  _MrStarModeEntry(
    46,
    'Blue-red-green light-dark transition',
    EffectCategory.rhythm,
    'Transition',
  ),
  _MrStarModeEntry(
    47,
    'Violet-green-yellow light-dark transition',
    EffectCategory.rhythm,
    'Transition',
  ),
  _MrStarModeEntry(
    48,
    '6 colors light-dark transition red',
    EffectCategory.rhythm,
    'Transition',
  ),
  _MrStarModeEntry(
    49,
    '6 colors light-dark transition green',
    EffectCategory.rhythm,
    'Transition',
  ),
  _MrStarModeEntry(
    50,
    '6 colors light-dark transition blue',
    EffectCategory.rhythm,
    'Transition',
  ),
  _MrStarModeEntry(
    51,
    '6 colors light-dark transition cyan',
    EffectCategory.rhythm,
    'Transition',
  ),
  _MrStarModeEntry(
    52,
    '6 colors light-dark transition yellow',
    EffectCategory.rhythm,
    'Transition',
  ),
  _MrStarModeEntry(
    53,
    '6 colors light-dark transition purple',
    EffectCategory.rhythm,
    'Transition',
  ),
  _MrStarModeEntry(
    54,
    '6 colors light-dark transition white',
    EffectCategory.rhythm,
    'Transition',
  ),
  _MrStarModeEntry(
    55,
    '7 colors flowing water',
    EffectCategory.motion,
    'Running water',
  ),
  _MrStarModeEntry(
    56,
    'Blue-green-red running water',
    EffectCategory.motion,
    'Running water',
  ),
  _MrStarModeEntry(
    57,
    'Purple-green-yellow running water',
    EffectCategory.motion,
    'Running water',
  ),
  _MrStarModeEntry(
    58,
    'Red-green running water',
    EffectCategory.motion,
    'Running water',
  ),
  _MrStarModeEntry(
    59,
    'Green-blue running water',
    EffectCategory.motion,
    'Running water',
  ),
  _MrStarModeEntry(
    60,
    'Yellow-blue running water',
    EffectCategory.motion,
    'Running water',
  ),
  _MrStarModeEntry(
    61,
    'Yellow-cyan running water',
    EffectCategory.motion,
    'Running water',
  ),
  _MrStarModeEntry(
    62,
    'Blue-purple running water',
    EffectCategory.motion,
    'Running water',
  ),
  _MrStarModeEntry(
    63,
    'Black-white running water',
    EffectCategory.motion,
    'Flow',
  ),
  _MrStarModeEntry(64, 'White-red-white flow', EffectCategory.motion, 'Flow'),
  _MrStarModeEntry(65, 'White-green-white flow', EffectCategory.motion, 'Flow'),
  _MrStarModeEntry(66, 'White-blue-white flow', EffectCategory.motion, 'Flow'),
  _MrStarModeEntry(
    67,
    'White-yellow-white flow',
    EffectCategory.motion,
    'Flow',
  ),
  _MrStarModeEntry(68, 'White-green-white flow', EffectCategory.motion, 'Flow'),
  _MrStarModeEntry(
    69,
    'White purple-white flow',
    EffectCategory.motion,
    'Flow',
  ),
  _MrStarModeEntry(70, 'Red-white-red flow', EffectCategory.motion, 'Flow'),
  _MrStarModeEntry(71, 'Green-white-green flow', EffectCategory.motion, 'Flow'),
  _MrStarModeEntry(72, 'Blue-white-blue flow', EffectCategory.motion, 'Flow'),
  _MrStarModeEntry(
    73,
    'yellow-white-yellow flow',
    EffectCategory.motion,
    'Flow',
  ),
  _MrStarModeEntry(74, 'Blue-white-blue flow', EffectCategory.motion, 'Flow'),
  _MrStarModeEntry(
    75,
    'Purple-white-purple flow',
    EffectCategory.motion,
    'Flow',
  ),
  _MrStarModeEntry(76, '7 colors trailing', EffectCategory.motion, 'Tailing'),
  _MrStarModeEntry(77, 'Red trailing', EffectCategory.motion, 'Tailing'),
  _MrStarModeEntry(78, 'Green trailing', EffectCategory.motion, 'Tailing'),
  _MrStarModeEntry(79, 'Blue trailing', EffectCategory.motion, 'Tailing'),
  _MrStarModeEntry(80, 'Yellow trailing', EffectCategory.motion, 'Tailing'),
  _MrStarModeEntry(81, 'Cyan tailing', EffectCategory.motion, 'Tailing'),
  _MrStarModeEntry(82, 'Purple tailing', EffectCategory.motion, 'Tailing'),
  _MrStarModeEntry(83, 'White trailing', EffectCategory.motion, 'Tailing'),
  _MrStarModeEntry(84, 'Red running', EffectCategory.motion, 'Running'),
  _MrStarModeEntry(85, 'Green running', EffectCategory.motion, 'Running'),
  _MrStarModeEntry(86, 'Blue running', EffectCategory.motion, 'Running'),
  _MrStarModeEntry(87, 'Yellow running', EffectCategory.motion, 'Running'),
  _MrStarModeEntry(88, 'Cyan running', EffectCategory.motion, 'Running'),
  _MrStarModeEntry(89, 'Purple running', EffectCategory.motion, 'Running'),
  _MrStarModeEntry(90, 'White running', EffectCategory.motion, 'Running'),
  _MrStarModeEntry(91, '7 colors running', EffectCategory.motion, 'Running'),
  _MrStarModeEntry(
    92,
    'Blue-green-red running',
    EffectCategory.motion,
    'Running',
  ),
  _MrStarModeEntry(
    93,
    'Purple-cyan-yellow running',
    EffectCategory.motion,
    'Running',
  ),
  _MrStarModeEntry(
    94,
    'Blue-purple-cyan-yellow running',
    EffectCategory.motion,
    null,
  ),
  _MrStarModeEntry(
    95,
    'Blue-green-cyan-yellow running',
    EffectCategory.motion,
    null,
  ),
  _MrStarModeEntry(
    96,
    'Red dot on white background running',
    EffectCategory.motion,
    null,
  ),
  _MrStarModeEntry(
    97,
    'Red background and green dot running',
    EffectCategory.motion,
    null,
  ),
  _MrStarModeEntry(
    98,
    'Green background and blue dot running',
    EffectCategory.motion,
    null,
  ),
  _MrStarModeEntry(
    99,
    'Yellow dot on the blue background running',
    EffectCategory.motion,
    null,
  ),
  _MrStarModeEntry(
    100,
    'Yellow background and blue dots running',
    EffectCategory.motion,
    null,
  ),
  _MrStarModeEntry(
    101,
    'Blue background and purple dots are running',
    EffectCategory.motion,
    null,
  ),
  _MrStarModeEntry(
    102,
    'White dots running on purple background',
    EffectCategory.motion,
    null,
  ),
  _MrStarModeEntry(
    103,
    'Red background and white dots running',
    EffectCategory.motion,
    null,
  ),
  _MrStarModeEntry(
    104,
    '7 colors running with red background',
    EffectCategory.motion,
    null,
  ),
  _MrStarModeEntry(
    105,
    '7 colors running with green background',
    EffectCategory.motion,
    null,
  ),
  _MrStarModeEntry(
    106,
    '7 colors running with blue background',
    EffectCategory.motion,
    null,
  ),
  _MrStarModeEntry(
    107,
    '7 colors yellow background running',
    EffectCategory.motion,
    null,
  ),
  _MrStarModeEntry(
    108,
    'Green background 7 colors running',
    EffectCategory.motion,
    null,
  ),
  _MrStarModeEntry(
    109,
    '7 colors running with purple background',
    EffectCategory.motion,
    null,
  ),
  _MrStarModeEntry(
    110,
    '7 colors running on white background',
    EffectCategory.motion,
    null,
  ),
  _MrStarModeEntry(
    111,
    'Blue background and green dot running',
    EffectCategory.motion,
    null,
  ),
  _MrStarModeEntry(
    112,
    'Red background and green dot running',
    EffectCategory.motion,
    null,
  ),
  _MrStarModeEntry(
    113,
    'Red dot on the blue background running',
    EffectCategory.motion,
    null,
  ),
  _MrStarModeEntry(
    114,
    'Yellow background and blue dots running',
    EffectCategory.motion,
    null,
  ),
  _MrStarModeEntry(
    115,
    'The yellow dots on the purple bottom running',
    EffectCategory.motion,
    null,
  ),
  _MrStarModeEntry(
    116,
    'Yellow background and white dots running',
    EffectCategory.motion,
    null,
  ),
  _MrStarModeEntry(
    117,
    'Yellow dots on white background running',
    EffectCategory.motion,
    null,
  ),
];

/// The built-in catalogue of device-native effects for the MR Star protocol.
///
/// Every entry owns its display metadata *and* its canonical protocol command
/// ([EffectDefinition.protocolModeId]). Every encode site resolves through
/// [effectByCommandName] / [effectById] and `ProtocolEncoder.setMode`, so
/// there is exactly one mapping to keep correct.
///
/// The mode ids come from the decompiled controller APK and are **not
/// verified against hardware**; the Effects Studio therefore describes these
/// as device-native controller modes whose exact pattern depends on firmware.
/// [EffectDefinition.hardwareVerified] is false for all entries — a
/// successful write only means the mode packet was accepted, not that the
/// visual pattern matches the name.
final List<EffectDefinition> kMrStarEffects = <EffectDefinition>[
  EffectDefinition(
    id: 'solid',
    name: 'Solid',
    commandName: 'Solid',
    protocolModeId: 0,
    description:
        'Steady light in the current colour. Mode 0 is not part of the '
        "APK's cmode1…cmode117 table — it is StarLight's steady-colour "
        'entry and the only catalogue effect without a speed parameter.',
    category: EffectCategory.static,
    speedRange: null,
    hardwareVerified: false,
  ),
  for (final entry in _kMrStarModeTable)
    EffectDefinition(
      id: 'cmode${entry.mode}',
      name: entry.name,
      commandName: 'cmode${entry.mode}',
      protocolModeId: entry.mode,
      description: entry.group == null
          ? 'MR Star firmware mode ${entry.mode} (cmode${entry.mode}).'
          : 'MR Star firmware mode ${entry.mode} (cmode${entry.mode}) — '
                '${entry.group}.',
      category: entry.category,
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
final List<EffectDefinition> kEffectCatalogue = <EffectDefinition>[
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

/// Command names from the pre-canonical catalogue — the one StarLight shipped
/// before the catalogue was rebuilt from the decompiled MR Star APK — mapped
/// to the controller mode id each of them selected on the wire.
///
/// **Why a mode id and not a name.** Those legacy names were never in the
/// firmware; they were StarLight's own labels for a mode number. A legacy
/// scene that says `Rainbow` was sending mode 2, and mode 2 is `Symphony` in
/// the real controller — so the *label* was wrong and the *packet* was not.
/// The mode id is the only unambiguous thing about a legacy name, and
/// resolving it there keeps the device doing exactly what it did before the
/// catalogue was corrected.
///
/// The table is finite, complete and case-insensitive on lookup. `Solid` is
/// deliberately absent: it is still a canonical command name (mode 0), so it
/// resolves through the normal path. Anything not in this table stays
/// unresolved and is reported as unsupported — it is never guessed at and
/// never silently replaced by a different effect.
const Map<String, int> kLegacyEffectCommandModeIds = <String, int>{
  'fireworks': 1,
  'rainbow': 2,
  'breath': 3,
  'scan': 4,
  'flash': 5,
  'police': 6,
  'chase': 7,
  'comet': 8,
  'lava': 9,
  'ocean': 10,
};

/// The effect a legacy (pre-canonical) command name refers to, or `null`.
///
/// See [kLegacyEffectCommandModeIds] for what a legacy name means and why it
/// resolves to a mode id. A `null` result means the value is not a known
/// effect at all — callers must treat that as an explicit unknown-effect
/// failure.
EffectDefinition? effectByLegacyCommandName(String? commandName) {
  if (commandName == null || commandName.isEmpty) return null;
  final modeId = kLegacyEffectCommandModeIds[commandName.toLowerCase()];
  if (modeId == null) return null;
  return effectByModeId(modeId);
}

/// Convenience: the device-pattern effect whose
/// [EffectDefinition.commandName] equals [commandName], or `null` when unknown.
///
/// Only hardware-native effects have a command name, so custom effects can never
/// be selected through the device-mode path.
///
/// A command name from the pre-canonical catalogue resolves to the effect that
/// selects the same controller mode, so data saved before the catalogue was
/// rebuilt keeps driving the device exactly as it did. Callers must treat
/// `null` as an explicit unknown-effect failure — there is no default
/// fallback, by design.
EffectDefinition? effectByCommandName(String? commandName) {
  if (commandName == null || commandName.isEmpty) return null;
  for (final effect in kMrStarEffects) {
    if (effect.commandName == commandName) return effect;
  }
  return effectByLegacyCommandName(commandName);
}

/// The command name to persist for a stored effect value.
///
/// * A canonical command name is kept as it is.
/// * A legacy name (from before the catalogue was rebuilt) is migrated to the
///   canonical command for the mode it always selected, so the device keeps
///   doing exactly what it did.
/// * Any other value is **preserved verbatim**. It is never replaced by a
///   different effect: an unknown value stays unknown, and the device
///   rejects it explicitly when the scene runs.
String? resolveEffectCommandName(String? storedValue) {
  if (storedValue == null || storedValue.isEmpty) return null;
  final effect = effectByCommandName(storedValue);
  if (effect == null) return storedValue;
  return effect.commandName;
}

/// Convenience: the device-pattern effect with the given [protocolModeId].
EffectDefinition? effectByModeId(int? modeId) {
  if (modeId == null) return null;
  for (final effect in kMrStarEffects) {
    if (effect.protocolModeId == modeId) return effect;
  }
  return null;
}
