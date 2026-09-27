import 'package:test/test.dart';
import 'package:starlight/core/ble/ble_constants.dart';
import 'package:starlight/core/utils/uuid_utils.dart';

void main() {
  group('UuidUtils.normalize', () {
    test('expands a 16-bit uuid to the bluetooth base uuid', () {
      expect(
        UuidUtils.normalize('fff0'),
        equals('0000fff000001000800000805f9b34fb'),
      );
    });

    test('expands an uppercase 32-bit uuid', () {
      expect(
        UuidUtils.normalize('0000FFF3'),
        equals('0000fff300001000800000805f9b34fb'),
      );
    });

    test('keeps a full 128-bit uuid and strips dashes', () {
      expect(
        UuidUtils.normalize('0000FFF4-0000-1000-8000-00805F9B34FB'),
        equals('0000fff400001000800000805f9b34fb'),
      );
    });

    test('is idempotent', () {
      final once = UuidUtils.normalize('fff4');
      expect(UuidUtils.normalize(once), equals(once));
    });
  });

  group('UuidUtils.matches', () {
    test('short form matches the full constant', () {
      expect(
        UuidUtils.matches('fff0', BleConstants.serviceUuid),
        isTrue,
      );
    });

    test('matches the characteristic constants', () {
      expect(UuidUtils.matches('fff3', BleConstants.writeCharUuid), isTrue);
      expect(UuidUtils.matches('fff4', BleConstants.notifyCharUuid), isTrue);
      expect(UuidUtils.matches('2902', BleConstants.cccDescriptorUuid), isTrue);
    });

    test('is case insensitive', () {
      expect(
        UuidUtils.matches('FFF0', BleConstants.serviceUuid),
        isTrue,
      );
    });

    test('does not match a different uuid', () {
      expect(
        UuidUtils.matches('fff1', BleConstants.serviceUuid),
        isFalse,
      );
      expect(
        UuidUtils.matches('fff3', BleConstants.notifyCharUuid),
        isFalse,
      );
    });

    test('does not match a custom 128-bit uuid', () {
      expect(
        UuidUtils.matches(
          '12345678-1234-5678-1234-56789abcdef0',
          BleConstants.serviceUuid,
        ),
        isFalse,
      );
    });
  });
}
