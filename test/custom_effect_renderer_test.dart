import 'package:flutter_test/flutter_test.dart';
import 'package:starlight/domain/entities/effect.dart';
import 'package:starlight/domain/entities/effect_palette.dart';
import 'package:starlight/domain/services/custom_effect_renderer.dart';

CustomEffectInput _input({
  double time = 0,
  int pixels = 16,
  double speed = 0.5,
  double intensity = 1.0,
  EffectPalette? palette,
  int seed = 7,
}) => CustomEffectInput(
  time: time,
  pixels: pixels,
  speed: speed,
  intensity: intensity,
  palette: palette ?? kEffectPalettes.first,
  seed: seed,
);

/// The custom-effect engine is StarLight's own code, so it must be verifiably
/// deterministic and bounded. A renderer that leaked time from `DateTime.now()`,
/// produced out-of-range channels, or crashed on an edge-case parameter would
/// make the preview lie or the player misbehave.
void main() {
  group('renderer registry', () {
    test('is in exact 1:1 correspondence with the custom catalogue', () {
      final rendererIds = kCustomEffectRenderers.keys.toSet();
      final customIds = kCustomEffects.map((e) => e.id).toSet();
      expect(rendererIds, customIds);
    });

    test('never contains a device-native id', () {
      for (final effect in kMrStarEffects) {
        expect(
          kCustomEffectRenderers.containsKey(effect.id),
          isFalse,
          reason: '${effect.id} is a device pattern and must not be rendered',
        );
      }
    });

    test('renderCustomEffect resolves by id and misses to null', () {
      expect(renderCustomEffect('custom-aurora', _input()), isNotNull);
      expect(renderCustomEffect('does-not-exist', _input()), isNull);
      expect(renderCustomEffect('', _input()), isNull);
    });
  });

  group('determinism', () {
    test('identical inputs produce identical samples', () {
      for (final entry in kCustomEffectRenderers.entries) {
        final input = _input(time: 3.25, pixels: 24, speed: 0.6, seed: 99);
        final first = entry.value(input);
        final second = entry.value(input);
        expect(first, second, reason: '${entry.key} is not deterministic');
      }
    });

    test('seed changes the output of the stochastic effect', () {
      final ember = kCustomEffectRenderers['custom-ember']!;
      final a = ember(_input(time: 1, seed: 1));
      final b = ember(_input(time: 1, seed: 2));
      expect(a, isNot(b));
    });

    test('animated effects evolve over time', () {
      final aurora = kCustomEffectRenderers['custom-aurora']!;
      final a = aurora(_input(time: 0));
      final b = aurora(_input(time: 5));
      expect(a, isNot(b));
    });
  });

  group('bounded output', () {
    const times = [0.0, 0.13, 1.7, 9.4, 123.6];
    const speeds = [0.0, 0.5, 1.0];
    const intensities = [0.0, 0.5, 1.0];

    test('every channel stays a valid byte and pixel count is honoured', () {
      for (final entry in kCustomEffectRenderers.entries) {
        for (final t in times) {
          for (final speed in speeds) {
            for (final intensity in intensities) {
              final sample = entry.value(
                _input(time: t, pixels: 19, speed: speed, intensity: intensity),
              );
              expect(
                sample.pixels.length,
                19,
                reason: '${entry.key} produced the wrong pixel count',
              );
              for (final c in [...sample.pixels, sample.global]) {
                expect(c.red, inInclusiveRange(0, 255), reason: entry.key);
                expect(c.green, inInclusiveRange(0, 255), reason: entry.key);
                expect(c.blue, inInclusiveRange(0, 255), reason: entry.key);
              }
            }
          }
        }
      }
    });

    test('a zero pixel request still yields a single segment', () {
      for (final entry in kCustomEffectRenderers.entries) {
        final sample = entry.value(_input(pixels: 0));
        expect(
          sample.pixels.length,
          1,
          reason: '${entry.key} must never return an empty strip',
        );
      }
    });

    test('intensity 0 darkens the strip', () {
      for (final entry in kCustomEffectRenderers.entries) {
        final sample = entry.value(_input(intensity: 0, time: 2.5));
        final bright = sample.pixels.fold<int>(
          0,
          (sum, c) => sum + c.red + c.green + c.blue,
        );
        expect(bright, lessThan(30), reason: '${entry.key} leaked light');
      }
    });

    test('every effect produces some visible light at full intensity', () {
      for (final entry in kCustomEffectRenderers.entries) {
        final sample = entry.value(_input(time: 4.2, intensity: 1));
        final global = sample.global;
        expect(
          global.red + global.green + global.blue,
          greaterThan(0),
          reason: '${entry.key} produced a black representative colour',
        );
      }
    });
  });

  group('CustomEffectInput', () {
    test('copyWith replaces only the provided fields', () {
      final base = _input(time: 1, pixels: 8, speed: 0.2, seed: 5);
      final copy = base.copyWith(time: 2, pixels: 12);
      expect(copy.time, 2);
      expect(copy.pixels, 12);
      expect(copy.speed, 0.2);
      expect(copy.seed, 5);
      expect(copy.palette, base.palette);
    });
  });

  group('sample equality', () {
    test('a rendered sample is Equatable for replay assertions', () {
      final sample = renderCustomEffect('custom-soft-breath', _input())!;
      expect(sample, renderCustomEffect('custom-soft-breath', _input())!);
      expect(sample.pixels, isNotEmpty);
    });
  });
}
