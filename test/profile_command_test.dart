import 'package:flutter_test/flutter_test.dart';
import 'package:starlight/domain/entities/profile_command.dart';

void main() {
  group('CommandTemplate.parse', () {
    test('parses literals and placeholders', () {
      final result = CommandTemplate.parse('A0 {brightness} {checksum}');

      expect(result.isOk, isTrue);
      final template = result.template!;
      expect(template.tokens, [
        const LiteralByte(0xA0),
        const CommandPlaceholder(ProfileValue.brightness),
        const CommandPlaceholder(ProfileValue.checksum),
      ]);
      expect(template.byteLength, 3);
      expect(template.requiredValues, {ProfileValue.brightness});
    });

    test('accepts lowercase hex and collapses whitespace', () {
      final template = CommandTemplate.parse('7e   ff\t02').template!;
      expect(template.tokens, [
        const LiteralByte(0x7E),
        const LiteralByte(0xFF),
        const LiteralByte(0x02),
      ]);
    });

    test('resolves documented placeholder aliases', () {
      final template = CommandTemplate.parse('{r} {g} {b} {bright} {xor}')
          .template!;
      expect(template.tokens, [
        const CommandPlaceholder(ProfileValue.red),
        const CommandPlaceholder(ProfileValue.green),
        const CommandPlaceholder(ProfileValue.blue),
        const CommandPlaceholder(ProfileValue.brightness),
        const CommandPlaceholder(ProfileValue.checksum),
      ]);
    });

    test('parses width suffixes', () {
      final template = CommandTemplate.parse(
        '01 {brightness:u16le} {red:u16be}',
      ).template!;
      expect(template.tokens, [
        const LiteralByte(0x01),
        const CommandPlaceholder(ProfileValue.brightness, NumericWidth.u16le),
        const CommandPlaceholder(ProfileValue.red, NumericWidth.u16be),
      ]);
      expect(template.byteLength, 1 + 2 + 2);
    });

    test('rejects an empty template', () {
      final result = CommandTemplate.parse('   ');
      expect(result.isOk, isFalse);
      expect(result.error, contains('empty'));
    });

    test('rejects an unterminated placeholder', () {
      final result = CommandTemplate.parse('{brightness');
      expect(result.isOk, isFalse);
      expect(result.error, contains('Unterminated'));
    });

    test('rejects an empty placeholder', () {
      expect(CommandTemplate.parse('{}').isOk, isFalse);
    });

    test('rejects an unknown placeholder', () {
      final result = CommandTemplate.parse('{temperature}');
      expect(result.isOk, isFalse);
      expect(result.error, contains('temperature'));
    });

    test('rejects an invalid literal byte', () {
      for (final bad in ['A', 'GG', 'ABCD', '0']) {
        expect(
          CommandTemplate.parse(bad).isOk,
          isFalse,
          reason: '"$bad" must not parse',
        );
      }
    });

    test('rejects an unknown width suffix', () {
      final result = CommandTemplate.parse('{brightness:u32}');
      expect(result.isOk, isFalse);
      expect(result.error, contains('u8'));
    });

    test('rejects a width suffix on a checksum', () {
      final result = CommandTemplate.parse('01 {checksum:u16le}');
      expect(result.isOk, isFalse);
      expect(result.error, contains('single byte'));
    });

    test('rejects a checksum that is not last', () {
      final result = CommandTemplate.parse('{checksum} 01');
      expect(result.isOk, isFalse);
      expect(result.error, contains('last byte'));
    });

    test('rejects more than one checksum', () {
      final result = CommandTemplate.parse('{checksum} {checksum}');
      expect(result.isOk, isFalse);
      expect(result.error, contains('at most one checksum'));
    });

    test('rejects more than twenty tokens', () {
      final source = List.filled(21, '01').join(' ');
      final result = CommandTemplate.parse(source);
      expect(result.isOk, isFalse);
      expect(result.error, contains('20'));
    });

    test('rejects a placeholder that is not allowed for the command', () {
      final result = CommandTemplate.parse(
        '01 {brightness}',
        allowed: const {ProfileValue.red, ProfileValue.checksum},
      );
      expect(result.isOk, isFalse);
      expect(result.error, contains('brightness'));
    });
  });

  group('CommandTemplate.encode', () {
    test('writes literals and a checksum as XOR of preceding bytes', () {
      final template = CommandTemplate.parse('A0 {brightness} {checksum}')
          .template!;
      final bytes = template.encode({ProfileValue.brightness: 0x0F});
      expect(bytes, [0xA0, 0x0F, 0xA0 ^ 0x0F]);
    });

    test('checksum of an empty prefix is zero', () {
      final template = CommandTemplate.parse('{checksum}').template!;
      expect(template.encode(const {}), [0x00]);
    });

    test('writes 16-bit values little- and big-endian', () {
      final le = CommandTemplate.parse('{brightness:u16le}').template!;
      final be = CommandTemplate.parse('{brightness:u16be}').template!;
      expect(le.encode({ProfileValue.brightness: 0x1234}), [0x34, 0x12]);
      expect(be.encode({ProfileValue.brightness: 0x1234}), [0x12, 0x34]);
    });

    test('clamps values to the width range instead of wrapping', () {
      final u8 = CommandTemplate.parse('{red}').template!;
      final u16 = CommandTemplate.parse('{red:u16be}').template!;
      expect(u8.encode({ProfileValue.red: 0x1FF}), [0xFF]);
      expect(u16.encode({ProfileValue.red: 0x1FFFF}), [0xFF, 0xFF]);
    });

    test('throws when a required value is missing', () {
      final template = CommandTemplate.parse('{red} {green}').template!;
      expect(
        () => template.encode({ProfileValue.red: 1}),
        throwsA(isA<StateError>()),
      );
    });

    test('round-trips through toText', () {
      const source = 'A0 {brightness} {checksum}';
      final template = CommandTemplate.parse(source).template!;
      expect(template.toText(), 'A0 {brightness} {checksum}');
      expect(CommandTemplate.parse(template.toText()).template, template);
    });
  });

  group('ProfileValue', () {
    test('maps aliases and canonical ids', () {
      expect(ProfileValue.fromToken('BRIGHT'), ProfileValue.brightness);
      expect(ProfileValue.fromToken('r'), ProfileValue.red);
      expect(ProfileValue.fromToken('xor'), ProfileValue.checksum);
      expect(ProfileValue.fromToken('nope'), isNull);
      expect(ProfileValue.fromId('green'), ProfileValue.green);
      expect(ProfileValue.fromId('nope'), isNull);
    });
  });
}
