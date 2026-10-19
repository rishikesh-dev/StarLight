import 'package:flutter_test/flutter_test.dart';
import 'package:starlight/domain/entities/device_capability.dart';
import 'package:starlight/domain/entities/device_profile.dart';
import 'package:starlight/domain/entities/notification_format.dart';
import 'package:starlight/domain/entities/profile_command.dart';
import 'package:starlight/domain/services/profile_validator.dart';

CommandTemplate _t(String source, {Set<ProfileValue>? allowed}) {
  final result = CommandTemplate.parse(
    source,
    allowed:
        allowed ??
        const {
          ProfileValue.brightness,
          ProfileValue.red,
          ProfileValue.green,
          ProfileValue.blue,
          ProfileValue.checksum,
        },
  );
  final template = result.template;
  if (template == null) {
    throw StateError('test template did not parse: ${result.error}');
  }
  return template;
}

DeviceProfile _profile({
  String name = 'Desk strip',
  String id = 'profile_1',
  String serviceUuid = 'fff0',
  String writeUuid = 'fff3',
  String? notifyUuid,
  Set<DeviceCapability> capabilities = const {DeviceCapability.power},
  GattCommandSet? commands,
  NotificationFormat? notifications,
}) {
  return DeviceProfile(
    id: id,
    name: name,
    serviceUuid: serviceUuid,
    writeCharacteristicUuid: writeUuid,
    notifyCharacteristicUuid: notifyUuid,
    capabilities: capabilities,
    commands:
        commands ??
        GattCommandSet(
          powerOn: _t('01', allowed: const {ProfileValue.checksum}),
          powerOff: _t('00', allowed: const {ProfileValue.checksum}),
        ),
    notifications: notifications,
  );
}

void main() {
  group('ProfileValidator.validate', () {
    test('a complete power profile is valid', () {
      expect(ProfileValidator.validate(_profile()), isEmpty);
      expect(ProfileValidator.isValid(_profile()), isTrue);
    });

    test('the built-in profile is always valid', () {
      expect(ProfileValidator.validate(DeviceProfile.mrStar), isEmpty);
    });

    test('name is required and length-limited', () {
      final missing = ProfileValidator.errorMap(_profile(name: '   '));
      expect(missing['name'], isNotNull);

      final tooLong = ProfileValidator.errorMap(
        _profile(name: 'x' * (ProfileValidator.maxNameLength + 1)),
      );
      expect(tooLong['name'], contains('${ProfileValidator.maxNameLength}'));
    });

    test('service and write UUIDs are required', () {
      final errors = ProfileValidator.errorMap(
        _profile(serviceUuid: '', writeUuid: ''),
      );
      expect(errors['serviceUuid'], contains('required'));
      expect(errors['writeCharacteristicUuid'], contains('required'));
    });

    test('rejects a malformed UUID', () {
      final errors = ProfileValidator.errorMap(_profile(serviceUuid: 'zzzz'));
      expect(errors['serviceUuid'], contains('valid UUID'));
    });

    test('accepts 16-bit, 32-bit and 128-bit UUID forms', () {
      for (final uuid in [
        'fff0',
        '0000fff0',
        '0000fff0-0000-1000-8000-00805f9b34fb',
      ]) {
        expect(
          ProfileValidator.isValid(_profile(serviceUuid: uuid)),
          isTrue,
          reason: uuid,
        );
      }
    });

    test('validates the notify UUID only when present', () {
      expect(ProfileValidator.isValid(_profile()), isTrue);
      final errors = ProfileValidator.errorMap(_profile(notifyUuid: 'zz'));
      expect(errors['notifyCharacteristicUuid'], isNotNull);
    });

    test('notification rules without a notify UUID are rejected', () {
      final errors = ProfileValidator.errorMap(
        _profile(
          notifications: const NotificationFormat([
            NotificationRule(target: NotificationTarget.power, byteOffset: 0),
          ]),
        ),
      );
      expect(errors['notifyCharacteristicUuid'], contains('notify'));
    });

    test('at least one capability is required', () {
      final errors = ProfileValidator.errorMap(
        _profile(capabilities: const {}),
      );
      expect(errors['capabilities'], contains('at least one'));
    });

    test('capabilities outside the executable set are rejected', () {
      final errors = ProfileValidator.errorMap(
        _profile(capabilities: const {DeviceCapability.effect}),
      );
      expect(errors['capabilities'], contains('Effect'));
    });

    test('power requires both power-on and power-off commands', () {
      final errors = ProfileValidator.errorMap(
        _profile(
          capabilities: const {DeviceCapability.power},
          commands: const GattCommandSet(),
        ),
      );
      expect(errors['powerOn'], contains('required'));
      expect(errors['powerOff'], contains('required'));
    });

    test('brightness requires a command and a valid range', () {
      final missing = ProfileValidator.errorMap(
        _profile(capabilities: const {DeviceCapability.brightness}),
      );
      expect(missing['brightness'], contains('required'));

      final badRange = ProfileValidator.errorMap(
        _profile(
          capabilities: const {DeviceCapability.brightness},
          commands: GattCommandSet(
            brightness: _t('{brightness}'),
            brightnessMin: 200,
            brightnessMax: 100,
          ),
        ),
      );
      expect(badRange['brightnessRange'], contains('greater'));
    });

    test('colour requires a colour command', () {
      final errors = ProfileValidator.errorMap(
        _profile(
          capabilities: const {DeviceCapability.color},
          commands: const GattCommandSet(),
        ),
      );
      expect(errors['color'], contains('required'));
    });

    test('a command cannot use a placeholder outside its allowed set', () {
      final errors = ProfileValidator.errorMap(
        _profile(
          capabilities: const {DeviceCapability.brightness},
          commands: GattCommandSet(brightness: _t('01 {checksum}')),
        ),
      );
      // A valid brightness profile must not sneak in a colour placeholder.
      final colourErrors = ProfileValidator.errorMap(
        _profile(
          capabilities: const {DeviceCapability.color},
          commands: GattCommandSet(color: _t('01 {brightness}')),
        ),
      );
      expect(errors, isEmpty);
      expect(colourErrors['color'], contains('brightness'));
    });

    test('brightness range must stay within 0..65535', () {
      final errors = ProfileValidator.errorMap(
        _profile(
          capabilities: const {DeviceCapability.brightness},
          commands: GattCommandSet(
            brightness: _t('01 {brightness}'),
            brightnessMin: -1,
            brightnessMax: 70000,
          ),
        ),
      );
      expect(errors['brightnessRange'], contains('65535'));
    });

    test('notification rules reject negative offsets and zero scale', () {
      final errors = ProfileValidator.errorMap(
        _profile(
          notifyUuid: 'fff4',
          notifications: const NotificationFormat([
            NotificationRule(
              target: NotificationTarget.power,
              byteOffset: -1,
              scale: 0,
            ),
          ]),
        ),
      );
      expect(errors['notifications'], isNotNull);
    });

    test('only one rule per state field is allowed', () {
      final errors = ProfileValidator.errorMap(
        _profile(
          notifyUuid: 'fff4',
          notifications: const NotificationFormat([
            NotificationRule(target: NotificationTarget.power, byteOffset: 0),
            NotificationRule(target: NotificationTarget.power, byteOffset: 1),
          ]),
        ),
      );
      expect(errors['notifications'], contains('one rule'));
    });

    test('errorMap keeps the first message per field', () {
      final map = ProfileValidator.errorMap(_profile(name: ''));
      expect(map['name'], 'Name is required.');
    });
  });
}
