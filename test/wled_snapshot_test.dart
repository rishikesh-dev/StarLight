import 'package:flutter_test/flutter_test.dart';
import 'package:starlight/data/models/wled_snapshot.dart';
import 'package:starlight/domain/entities/device_capability.dart';
import 'package:starlight/domain/entities/rgb_color.dart';

void main() {
  group('WledLightState.fromJson (segment-based / 0.14+)', () {
    test('parses on, brightness, color, fx, sx, pal, cct', () {
      const json = {
        'on': true,
        'bri': 200,
        'seg': [
          {
            'id': 0,
            'col': [
              [10, 20, 30, 40],
              [0, 0, 0, 0],
            ],
            'fx': 7,
            'sx': 120,
            'pal': 3,
            'cct': 90,
            'sel': true,
          },
        ],
      };
      final state = WledLightState.fromJson(json);
      expect(state.on, isTrue);
      expect(state.brightness, 200);
      // 4th channel (white) is dropped; only RGB is exposed.
      expect(state.color, const RGBColor(10, 20, 30));
      expect(state.effectId, 7);
      expect(state.speed, 120);
      expect(state.paletteId, 3);
      expect(state.colorTemperature, 90);
      expect(state.segmentBased, isTrue);
    });

    test('accepts seg as a single object (not array)', () {
      const json = {
        'on': false,
        'bri': 50,
        'seg': {
          'col': [
            [255, 0, 255],
          ],
          'fx': 1,
        },
      };
      final state = WledLightState.fromJson(json);
      expect(state.segmentBased, isTrue);
      expect(state.color, const RGBColor(255, 0, 255));
      expect(state.effectId, 1);
    });
  });

  group('WledLightState.fromJson (legacy flat)', () {
    test('parses on, bri, c, fx, sx', () {
      const json = {
        'on': true,
        'bri': 128,
        'c': [1, 128, 0],
        'fx': 2,
        'sx': 128,
      };
      final state = WledLightState.fromJson(json);
      expect(state.on, isTrue);
      expect(state.brightness, 128);
      expect(state.color, const RGBColor(1, 128, 0));
      expect(state.effectId, 2);
      expect(state.speed, 128);
      expect(state.paletteId, isNull);
      expect(state.colorTemperature, isNull);
      expect(state.segmentBased, isFalse);
    });

    test('handles missing optional fields gracefully', () {
      const json = {'on': false, 'bri': 0};
      final state = WledLightState.fromJson(json);
      expect(state.on, isFalse);
      expect(state.brightness, 0);
      expect(state.color, isNull);
      expect(state.effectId, isNull);
      expect(state.speed, isNull);
      expect(state.segmentBased, isFalse);
    });
  });

  group('WledInfo.fromJson', () {
    test('parses version, name, mac, leds', () {
      const json = {
        'ver': '0.14.4',
        'name': 'WLED-ABCD',
        'mac': 'aabbccddeeff',
        'fxcount': 256,
        'palcount': 64,
        'leds': {'count': 60, 'lc': 7},
      };
      final info = WledInfo.fromJson(json);
      expect(info.version, '0.14.4');
      expect(info.name, 'WLED-ABCD');
      expect(info.mac, 'aabbccddeeff');
      expect(info.ledCount, 60);
      expect(info.effectCount, 256);
      expect(info.paletteCount, 64);
      expect(info.lightCapabilities, 7);
    });

    test('legacy firmware without leds.lc', () {
      const json = {
        'ver': '0.12.0',
        'leds': {'count': 30},
      };
      final info = WledInfo.fromJson(json);
      expect(info.version, '0.12.0');
      expect(info.ledCount, 30);
      expect(info.lightCapabilities, isNull);
      expect(info.mac, isNull);
    });
  });

  group('WledSnapshot.fromJson', () {
    test('parses combined /json response (current keys)', () {
      const json = {
        'state': {
          'on': true,
          'bri': 100,
          'c': [1, 2, 3],
        },
        'info': {'ver': '0.14.4', 'mac': 'aa'},
        'effects': ['Solid', 'Rainbow', 'RSVD'],
        'palettes': ['Default', 'Sunset'],
      };
      final snap = WledSnapshot.fromJson(json);
      expect(snap.state.on, isTrue);
      expect(snap.info.version, '0.14.4');
      expect(snap.effects, ['Solid', 'Rainbow', 'RSVD']);
      expect(snap.palettes, ['Default', 'Sunset']);
    });

    test('falls back to legacy eff/pal keys', () {
      const json = {
        'state': {'on': false, 'bri': 0},
        'eff': ['Solid'],
        'pal': ['Default'],
      };
      final snap = WledSnapshot.fromJson(json);
      expect(snap.effects, ['Solid']);
      expect(snap.palettes, ['Default']);
    });

    test('missing effect/palette arrays default to empty', () {
      const json = {
        'state': {'on': true, 'bri': 50},
      };
      final snap = WledSnapshot.fromJson(json);
      expect(snap.effects, isEmpty);
      expect(snap.palettes, isEmpty);
    });
  });

  group('WledCapabilities.fromSnapshot', () {
    WledSnapshot snap({
      required bool segmentBased,
      int? lc,
      String? c,
      List<String> effects = const ['Solid', 'Rainbow'],
      List<String> palettes = const ['Default'],
    }) {
      final stateJson = segmentBased
          ? {
              'on': true,
              'bri': 100,
              'seg': {
                'col': [
                  [1, 2, 3],
                ],
                'fx': 0,
              },
            }
          : {
              'on': true,
              'bri': 100,
              'c': [1, 2, 3],
              'fx': 0,
            };
      return WledSnapshot.fromJson({
        'state': stateJson,
        'info': {
          'ver': '1.0',
          if (lc != null) 'leds': {'lc': lc},
        },
        'effects': effects,
        'palettes': palettes,
      });
    }

    test('legacy firmware advertises color but not color temperature', () {
      final caps = WledCapabilities.fromSnapshot(snap(segmentBased: false));
      expect(caps, contains(DeviceCapability.power));
      expect(caps, contains(DeviceCapability.brightness));
      expect(caps, contains(DeviceCapability.color));
      expect(caps, contains(DeviceCapability.effect));
      expect(caps, contains(DeviceCapability.speed));
      expect(caps, isNot(contains(DeviceCapability.colorTemperature)));
    });

    test('segment firmware with CCT bit exposes color temperature', () {
      // lc bit0=RGB, bit1=white, bit2=CCT → 7
      final caps = WledCapabilities.fromSnapshot(
        snap(segmentBased: true, lc: 7),
      );
      expect(caps, contains(DeviceCapability.color));
      expect(caps, contains(DeviceCapability.colorTemperature));
    });

    test('segment firmware without RGB bit does not expose color', () {
      final caps = WledCapabilities.fromSnapshot(
        snap(segmentBased: true, lc: 4), // CCT only
      );
      expect(caps, isNot(contains(DeviceCapability.color)));
      expect(caps, contains(DeviceCapability.colorTemperature));
    });

    test('no effect list → no effect/speed capabilities', () {
      final caps = WledCapabilities.fromSnapshot(
        snap(segmentBased: false, effects: []),
      );
      expect(caps, isNot(contains(DeviceCapability.effect)));
      expect(caps, isNot(contains(DeviceCapability.speed)));
    });

    test('no palette list → no palette capability', () {
      final caps = WledCapabilities.fromSnapshot(
        snap(segmentBased: false, palettes: []),
      );
      expect(caps, isNot(contains(DeviceCapability.palette)));
    });
  });
}
