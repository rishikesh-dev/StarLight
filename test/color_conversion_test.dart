import 'package:test/test.dart';
import 'package:starlight/core/utils/color_conversion.dart';
import 'package:starlight/domain/entities/rgb_color.dart';

void main() {
  group('ColorConversion exact HSV matching e2.e.B()', () {
    test('red (255,0,0) -> hue=0, sat=1000', () {
      final (hue, sat) = ColorConversion.computeColorValues(255, 0, 0);
      expect(hue, equals(0));
      expect(sat, equals(1000));
    });

    test('green (0,255,0) -> hue=120, sat=1000', () {
      final (hue, sat) = ColorConversion.computeColorValues(0, 255, 0);
      expect(hue, equals(120));
      expect(sat, equals(1000));
    });

    test('blue (0,0,255) -> hue=240, sat=1000', () {
      final (hue, sat) = ColorConversion.computeColorValues(0, 0, 255);
      expect(hue, equals(240));
      expect(sat, equals(1000));
    });

    test('yellow (255,255,0) -> hue=60, sat=1000', () {
      final (hue, sat) = ColorConversion.computeColorValues(255, 255, 0);
      expect(hue, equals(60));
      expect(sat, equals(1000));
    });

    test('cyan (0,255,255) -> hue=180, sat=1000', () {
      final (hue, sat) = ColorConversion.computeColorValues(0, 255, 255);
      expect(hue, equals(180));
      expect(sat, equals(1000));
    });

    test('purple (255,0,255) -> hue=300, sat=1000', () {
      final (hue, sat) = ColorConversion.computeColorValues(255, 0, 255);
      expect(hue, equals(300));
      expect(sat, equals(1000));
    });

    test('white (255,255,255) -> hue=0, sat=0 (sat forced to 1.0)', () {
      final hsv = ColorConversion.rgbToHsv(255, 255, 255);
      expect(hsv[0], equals(0));
      expect(hsv[1], equals(1.0)); // forced by saturation fix
    });

    test('black (0,0,0) -> hue=0, sat=0 (sat forced to 1.0)', () {
      final hsv = ColorConversion.rgbToHsv(0, 0, 0);
      expect(hsv[0], equals(0));
      expect(hsv[1], equals(1.0)); // forced by saturation fix
    });

    test('warm white (255,245,228) -> hue near 40, sat near 0.106', () {
      final hsv = ColorConversion.rgbToHsv(255, 245, 228);
      expect(hsv[0], closeTo(37.78, 3));
      expect(hsv[1], closeTo(0.106, 0.01));
    });

    test('RGBColor.toHexInt roundtrip', () {
      final color = RGBColor(255, 128, 0);
      expect(color.toHexInt(), equals(0xFF8000));
    });

    test('RGBColor.fromHex roundtrip', () {
      final color = RGBColor.fromHex(0xFF5733);
      expect(color.red, equals(255));
      expect(color.green, equals(87));
      expect(color.blue, equals(51));
    });

    test('RGBColor.toHexStr format', () {
      final color = RGBColor(255, 0, 0);
      expect(color.toHexStr(), equals('#FF0000'));
    });
  });
}
