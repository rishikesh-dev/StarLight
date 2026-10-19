import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:starlight/core/ble/protocol_encoder.dart';
import 'package:starlight/domain/entities/command_result.dart';
import 'package:starlight/domain/entities/device_capability.dart';
import 'package:starlight/domain/entities/device_command.dart';
import 'package:starlight/domain/entities/device_profile.dart';
import 'package:starlight/domain/entities/effect.dart';
import 'package:starlight/domain/entities/light_command.dart';
import 'package:starlight/domain/entities/profile_command.dart';
import 'package:starlight/domain/entities/profile_verification.dart';
import 'package:starlight/domain/repositories/ble_repository.dart';
import 'package:starlight/domain/services/command_router.dart';

import 'support/fake_profile_executor.dart';

class MockBleRepository extends Mock implements BleRepository {}

CommandTemplate _t(String source) => CommandTemplate.parse(source).template!;

DeviceProfile _customProfile() => DeviceProfile(
  id: 'profile_custom',
  name: 'Custom',
  serviceUuid: 'fff0',
  writeCharacteristicUuid: 'fff3',
  capabilities: const {DeviceCapability.power},
  commands: GattCommandSet(powerOn: _t('A1'), powerOff: _t('A0')),
);

bool _sameBytes(List<int> actual, List<int> expected) {
  if (actual.length != expected.length) return false;
  for (var i = 0; i < expected.length; i++) {
    if (actual[i] != expected[i]) return false;
  }
  return true;
}

