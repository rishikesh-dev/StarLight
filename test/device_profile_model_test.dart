import 'package:flutter_test/flutter_test.dart';
import 'package:starlight/data/models/device_profile_model.dart';
import 'package:starlight/domain/entities/device_capability.dart';
import 'package:starlight/domain/entities/device_profile.dart';
import 'package:starlight/domain/entities/notification_format.dart';
import 'package:starlight/domain/entities/profile_command.dart';

CommandTemplate _t(String source) {
  final result = CommandTemplate.parse(source);
  final template = result.template;
  if (template == null) {
    throw StateError('test template did not parse: ${result.error}');
  }
  return template;
}

DeviceProfile _fullProfile() => DeviceProfile(
  id: 'profile_1',
  name: 'Desk strip',
  serviceUuid: 'fff0',
  writeCharacteristicUuid: 'fff3',
  notifyCharacteristicUuid: 'fff4',
  capabilities: const {DeviceCapability.power, DeviceCapability.brightness},
  commands: GattCommandSet(
    powerOn: _t('01'),
    powerOff: _t('00'),
    brightness: _t('02 {brightness}'),
    brightnessMin: 0,
    brightnessMax: 255,
  ),
  notifications: const NotificationFormat([
    NotificationRule(target: NotificationTarget.brightness, byteOffset: 1),
  ]),
  schemaVersion: DeviceProfileModel.schemaVersion,
);

void main() {
  group('DeviceProfileModel round-trip', () {
    test('a fully populated profile survives encode/decode', () {
      final profile = _fullProfile();
      final decoded = DeviceProfileModel.fromJson(
        DeviceProfileModel.toJson(profile),
      );
      expect(decoded, profile);
      expect(decoded.hasNotifications, isTrue);
    });

    test('a minimal profile survives encode/decode', () {
      const profile = DeviceProfile(
        id: 'p',
        name: 'Minimal',
        serviceUuid: 'fff0',
        writeCharacteristicUuid: 'fff3',
      );
      final decoded = DeviceProfileModel.fromJson(
        DeviceProfileModel.toJson(profile),
      );
      expect(decoded, profile);
      expect(decoded.notifyCharacteristicUuid, isNull);
      expect(decoded.notifications, isNull);
      expect(decoded.hasNotifications, isFalse);
    });
  });

  group('DeviceProfileModel.fromJson rejection', () {
    test('missing schema', () {
      expect(
        () => DeviceProfileModel.fromJson(const {'id': 'x'}),
        throwsA(isA<ProfileFormatException>()),
      );
    });

    test('a newer schema is rejected rather than partially understood', () {
      final json = DeviceProfileModel.toJson(_fullProfile())
        ..['schema'] = DeviceProfileModel.schemaVersion + 1;
      expect(
        () => DeviceProfileModel.fromJson(json),
        throwsA(isA<ProfileFormatException>()),
      );
    });

    test('an older schema without a migration is rejected', () {
      final json = DeviceProfileModel.toJson(_fullProfile())..['schema'] = 0;
      expect(
        () => DeviceProfileModel.fromJson(json),
        throwsA(isA<ProfileFormatException>()),
      );
    });

    test('unknown protocol', () {
      final json = DeviceProfileModel.toJson(_fullProfile())
        ..['protocol'] = 'zigbee';
      expect(
        () => DeviceProfileModel.fromJson(json),
        throwsA(isA<ProfileFormatException>()),
      );
    });

    test('unknown capability', () {
      final json = DeviceProfileModel.toJson(_fullProfile())
        ..['capabilities'] = ['teleport'];
      expect(
        () => DeviceProfileModel.fromJson(json),
        throwsA(isA<ProfileFormatException>()),
      );
    });

    test('malformed command template', () {
      final json = DeviceProfileModel.toJson(_fullProfile());
      (json['commands'] as Map)['brightness'] = 'ZZ';
      expect(
        () => DeviceProfileModel.fromJson(json),
        throwsA(isA<ProfileFormatException>()),
      );
    });

    test('notification rule with an unknown target', () {
      final json = DeviceProfileModel.toJson(_fullProfile());
      (json['notifications'] as Map)['rules'] = [
        {'target': 'luminance', 'byteOffset': 0},
      ];
      expect(
        () => DeviceProfileModel.fromJson(json),
        throwsA(isA<ProfileFormatException>()),
      );
    });

    test('notifications without a rules list', () {
      final json = DeviceProfileModel.toJson(_fullProfile())
        ..['notifications'] = const {'oops': true};
      expect(
        () => DeviceProfileModel.fromJson(json),
        throwsA(isA<ProfileFormatException>()),
      );
    });

    test('a missing required string field', () {
      final json = DeviceProfileModel.toJson(_fullProfile())..remove('id');
      expect(
        () => DeviceProfileModel.fromJson(json),
        throwsA(isA<ProfileFormatException>()),
      );
    });
  });
}
