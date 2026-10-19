import 'package:test/test.dart';
import 'package:starlight/core/ble/protocol_decoder.dart';
import 'package:starlight/core/ble/protocol_encoder.dart';
import 'package:starlight/domain/entities/device_state_update.dart';
import 'package:starlight/domain/entities/effect.dart';

void main() {
  group('ProtocolDecoder', () {
    test('decode returns null for empty bytes', () {
      expect(ProtocolDecoder.decode([]), isNull);
      expect(ProtocolDecoder.decode([0xBC]), isNull);
    });

    test('decode returns null for invalid start byte', () {
      final packet = [0x00, 0x01, 0x01, 0x00, 0x55];
      expect(ProtocolDecoder.decode(packet), isNull);
    });

    test('decode returns null for invalid end byte', () {
      final packet = [0xBC, 0x01, 0x01, 0x00, 0x00];
      expect(ProtocolDecoder.decode(packet), isNull);
    });

    test('decode returns null for too short packet', () {
      final packet = [0xBC, 0x01];
      expect(ProtocolDecoder.decode(packet), isNull);
    });

    test('decode correctly parses valid notification packet', () {
      // Brightness notification: opcode=0x05, length=2, data=[0x03, 0xE8] (1000)
      final packet = [0xBC, 0x05, 0x02, 0x03, 0xE8, 0x55];
      final decoded = ProtocolDecoder.decode(packet);
      expect(decoded, isNotNull);
      expect(decoded!.opcode, 0x05);
      expect(decoded.length, 2);
      expect(decoded.data, [0x03, 0xE8]);
    });

    test('parseState returns brightness update from notification', () {
      // Notification: BC 05 02 03 E8 55 -> brightness = 1000
      final packet = DecodedPacket(
        opcode: 0x05,
        length: 2,
        data: [0x03, 0xE8],
        rawBytes: [0xBC, 0x05, 0x02, 0x03, 0xE8, 0x55],
      );
      final update = ProtocolDecoder.parseState(packet);
      expect(update?.type, StateUpdateType.brightness);
      expect(update?.value, 1000);
    });

    test('parseState returns color update from notification', () {
      // Notification: BC 04 06 00 00 FF 00 00 00 00 55 -> red color
      // data[2] = red (0xFF), data[3] = green (0x00), data[4] = blue (0x00)
      final packet = DecodedPacket(
        opcode: 0x04,
        length: 6,
        data: [0x00, 0x00, 0xFF, 0x00, 0x00, 0x00],
        rawBytes: [
          0xBC,
          0x04,
          0x06,
          0x00,
          0x00,
          0xFF,
          0x00,
          0x00,
          0x00,
          0x00,
          0x55,
        ],
      );
      final update = ProtocolDecoder.parseState(packet);
      expect(update?.type, StateUpdateType.color);
      expect(update?.value, {'red': 255, 'green': 0, 'blue': 0});
    });

    test('parseState returns power update from notification', () {
      final packet = DecodedPacket(
        opcode: 0x01,
        length: 1,
        data: [0x01],
        rawBytes: [],
      );
      final update = ProtocolDecoder.parseState(packet);
      expect(update?.type, StateUpdateType.power);
      expect(update?.value, true);
    });

    test('parseState returns mic update from notification', () {
      final packet = DecodedPacket(
        opcode: 0x0F,
        length: 1,
        data: [0x01],
        rawBytes: [],
      );
      final update = ProtocolDecoder.parseState(packet);
      expect(update?.type, StateUpdateType.mic);
      expect(update?.value, true);
    });
  });

  group('ProtocolEncoder edge cases', () {
    test('brightness clamps minimum to 3', () {
      final bytes = ProtocolEncoder.brightness(0);
      expect(bytes[3], 0x00);
      expect(bytes[4], 0x03);
    });

    test('setMode encodes values correctly', () {
      final bytes = ProtocolEncoder.setMode(5);
      expect(bytes[0], 0xBC);
      expect(bytes[1], 0x06);
      expect(bytes[2], 0x02);
      expect(bytes[3], 0x00);
      expect(bytes[4], 0x05);
      expect(bytes.last, 0x55);
    });

    test('setMode rolls over at 255', () {
      final bytes = ProtocolEncoder.setMode(255);
      expect(bytes[3], 0x01);
      expect(bytes[4], 0x00);
    });

    test('setMode negative is clamped', () {
      final bytes = ProtocolEncoder.setMode(-3);
      expect(bytes[3], 0x00);
      expect(bytes[4], 0x00);
    });

    test('setMode encodes a catalogue effect id (cmode3 = 3)', () {
      final mode = ProtocolEncoder.setMode(
        effectById('cmode3')!.protocolModeId!,
      );
      expect(mode[0], 0xBC);
      expect(mode[1], 0x06);
      expect(mode[2], 0x02);
      expect(mode[3], 0x00);
      expect(mode[4], 0x03);
      expect(mode.last, 0x55);
    });

    test('setSpeed encodes the byte field', () {
      final bytes = ProtocolEncoder.setSpeed(80);
      expect(bytes[0], 0xBC);
      expect(bytes[1], 0x08);
      expect(bytes[2], 0x01);
      expect(bytes[3], 80);
      expect(bytes[4], 0x55);
    });

    test('setSpeed accepts the byte boundaries 0 and 255', () {
      expect(ProtocolEncoder.setSpeed(0)[3], 0x00);
      expect(ProtocolEncoder.setSpeed(255)[3], 0xFF);
    });

    test('setSpeed rejects out-of-byte values instead of wrapping', () {
      expect(() => ProtocolEncoder.setSpeed(-1), throwsArgumentError);
      expect(() => ProtocolEncoder.setSpeed(256), throwsArgumentError);
      expect(() => ProtocolEncoder.setSpeed(1000), throwsArgumentError);
    });
  });

  group('DecodedPacket', () {
    test('toString formats correctly', () {
      final packet = DecodedPacket(
        opcode: 0x01,
        length: 1,
        data: [0x00],
        rawBytes: [0xBC, 0x01, 0x01, 0x00, 0x55],
      );
      expect(packet.toString(), contains('01'));
    });
  });

  group('DeviceStateUpdate', () {
    test('props includes type and value', () {
      final update = DeviceStateUpdate(
        type: StateUpdateType.power,
        value: true,
      );
      expect(update.props, [StateUpdateType.power, true]);
    });
  });
}