void main() {
  late MockBleRepository bleRepository;

  setUpAll(() {
    registerFallbackValue(const LightCommand(type: 'fallback', bytes: []));
  });

  setUp(() {
    bleRepository = MockBleRepository();
    when(() => bleRepository.sendCommand(any())).thenAnswer((_) async {});
  });

  group('built-in MR Star path', () {
    test('sends the unchanged ProtocolEncoder power bytes', () async {
      final router = CommandRouter(bleRepository);

      await router.send(DeviceCommand.power(true));

      final command =
          verify(() => bleRepository.sendCommand(captureAny())).captured.single
              as LightCommand;
      expect(_sameBytes(command.bytes, ProtocolEncoder.powerOn()), isTrue);
    });

    test('exposes the default MR Star capabilities', () {
      final router = CommandRouter(bleRepository);
      expect(router.capabilities, kDefaultLightCapabilities);
      expect(router.activeProfile, isNull);
    });

    test('assigning the built-in profile keeps the MR Star path', () async {
      final router = CommandRouter(bleRepository);
      router.applyProfile(DeviceProfile.mrStar);
      expect(router.activeProfile, isNull);

      await router.send(DeviceCommand.power(false));

      final command =
          verify(() => bleRepository.sendCommand(captureAny())).captured.single
              as LightCommand;
      expect(_sameBytes(command.bytes, ProtocolEncoder.powerOff()), isTrue);
    });

    test('refuses an unsupported command without touching the transport', () {
      final router = CommandRouter(bleRepository);

      expect(
        () => router.send(DeviceCommand.custom('effect', const {})),
        throwsA(
          isA<CommandRoutingException>().having(
            (e) => e.code,
            'code',
            'unsupported_command',
          ),
        ),
      );
      verifyNever(() => bleRepository.sendCommand(any()));
    });
  });

  group('custom profile routing', () {
    test('sends through the executor when the profile is verified', () async {
      final executor = FakeProfileExecutor(
        verification: const ProfileVerification(
          status: ProfileVerificationStatus.verified,
        ),
      );
      final profile = _customProfile();
      await executor.verify(profile);
      expect(executor.isVerified(profile.id), isTrue);

      final router = CommandRouter(bleRepository, executor: executor)
        ..applyProfile(profile);
      expect(router.activeProfile, profile);

      await router.send(DeviceCommand.power(true));

      expect(executor.sent, hasLength(1));
      expect(executor.sent.single.$2.type, 'power');
      verifyNever(() => bleRepository.sendCommand(any()));
    });

    test('refuses to send when the profile is not verified', () async {
      final executor = FakeProfileExecutor();
      final router = CommandRouter(bleRepository, executor: executor)
        ..applyProfile(_customProfile());

      await expectLater(
        router.send(DeviceCommand.power(true)),
        throwsA(
          isA<CommandRoutingException>().having(
            (e) => e.code,
            'code',
            'profile_not_verified',
          ),
        ),
      );
      expect(executor.sent, isEmpty);
      verifyNever(() => bleRepository.sendCommand(any()));
    });

    test('surfaces a failed executor result as a routing error', () async {
      final executor = FakeProfileExecutor(
        verification: const ProfileVerification(
          status: ProfileVerificationStatus.verified,
        ),
        result: const CommandResult.failure('write_timeout', 'Timed out'),
      );
      final profile = _customProfile();
      await executor.verify(profile);

      final router = CommandRouter(bleRepository, executor: executor)
        ..applyProfile(profile);

      await expectLater(
        router.send(DeviceCommand.power(true)),
        throwsA(
          isA<CommandRoutingException>()
              .having((e) => e.code, 'code', 'write_timeout')
              .having((e) => e.message, 'message', 'Timed out'),
        ),
      );
    });

    test('exposes the profile capabilities by default', () {
      final executor = FakeProfileExecutor();
      final profile = _customProfile();
      final router = CommandRouter(bleRepository, executor: executor)
        ..applyProfile(profile);
      expect(router.capabilities, profile.capabilities);
    });

    test('an empty capability set is honoured for assigned-but-unverified', () {
      final router = CommandRouter(bleRepository);
      router.applyProfile(null, capabilities: const {});
      expect(router.capabilities, isEmpty);
      expect(router.activeProfile, isNull);

      router.reset();
      expect(router.capabilities, kDefaultLightCapabilities);
    });

    test('notifies listeners only when the route actually changes', () {
      final router = CommandRouter(bleRepository);
      var notifications = 0;
      router.addListener(() => notifications++);

      router.applyProfile(null);
      expect(notifications, 0, reason: 'no-op apply should not notify');

      router.applyProfile(_customProfile());
      expect(notifications, 1);

      router.applyProfile(_customProfile());
      expect(notifications, 1, reason: 'same profile should not notify');

      router.reset();
      expect(notifications, 2);
    });
  });

  group('MR Star effect and speed encoding', () {
    test('encodes a known effect name via ProtocolEncoder', () async {
      final router = CommandRouter(bleRepository);

      await router.send(DeviceCommand.effect('Rainbow'));

      final command =
          verify(() => bleRepository.sendCommand(captureAny())).captured.single
              as LightCommand;
      expect(
        _sameBytes(
          command.bytes,
          ProtocolEncoder.setMode(effectById('rainbow')!.protocolModeId!),
        ),
        isTrue,
      );
    });

    test('every catalogue effect encodes to its canonical mode id', () async {
      for (final effect in kMrStarEffects) {
        clearInteractions(bleRepository);
        final router = CommandRouter(bleRepository);

        await router.send(DeviceCommand.effect(effect.commandName!));

        final command =
            verify(() => bleRepository.sendCommand(captureAny()))
                    .captured
                    .single
                as LightCommand;
        expect(
          _sameBytes(
            command.bytes,
            ProtocolEncoder.setMode(effect.protocolModeId!),
          ),
          isTrue,
          reason:
              '${effect.commandName} did not map to mode id '
              '${effect.protocolModeId}',
        );
      }
    });

    test('refuses an unknown effect instead of defaulting to a mode', () {
      final router = CommandRouter(bleRepository);

      expect(
        () => router.send(DeviceCommand.effect('DefinitelyNotAnEffect')),
        throwsA(
          isA<CommandRoutingException>().having(
            (e) => e.code,
            'code',
            'unsupported_command',
          ),
        ),
      );
      verifyNever(() => bleRepository.sendCommand(any()));
    });

    test('encodes an effect speed via ProtocolEncoder', () async {
      final router = CommandRouter(bleRepository);

      await router.send(DeviceCommand.speed(75));

      final command =
          verify(() => bleRepository.sendCommand(captureAny())).captured.single
              as LightCommand;
      expect(_sameBytes(command.bytes, ProtocolEncoder.setSpeed(75)), isTrue);
    });

    test('refuses an empty effect name without touching the transport', () {
      final router = CommandRouter(bleRepository);

      expect(
        () => router.send(DeviceCommand.effect('')),
        throwsA(
          isA<CommandRoutingException>().having(
            (e) => e.code,
            'code',
            'unsupported_command',
          ),
        ),
      );
      verifyNever(() => bleRepository.sendCommand(any()));
    });

    test('refuses a non-integer speed without touching the transport', () {
      final router = CommandRouter(bleRepository);

      expect(
        () => router.send(
          DeviceCommand(type: 'speed', parameters: {'value': 'fast'}),
        ),
        throwsA(
          isA<CommandRoutingException>().having(
            (e) => e.code,
            'code',
            'unsupported_command',
          ),
        ),
      );
      verifyNever(() => bleRepository.sendCommand(any()));
    });

    test('rejects an out-of-byte speed as invalid_parameter', () {
      final router = CommandRouter(bleRepository);

      expect(
        () => router.send(DeviceCommand.speed(999)),
        throwsA(
          isA<CommandRoutingException>().having(
            (e) => e.code,
            'code',
            'invalid_parameter',
          ),
        ),
      );
      verifyNever(() => bleRepository.sendCommand(any()));
    });
  });
}
