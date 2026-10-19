import 'package:flutter_test/flutter_test.dart';
import 'package:starlight/domain/entities/effect_palette.dart';
import 'package:starlight/domain/entities/rgb_color.dart';

/// The palette rack is pure data plus two colour helpers. These tests pin the
/// behaviour the custom-effect renderers rely on: sampling wraps (so a renderer
/// may pass an unbounded time/position), helpers stay inside 0–255, and a stale
/// persisted id never yields an empty palette.
void main() {
  group('colour helpers', () {
    test('lerpRgb interpolates and clamps', () {
      expect(
        lerpRgb(const RGBColor(0, 0, 0), const RGBColor(255, 255, 255), 0.5),
        const RGBColor(128, 128, 128),
      );
      expect(
        lerpRgb(const RGBColor(10, 20, 30), const RGBColor(200, 200, 200), -1),
        const RGBColor(10, 20, 30),
      );
      expect(
        lerpRgb(const RGBColor(10, 20, 30), const RGBColor(200, 200, 200), 2),
        const RGBColor(200, 200, 200),
      );
    });

    test('scaleRgb multiplies and clamps to a byte', () {
      expect(
        scaleRgb(const RGBColor(100, 200, 255), 0.5),
        const RGBColor(50, 100, 128),
      );
      expect(
        scaleRgb(const RGBColor(100, 200, 255), 0),
        const RGBColor(0, 0, 0),
      );
      expect(
        scaleRgb(const RGBColor(100, 200, 255), 5),
        const RGBColor(100, 200, 255),
      );
    });
  });

  group('EffectPalette.sample', () {
    const ramp = EffectPalette(
      id: 'test',
      name: 'Test',
      colors: [RGBColor(0, 0, 0), RGBColor(255, 255, 255)],
    );

    test('hits exact colours at segment boundaries', () {
      expect(ramp.sample(0.0), const RGBColor(0, 0, 0));
      expect(ramp.sample(0.5), const RGBColor(255, 255, 255));
    });

    test('wraps at and beyond 1.0', () {
      expect(ramp.sample(1.0), const RGBColor(0, 0, 0));
      expect(ramp.sample(1.5), const RGBColor(255, 255, 255));
      expect(ramp.sample(2.0), const RGBColor(0, 0, 0));
    });

    test('wraps negative parameters instead of clamping', () {
      expect(ramp.sample(-1.0), const RGBColor(0, 0, 0));
      expect(ramp.sample(-0.5), const RGBColor(255, 255, 255));
    });

    test('returns the single colour for a one-colour ramp', () {
      const single = EffectPalette(
        id: 's',
        name: 'S',
        colors: [RGBColor(1, 2, 3)],
      );
      expect(single.sample(0.42), const RGBColor(1, 2, 3));
    });

    test('falls back to white for an empty ramp', () {
      const empty = EffectPalette(id: 'e', name: 'E', colors: []);
      expect(empty.sample(0.3), const RGBColor(255, 255, 255));
    });
  });

  group('built-in rack', () {
    test('every palette has a unique id and at least two colours', () {
      final ids = kEffectPalettes.map((p) => p.id).toSet();
      expect(ids.length, kEffectPalettes.length);
      for (final palette in kEffectPalettes) {
        expect(palette.colors.length, greaterThanOrEqualTo(2));
        expect(palette.name, isNotEmpty);
      }
    });

    test('effectPaletteById finds by id and misses to null', () {
      expect(effectPaletteById('aurora')?.name, 'Aurora');
      expect(effectPaletteById('nope'), isNull);
      expect(effectPaletteById(null), isNull);
    });

    test('effectPaletteOrDefault always yields a real palette', () {
      expect(effectPaletteOrDefault('ocean').id, 'ocean');
      expect(effectPaletteOrDefault('missing'), kEffectPalettes.first);
      expect(effectPaletteOrDefault(null), kEffectPalettes.first);
    });
  });
}
