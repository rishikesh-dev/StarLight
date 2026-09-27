import 'package:test/test.dart';
import 'package:starlight/core/ble/protocol_encoder.dart';
import 'package:starlight/core/utils/color_conversion.dart';
import 'package:starlight/core/utils/hex_utils.dart';

void main() {
  group('ProtocolEncoder', () {
    test('powerOn produces correct packet', () {
      final bytes = ProtocolEncoder.powerOn();
      expect(HexUtils.toHexString(bytes), equals('BC 01 01 00 55'));
    });

    test('powerOff produces correct packet', () {
      final bytes = ProtocolEncoder.powerOff();
      expect(HexUtils.toHexString(bytes), equals('BC 01 01 01 55'));
    });

    test('brightness clamps minimum to 3', () {
      final bytes = ProtocolEncoder.brightness(0);
      expect(HexUtils.toHexString(bytes), equals('BC 05 06 00 03 00 00 00 00 55'));
    });

    test('brightness at 1000 produces correct packet', () {
      final bytes = ProtocolEncoder.brightness(1000);
      expect(HexUtils.toHexString(bytes), equals('BC 05 06 03 E8 00 00 00 00 55'));
    });

    test('colorFromRGB red produces hue=0 saturation=1000', () {
      final bytes = ProtocolEncoder.colorFromRGB(255, 0, 0);
      expect(HexUtils.toHexString(bytes), equals('BC 04 06 00 00 03 E8 00 00 55'));
    });

    test('colorFromHSV with hue=0 sat=1000', () {
      final bytes = ProtocolEncoder.colorFromHSV(0, 1000);
      expect(HexUtils.toHexString(bytes), equals('BC 04 06 00 00 03 E8 00 00 55'));
    });

    test('setLedCount produces correct packet', () {
      final bytes = ProtocolEncoder.setLedCount(300);
      expect(HexUtils.toHexString(bytes), equals('BC 03 02 01 2C 55'));
    });

    test('setLineOrder produces correct packet', () {
      final bytes = ProtocolEncoder.setLineOrder(2);
      expect(HexUtils.toHexString(bytes), equals('BC 02 01 02 55'));
    });

    test('setSpeed produces correct packet', () {
      final bytes = ProtocolEncoder.setSpeed(128);
      expect(HexUtils.toHexString(bytes), equals('BC 08 01 80 55'));
    });

    test('micToggle on produces correct packet', () {
      final bytes = ProtocolEncoder.micToggle(true);
      expect(HexUtils.toHexString(bytes), equals('BC 0F 01 01 55'));
    });

    test('micToggle off produces correct packet', () {
      final bytes = ProtocolEncoder.micToggle(false);
      expect(HexUtils.toHexString(bytes), equals('BC 0F 01 00 55'));
    });

    test('setColorPicker up produces correct packet', () {
      final bytes = ProtocolEncoder.setColorPicker(true);
      expect(HexUtils.toHexString(bytes), equals('BC 07 01 01 55'));
    });
  });

  group('ColorConversion', () {
    test('red converts to hue=0, saturation=1000', () {
      final (hue, sat) = ColorConversion.computeColorValues(255, 0, 0);
      expect(hue, equals(0));
      expect(sat, equals(1000));
    });

    test('green converts to hue=120, saturation=1000', () {
      final (hue, sat) = ColorConversion.computeColorValues(0, 255, 0);
      expect(hue, equals(120));
      expect(sat, equals(1000));
    });

    test('blue converts to hue=240, saturation=1000', () {
      final (hue, sat) = ColorConversion.computeColorValues(0, 0, 255);
      expect(hue, equals(240));
      expect(sat, equals(1000));
    });

    test('white converts to hue=0, saturation=1000 (forced by e2.e.B fix)', () {
      final (hue, sat) = ColorConversion.computeColorValues(255, 255, 255);
      expect(hue, equals(0));
      expect(sat, equals(1000));
    });

    test('saturation is forced to 1.0 for pure colors', () {
      final hsv = ColorConversion.rgbToHsv(255, 0, 0);
      expect(hsv[1], equals(1.0));
    });
  });

  group('HexUtils', () {
    test('toHexString formats bytes correctly', () {
      expect(HexUtils.toHexString([0xBC, 0x01, 0x01, 0x00, 0x55]), equals('BC 01 01 00 55'));
    });

    test('toHexString handles empty list', () {
      expect(HexUtils.toHexString([]), equals(''));
    });
  });
}