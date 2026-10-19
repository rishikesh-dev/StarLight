import 'package:flutter_test/flutter_test.dart';
import 'package:starlight/core/ble/device_name.dart';

/// Regression coverage for the Add Device overflow defect: advertisement byte
/// arrays were being turned into device names via `List.toString()`, producing
/// multi-hundred-character titles that overflowed the list row.
void main() {
  group('resolveDeviceDisplayName', () {
    test('prefers a valid platform name', () {
      expect(
        resolveDeviceDisplayName(platformName: 'Living Room Light'),
        'Living Room Light',
      );
    });

    test('uses the advertised name when the platform name is empty', () {
      expect(
        resolveDeviceDisplayName(platformName: '', advName: 'Desk Lamp'),
        'Desk Lamp',
      );
    });

    test('trims surrounding whitespace', () {
      expect(resolveDeviceDisplayName(platformName: '  Lamp  '), 'Lamp');
    });

    test('decodes a printable service-data payload', () {
      final bytes = 'StarLight'.codeUnits;
      expect(resolveDeviceDisplayName(serviceData: bytes), 'StarLight');
    });

    test('never renders a raw advertisement byte array', () {
      // Arbitrary RGB-ish bytes that do not decode to a printable string.
      final bytes = List<int>.generate(120, (i) => 190 + (i % 60));
      final name = resolveDeviceDisplayName(serviceData: bytes);
      expect(name, isNot(contains('[')));
      expect(name, isNot(contains(',')));
      expect(name.length, lessThanOrEqualTo(64));
    });

    test('falls back when no name is advertised', () {
      expect(resolveDeviceDisplayName(), kUnknownDeviceName);
      expect(resolveDeviceDisplayName(platformName: null), kUnknownDeviceName);
    });

    test('falls back for empty and whitespace-only names', () {
      expect(resolveDeviceDisplayName(platformName: ''), kUnknownDeviceName);
      expect(resolveDeviceDisplayName(advName: '   '), kUnknownDeviceName);
      expect(
        resolveDeviceDisplayName(platformName: '', advName: ''),
        kUnknownDeviceName,
      );
    });

    test('rejects control characters that indicate binary data', () {
      expect(
        resolveDeviceDisplayName(platformName: '\u0001\u0002\u0003'),
        kUnknownDeviceName,
      );
    });

    test('rejects extremely long advertisement-derived names', () {
      expect(
        resolveDeviceDisplayName(platformName: 'A' * 5000),
        kUnknownDeviceName,
      );
    });

    test('rejects malformed UTF-8 service data', () {
      final malformed = <int>[0xC3, 0x28];
      expect(
        resolveDeviceDisplayName(serviceData: malformed),
        kUnknownDeviceName,
      );
    });
  });
}
