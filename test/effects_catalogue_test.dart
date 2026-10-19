import 'package:flutter_test/flutter_test.dart';
import 'package:starlight/core/ble/protocol_encoder.dart';
import 'package:starlight/domain/entities/device_capability.dart';
import 'package:starlight/domain/entities/effect.dart';

bool _sameBytes(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < b.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// The MR Star controller mode names, transcribed **verbatim** from the
/// decompiled MR Star APK (`res/values/strings.xml`, keys `cmode1` …
/// `cmode117`). Index `n` holds the name of `cmode{n + 1}`.
///
/// This is the golden copy of the source of truth. The catalogue under test
/// must match it exactly — a typo in a mode name is a defect, and a mode
/// that silently disappears from the catalogue is a defect.
const List<String> _expectedMrStarModeNames = <String>[
  'Automatic loop',
  'Symphony',
  'Colorful energy',
  'Colorful jumps',
  'Red-green-blue jumps',
  'Yellow-blue-purple jumps',
  '7 colors strobe',
  'Red-green-blue strobe',
  'Yellow-purple-blue strobe',
  '7 colors gradient',
  'Alternate red-yellow gradient',
  'Alternate red-purple gradient',
  'Green-green alternate gradient',
  'Alternate green-yellow gradient',
  'Blue-purple alternating gradient',
  'Red horse racing',
  'Green horse racing',
  'Blue horse racing',
  'Yellow horse racing',
  'Cyan horse racing',
  'Purple horse racing',
  'White horse racing',
  'Colorful chasing light',
  'Red-green-blue follow-up',
  'Yellow-cyan-purple follow-up light',
  'Colorful fluttering',
  'Red-green-blue fluttering',
  'Yellow-cyan-purple fluttering',
  'Colorful brushing',
  'Red-green-blue color brushing',
  'Yellow-cyan-purple color brushing',
  'Colorful brush color brush closed-pull',
  'Red-green-blue color brush closed-pull',
  'Yellow-cyan-purple color brush closed-pull',
  '7 colors opening-closing',
  'Red-green-blue opening-closing',
  'Yellow-cyan-purple opening-closes',
  'Red opening-closing',
  'Green opening-closing',
  'Blue opening-closing',
  'Yellow opening-closing',
  'Cyan opening-closing',
  'purple opening-closing',
  'White opening-closing',
  '7 colors light-dark transition',
  'Blue-red-green light-dark transition',
  'Violet-green-yellow light-dark transition',
  '6 colors light-dark transition red',
  '6 colors light-dark transition green',
  '6 colors light-dark transition blue',
  '6 colors light-dark transition cyan',
  '6 colors light-dark transition yellow',
  '6 colors light-dark transition purple',
  '6 colors light-dark transition white',
  '7 colors flowing water',
  'Blue-green-red running water',
  'Purple-green-yellow running water',
  'Red-green running water',
  'Green-blue running water',
  'Yellow-blue running water',
  'Yellow-cyan running water',
  'Blue-purple running water',
  'Black-white running water',
  'White-red-white flow',
  'White-green-white flow',
  'White-blue-white flow',
  'White-yellow-white flow',
  'White-green-white flow',
  'White purple-white flow',
  'Red-white-red flow',
  'Green-white-green flow',
  'Blue-white-blue flow',
  'yellow-white-yellow flow',
  'Blue-white-blue flow',
  'Purple-white-purple flow',
  '7 colors trailing',
  'Red trailing',
  'Green trailing',
  'Blue trailing',
  'Yellow trailing',
  'Cyan tailing',
  'Purple tailing',
  'White trailing',
  'Red running',
  'Green running',
  'Blue running',
  'Yellow running',
  'Cyan running',
  'Purple running',
  'White running',
  '7 colors running',
  'Blue-green-red running',
  'Purple-cyan-yellow running',
  'Blue-purple-cyan-yellow running',
  'Blue-green-cyan-yellow running',
  'Red dot on white background running',
  'Red background and green dot running',
  'Green background and blue dot running',
  'Yellow dot on the blue background running',
  'Yellow background and blue dots running',
  'Blue background and purple dots are running',
  'White dots running on purple background',
  'Red background and white dots running',
  '7 colors running with red background',
  '7 colors running with green background',
  '7 colors running with blue background',
  '7 colors yellow background running',
  'Green background 7 colors running',
  '7 colors running with purple background',
  '7 colors running on white background',
  'Blue background and green dot running',
  'Red background and green dot running',
  'Red dot on the blue background running',
  'Yellow background and blue dots running',
  'The yellow dots on the purple bottom running',
  'Yellow background and white dots running',
  'Yellow dots on white background running',
];

/// The four pairs of display names the APK genuinely duplicates. These are
/// distinct controller modes that share a label — the catalogue must keep
/// them apart, not collapse them.
const Map<String, List<int>> _expectedDuplicateNames = <String, List<int>>{
  'White-green-white flow': [65, 68],
  'Blue-white-blue flow': [72, 74],
  'Red background and green dot running': [97, 112],
  'Yellow background and blue dots running': [100, 114],
};

/// The category the catalogue assigns to each mode, restated here as ranges
/// so a change in the production table has to be a deliberate change in this
/// test too.
const Map<EffectCategory, List<int>> _expectedCategories =
    <EffectCategory, List<int>>{
      EffectCategory.ambient: [1, 2, 3],
      EffectCategory.rhythm: [
        4, 5, 6, 7, 8, 9, //
        35, 36, 37, 38, 39, 40, 41, 42, 43, 44,
        45, 46, 47, 48, 49, 50, 51, 52, 53, 54,
      ],
      EffectCategory.static: [10, 11, 12, 13, 14, 15],
      EffectCategory.motion: [
        16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32,
        33, 34, //
        55, 56, 57, 58, 59, 60, 61, 62, 63, 64, 65, 66, 67, 68, 69, 70, 71, 72,
        73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90,
        91, 92, 93, 94, 95, 96, 97, 98, 99, 100, 101, 102, 103, 104, 105, 106,
        107, 108, 109, 110, 111, 112, 113, 114, 115, 116, 117,
      ],
    };

/// The Effects Studio builds on a real, typed contract. These tests pin the
/// invariants that keep it honest *and* keep the mapping single-sourced:
///
/// 1. Every controller mode the MR Star APK declares (`cmode1`…`cmode117`)
///    is present, named verbatim, and mapped to its own protocol mode id.
/// 2. Encoding an effect is driven entirely by `protocolModeId`; the encoder
///    owns no name table and never falls back to a default mode.
/// 3. Unknown ids/names/mode ids resolve to `null` rather than a default.
void main() {
  group('MR Star controller modes (source of truth)', () {
    test(
      'declares exactly 117 controller modes plus the steady-colour entry',
      () {
        final cmodeEffects = kMrStarEffects
            .where((e) => e.id.startsWith('cmode'))
            .toList();
        expect(cmodeEffects.length, 117);
        expect(kMrStarEffects.length, 118);
      },
    );

    test('covers the mode id space 1..117 with no gaps or overlaps', () {
      final modeIds =
          kMrStarEffects.map((e) => e.protocolModeId).toSet().toList()..sort();
      expect(modeIds.length, 118);
      expect(modeIds.first, 0, reason: 'mode 0 is the steady-colour entry');
      expect(modeIds.last, 117);
      for (var id = 0; id <= 117; id++) {
        expect(modeIds, contains(id), reason: 'mode id $id is missing');
      }
    });

    test('maps every mode id onto its own cmode number', () {
      for (var id = 1; id <= 117; id++) {
        final effect = effectByModeId(id);
        expect(effect, isNotNull, reason: 'no effect for mode id $id');
        expect(effect!.protocolModeId, id);
        expect(effect.id, 'cmode$id');
        expect(effect.commandName, 'cmode$id');
        expect(effect.kind, EffectKind.hardwareNative);
        expect(effect.route, EffectExecutionRoute.mrStar);
        expect(effect.requires, contains(DeviceCapability.effect));
        expect(effect.hardwareVerified, isFalse);
      }
    });

    test('names every mode exactly as the APK does', () {
      for (var id = 1; id <= 117; id++) {
        final effect = effectByModeId(id)!;
        expect(
          effect.name,
          _expectedMrStarModeNames[id - 1],
          reason: 'cmode$id name does not match strings.xml',
        );
      }
    });

    test('preserves the APK\'s genuinely duplicated display names', () {
      for (final entry in _expectedDuplicateNames.entries) {
        for (final id in entry.value) {
          final effect = effectByModeId(id)!;
          expect(effect.name, entry.key, reason: 'cmode$id');
        }
      }
      // No other pair of modes may share a display name.
      final byName = <String, List<String>>{};
      for (final effect in kMrStarEffects) {
        byName.putIfAbsent(effect.name, () => <String>[]).add(effect.id);
      }
      final unexpected = byName.entries
          .where((e) => e.value.length > 1)
          .where((e) => !_expectedDuplicateNames.containsKey(e.key));
      expect(unexpected, isEmpty);
    });

    test('gives every mode a unique id and a unique command name', () {
      final ids = kMrStarEffects.map((e) => e.id).toList();
      final commands = kMrStarEffects.map((e) => e.commandName).toList();
      expect(ids.toSet().length, ids.length);
      expect(commands.toSet().length, commands.length);
    });

    test('assigns the source-derived category to every mode', () {
      for (final entry in _expectedCategories.entries) {
        for (final id in entry.value) {
          expect(effectByModeId(id)!.category, entry.key, reason: 'cmode$id');
        }
      }
      final categories = kMrStarEffects.map((e) => e.category).toSet();
      expect(categories, containsAll(EffectCategory.values));
    });

    test('every controller mode exposes the firmware speed range', () {
      for (var id = 1; id <= 117; id++) {
        final effect = effectByModeId(id)!;
        expect(effect.supportsSpeed, isTrue, reason: 'cmode$id');
        expect(effect.speedRange, kMrStarSpeedRange, reason: 'cmode$id');
      }
    });

    test('the steady-colour entry is the only effect without a speed', () {
      final solid = effectByModeId(0)!;
      expect(solid.id, 'solid');
      expect(solid.name, 'Solid');
      expect(solid.category, EffectCategory.static);
      expect(solid.supportsSpeed, isFalse);
      expect(solid.speedRange, isNull);
    });

    test('encodes each mode to the packet the APK would send', () {
      for (var id = 1; id <= 117; id++) {
        final encoded = ProtocolEncoder.setMode(id);
        expect(encoded[0], 0xBC);
        expect(encoded[1], 0x06);
        expect(encoded[2], 0x02);
        expect(encoded[3], 0x00, reason: 'cmode$id');
        expect(encoded[4], id, reason: 'cmode$id');
        expect(encoded.last, 0x55);
      }
    });

    test('encoding each effect produces a distinct packet', () {
      final seen = <List<int>>[];
      for (final effect in kMrStarEffects) {
        final encoded = ProtocolEncoder.setMode(effect.protocolModeId!);
        for (final previous in seen) {
          expect(
            _sameBytes(previous, encoded),
            isFalse,
            reason: 'two effects encoded to the same packet',
          );
        }
        seen.add(encoded);
      }
    });

    test('lookups find a mode by id, command name and mode id', () {
      expect(effectById('cmode65')?.name, 'White-green-white flow');
      expect(effectById('cmode65')?.protocolModeId, 65);
      expect(effectByCommandName('cmode65')?.id, 'cmode65');
      expect(effectByModeId(65)?.id, 'cmode65');
      expect(
        effectById('cmode117')?.name,
        'Yellow dots on white background running',
      );
    });

    test('unknown id / name / mode id resolve to null (no default)', () {
      expect(effectById('does-not-exist'), isNull);
      expect(effectByCommandName('Nope'), isNull);
      expect(effectByModeId(118), isNull);
      expect(effectByModeId(9999), isNull);
      expect(effectByModeId(null), isNull);
      expect(effectById(null), isNull);
      expect(effectByCommandName(null), isNull);
    });
  });

  group('legacy command names (pre-rebuild catalogue)', () {
    test('every legacy name still selects the mode it used to select', () {
      // Recorded truth of the catalogue StarLight shipped before it was
      // rebuilt from the decompiled APK.
      const legacy = <String, int>{
        'Solid': 0,
        'Fireworks': 1,
        'Rainbow': 2,
        'Breath': 3,
        'Scan': 4,
        'Flash': 5,
        'Police': 6,
        'Chase': 7,
        'Comet': 8,
        'Lava': 9,
        'Ocean': 10,
      };
      for (final entry in legacy.entries) {
        final effect = effectByCommandName(entry.key);
        expect(effect, isNotNull, reason: entry.key);
        expect(effect!.protocolModeId, entry.value, reason: entry.key);
        expect(
          _sameBytes(
            ProtocolEncoder.setMode(effect.protocolModeId!),
            ProtocolEncoder.setMode(entry.value),
          ),
          isTrue,
          reason: entry.key,
        );
      }
    });

    test('the legacy table is exactly the ten dropped names', () {
      expect(kLegacyEffectCommandModeIds.length, 10);
      expect(kLegacyEffectCommandModeIds.keys.toSet(), {
        'fireworks',
        'rainbow',
        'breath',
        'scan',
        'flash',
        'police',
        'chase',
        'comet',
        'lava',
        'ocean',
      });
    });

    test('a legacy name never shadows a canonical command name', () {
      final canonical = kMrStarEffects
          .map((e) => e.commandName!.toLowerCase())
          .toSet();
      for (final name in kLegacyEffectCommandModeIds.keys) {
        expect(canonical, isNot(contains(name)), reason: name);
      }
    });

    test('an unknown name is still not guessed at', () {
      expect(effectByCommandName('Symphony'), isNull);
      expect(effectByLegacyCommandName('Symphony'), isNull);
      expect(resolveEffectCommandName('Symphony'), 'Symphony');
    });

    test('persisting a value migrates legacy names and preserves unknowns', () {
      expect(resolveEffectCommandName('Rainbow'), 'cmode2');
      expect(resolveEffectCommandName('cmode65'), 'cmode65');
      expect(resolveEffectCommandName('Solid'), 'Solid');
      expect(resolveEffectCommandName('who knows'), 'who knows');
      expect(resolveEffectCommandName(null), isNull);
      expect(resolveEffectCommandName(''), isNull);
    });
  });

  group('effect catalogue', () {
    test('has unique stable ids and command names', () {
      final ids = kMrStarEffects.map((e) => e.id).toList();
      final commands = kMrStarEffects.map((e) => e.commandName).toList();
      expect(ids.toSet().length, ids.length);
      expect(commands.toSet().length, commands.length);
    });

    test('has unique canonical protocol mode ids', () {
      final modeIds = kMrStarEffects.map((e) => e.protocolModeId).toList();
      expect(
        modeIds.toSet().length,
        modeIds.length,
        reason: 'two effects must not share a protocol mode id',
      );
      for (final effect in kMrStarEffects) {
        expect(effectByModeId(effect.protocolModeId)?.id, effect.id);
      }
    });

    test('every MR Star effect declares the mrStar execution route', () {
      for (final effect in kMrStarEffects) {
        expect(effect.route, EffectExecutionRoute.mrStar);
      }
    });

    test('every effect requires the effect capability', () {
      for (final effect in kMrStarEffects) {
        expect(effect.requires, contains(DeviceCapability.effect));
      }
    });

    test('covers all four browsing categories', () {
      final categories = kMrStarEffects.map((e) => e.category).toSet();
      expect(categories, containsAll(EffectCategory.values));
    });

    test('declares a schema version', () {
      expect(EffectDefinition.schemaVersion, greaterThanOrEqualTo(1));
    });
  });

  group('speed range', () {
    test('contains its boundaries and rejects outside values', () {
      expect(kMrStarSpeedRange.contains(0), isTrue);
      expect(kMrStarSpeedRange.contains(100), isTrue);
      expect(kMrStarSpeedRange.contains(50), isTrue);
      expect(kMrStarSpeedRange.contains(-1), isFalse);
      expect(kMrStarSpeedRange.contains(101), isFalse);
    });
  });

  group('unified catalogue', () {
    test('ids are unique across both kinds', () {
      final ids = kEffectCatalogue.map((e) => e.id).toSet();
      expect(ids.length, kEffectCatalogue.length);
    });

    test('device patterns own a command name and mode id; custom do not', () {
      for (final effect in kMrStarEffects) {
        expect(effect.kind, EffectKind.hardwareNative);
        expect(effect.commandName, isNotNull);
        expect(effect.protocolModeId, isNotNull);
        expect(effect.playback, EffectPlayback.deviceMode);
      }
      for (final effect in kCustomEffects) {
        expect(effect.kind, EffectKind.custom);
        expect(effect.commandName, isNull);
        expect(effect.protocolModeId, isNull);
      }
    });

    test('custom effects are never selectable by command name', () {
      for (final effect in kCustomEffects) {
        expect(effectByCommandName(effect.id), isNull);
        expect(effectByModeId(-1), isNull);
      }
    });

    test('custom effects require colour, not the native effect capability', () {
      for (final effect in kCustomEffects) {
        expect(effect.requires, contains(DeviceCapability.color));
        expect(effect.requires.contains(DeviceCapability.effect), isFalse);
        expect(effect.kind, EffectKind.custom);
      }
    });

    test('playback is classified exactly by kind and addressability', () {
      for (final effect in kCustomEffects) {
        final expected = effect.requiresAddressable
            ? EffectPlayback.previewOnly
            : EffectPlayback.colorSequence;
        expect(effect.playback, expected, reason: effect.id);
        expect(
          effect.supportsPhysicalPlayback,
          !effect.requiresAddressable,
          reason: effect.id,
        );
      }
    });

    test(
      'every custom effect exposes validated speed and intensity ranges',
      () {
        for (final effect in kCustomEffects) {
          expect(effect.speedRange, kEffectSpeedRange, reason: effect.id);
          expect(
            effect.intensityRange,
            kEffectIntensityRange,
            reason: effect.id,
          );
        }
      },
    );

    test('a declared default palette always resolves', () {
      for (final effect in kCustomEffects) {
        if (effect.supportsPalette) {
          expect(
            effect.defaultPaletteId,
            isNotNull,
            reason: '${effect.id} advertises a palette but names no default',
          );
        }
      }
    });

    test('the single catalogue contains both kinds', () {
      expect(
        kEffectCatalogue.where((e) => e.kind == EffectKind.custom),
        isNotEmpty,
      );
      expect(
        kEffectCatalogue.where((e) => e.kind == EffectKind.hardwareNative),
        isNotEmpty,
      );
    });

    test('effectByModeId never resolves a custom effect', () {
      for (final effect in kCustomEffects) {
        expect(effectByModeId(effect.protocolModeId), isNull);
      }
    });

    test('the eight StarLight custom effects are preserved', () {
      expect(kCustomEffects.length, 8);
      expect(kCustomEffects.map((e) => e.id).toSet(), {
        'custom-aurora',
        'custom-ember',
        'custom-ocean-drift',
        'custom-meteor',
        'custom-prism-flow',
        'custom-soft-breath',
        'custom-color-bloom',
        'custom-starlight',
      });
    });
  });
}
