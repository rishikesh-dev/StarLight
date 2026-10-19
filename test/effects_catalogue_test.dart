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

/// The Effects Studio builds on a real, typed contract. These tests pin the
/// invariants that keep it honest *and* keep the mapping single-sourced:
///
/// 1. Every advertised effect has a stable, unique id and a unique canonical
///    protocol mode id — there is one table, not two.
/// 2. Encoding an effect is driven entirely by `protocolModeId`; the encoder
///    owns no name table and never falls back to a default mode.
/// 3. Unknown ids/names/mode ids resolve to `null` rather than a default.
void main() {
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

    test('encoding each effect produces a distinct packet', () {
      final seen = <List<int>>[];
      for (final effect in kMrStarEffects) {
        final encoded = ProtocolEncoder.setMode(effect.protocolModeId!);
        expect(encoded[0], 0xBC);
        expect(encoded[1], 0x06);
        expect(encoded[2], 0x02);
        expect(encoded[3], 0x00);
        expect(encoded[4], effect.protocolModeId!);
        expect(encoded.last, 0x55);
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

    test('covers all four browsing categories', () {
      final categories = kMrStarEffects.map((e) => e.category).toSet();
      expect(categories, containsAll(EffectCategory.values));
    });

    test('declares a schema version', () {
      expect(EffectDefinition.schemaVersion, greaterThanOrEqualTo(1));
    });

    test('speed is declared only for effects that have a speed parameter', () {
      for (final effect in kMrStarEffects) {
        if (effect.category == EffectCategory.static) {
          expect(effect.supportsSpeed, isFalse);
          expect(effect.speedRange, isNull);
        } else {
          expect(effect.supportsSpeed, isTrue);
          expect(effect.speedRange, kMrStarSpeedRange);
        }
      }
    });

    test('lookups find by id, command name and mode id', () {
      expect(effectById('rainbow')?.commandName, 'Rainbow');
      expect(effectById('rainbow')?.protocolModeId, 2);
      expect(effectByCommandName('Rainbow')?.id, 'rainbow');
      expect(effectByModeId(2)?.id, 'rainbow');
    });

    test('unknown id / name / mode id resolve to null (no default)', () {
      expect(effectById('does-not-exist'), isNull);
      expect(effectByCommandName('Nope'), isNull);
      expect(effectByModeId(9999), isNull);
      expect(effectByModeId(null), isNull);
      expect(effectById(null), isNull);
      expect(effectByCommandName(null), isNull);
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
  });
}
