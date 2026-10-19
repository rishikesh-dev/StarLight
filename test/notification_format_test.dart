import 'package:flutter_test/flutter_test.dart';
import 'package:starlight/domain/entities/device_state_update.dart';
import 'package:starlight/domain/entities/notification_format.dart';
import 'package:starlight/domain/entities/profile_command.dart';

void main() {
  group('NotificationRule', () {
    test('reads an unsigned byte', () {
      const rule = NotificationRule(
        target: NotificationTarget.power,
        byteOffset: 1,
      );
      expect(rule.rawValue([0x00, 0xFF]), 255);
    });

    test('reads little- and big-endian 16-bit values', () {
      const le = NotificationRule(
        target: NotificationTarget.brightness,
        byteOffset: 0,
        width: NumericWidth.u16le,
      );
      final be = le.copyWith(width: NumericWidth.u16be);
      expect(le.rawValue([0x34, 0x12]), 0x1234);
      expect(be.rawValue([0x12, 0x34]), 0x1234);
    });

    test('returns null when the packet is too short', () {
      const rule = NotificationRule(
        target: NotificationTarget.brightness,
        byteOffset: 3,
        width: NumericWidth.u16le,
      );
      expect(rule.rawValue([0, 0, 0]), isNull);
      expect(rule.value([0, 0, 0]), isNull);
    });

    test('applies scale and offset', () {
      const rule = NotificationRule(
        target: NotificationTarget.brightness,
        byteOffset: 0,
        scale: 10,
        offset: 5,
      );
      expect(rule.value([3]), 35);
    });
  });

  group('NotificationFormat.decode', () {
    test('decodes power against the on threshold', () {
      const format = NotificationFormat([
        NotificationRule(
          target: NotificationTarget.power,
          byteOffset: 0,
          onThreshold: 2,
        ),
      ]);
      expect(format.decode([2]).single.value, isTrue);
      expect(format.decode([2]).single.type, StateUpdateType.power);
      expect(format.decode([1]).single.value, isFalse);
    });

    test('decodes brightness as a rounded integer', () {
      const format = NotificationFormat([
        NotificationRule(
          target: NotificationTarget.brightness,
          byteOffset: 1,
          scale: 2.4,
        ),
      ]);
      final update = format.decode([0, 10]).single;
      expect(format.decode([0, 10]).single.type, StateUpdateType.brightness);
      expect(update.value, 24);
    });

    test('emits one colour update only when all three channels exist', () {
      const format = NotificationFormat([
        NotificationRule(target: NotificationTarget.red, byteOffset: 0),
        NotificationRule(target: NotificationTarget.green, byteOffset: 1),
        NotificationRule(target: NotificationTarget.blue, byteOffset: 2),
      ]);
      final color = format.decode([10, 20, 30]).single;
      expect(color.type, StateUpdateType.color);
      expect(color.value, {'red': 10, 'green': 20, 'blue': 30});
    });

    test('emits no colour when a channel is missing from the packet', () {
      const format = NotificationFormat([
        NotificationRule(target: NotificationTarget.red, byteOffset: 0),
        NotificationRule(target: NotificationTarget.green, byteOffset: 1),
        NotificationRule(target: NotificationTarget.blue, byteOffset: 2),
      ]);
      expect(format.decode([10, 20]), isEmpty);
    });

    test('a short packet yields no updates rather than a fabricated one', () {
      const format = NotificationFormat([
        NotificationRule(target: NotificationTarget.brightness, byteOffset: 5),
      ]);
      expect(format.decode([1, 2]), isEmpty);
    });

    test('isEmpty reflects the rule list', () {
      expect(const NotificationFormat([]).isEmpty, isTrue);
      expect(
        const NotificationFormat([
          NotificationRule(target: NotificationTarget.power, byteOffset: 0),
        ]).isEmpty,
        isFalse,
      );
    });
  });
}
