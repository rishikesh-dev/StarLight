import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:starlight/core/ble/protocol_encoder.dart';
import 'package:starlight/domain/entities/device_capability.dart';
import 'package:starlight/domain/entities/device_profile.dart';
import 'package:starlight/domain/entities/effect.dart';
import 'package:starlight/domain/entities/light_command.dart';
import 'package:starlight/domain/entities/profile_command.dart';
import 'package:starlight/domain/entities/profile_verification.dart';
import 'package:starlight/domain/repositories/ble_repository.dart';
import 'package:starlight/domain/services/command_router.dart';
import 'package:starlight/domain/services/effect_engine.dart';

import 'support/fake_profile_executor.dart';

class MockBleRepository extends Mock implements BleRepository {}

bool _sameBytes(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < b.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

CommandTemplate _t(String source) => CommandTemplate.parse(source).template!;

DeviceProfile _customProfile() => DeviceProfile(
  id: 'profile_custom',
  name: 'Custom',
  serviceUuid: 'fff0',
  writeCharacteristicUuid: 'fff3',
  capabilities: const {DeviceCapability.power},
  commands: GattCommandSet(powerOn: _t('A1'), powerOff: _t('A0')),
);

void main() {
  late MockBleRepository bleRepository;

  setUpAll(() {
    registerFallbackValue(const LightCommand(type: 'fallback', bytes: []));
  });

  setUp(() {
    bleRepository = MockBleRepository();
  });

  LightCommand captureSingle() =>
      verify(() => bleRepository.sendCommand(captureAny())).captured.single
          as LightCommand;

  group('EffectEngine — MR Star route', () {
    test('sends a supported effect via the canonical mode packet', () async {
      when(() => bleRepository.sendCommand(any())).thenAnswer((_) async {});
      final engine = EffectEngine(CommandRouter(bleRepository));

      final result = await engine.apply(effectById('rainbow')!);

      expect(result.isSent, isTrue);
      expect(
        _sameBytes(captureSingle().bytes, ProtocolEncoder.setMode(2)),
        isTrue,
      );
    });

    test('sends effect then speed when a speed is requested', () async {
      when(() => bleRepository.sendCommand(any())).thenAnswer((_) async {});
      final engine = EffectEngine(CommandRouter(bleRepository));

      final result = await engine.apply(effectById('chase')!, speed: 40);

      expect(result.isSent, isTrue);
      final captured = verify(() => bleRepository.sendCommand(captureAny()))
          .captured
          .cast<LightCommand>();
      expect(captured, hasLength(2));
      expect(_sameBytes(captured[0].bytes, ProtocolEncoder.setMode(7)), isTrue);
      expect(
        _sameBytes(captured[1].bytes, ProtocolEncoder.setSpeed(40)),
        isTrue,
      );
    });

    test(
      'rejects a speed above the advertised range, without sending',
      () async {
        when(() => bleRepository.sendCommand(any())).thenAnswer((_) async {});
        final engine = EffectEngine(CommandRouter(bleRepository));

        final result = await engine.apply(effectById('rainbow')!, speed: 101);

        expect(result.outcome, EffectOutcome.invalidParameter);
        expect(result.code, 'speed_out_of_range');
        verifyNever(() => bleRepository.sendCommand(any()));
      },
    );

    test('rejects a speed for an effect with no speed parameter', () async {
      when(() => bleRepository.sendCommand(any())).thenAnswer((_) async {});
      final engine = EffectEngine(CommandRouter(bleRepository));

      final result = await engine.apply(effectById('solid')!, speed: 50);

      expect(result.outcome, EffectOutcome.invalidParameter);
      expect(result.code, 'speed_not_supported');
      verifyNever(() => bleRepository.sendCommand(any()));
    });

    test(
      'setSpeed validates the app-level range and boundary values',
      () async {
        when(() => bleRepository.sendCommand(any())).thenAnswer((_) async {});
        final engine = EffectEngine(CommandRouter(bleRepository));

        expect((await engine.setSpeed(0)).isSent, isTrue);
        expect((await engine.setSpeed(100)).isSent, isTrue);
        expect((await engine.setSpeed(50)).isSent, isTrue);

        final tooHigh = await engine.setSpeed(101);
        expect(tooHigh.outcome, EffectOutcome.invalidParameter);
        final negative = await engine.setSpeed(-1);
        expect(negative.outcome, EffectOutcome.invalidParameter);
      },
    );

    test('maps a transport failure to a typed transport error', () async {
      when(() => bleRepository.sendCommand(any()))
          .thenThrow(Exception('link down'));
      final engine = EffectEngine(CommandRouter(bleRepository));

      final result = await engine.apply(effectById('rainbow')!);

      expect(result.outcome, EffectOutcome.transportError);
    });
  });

  group('EffectEngine — capability gating', () {
    test(
      'reports unsupported when the route exposes no effect capability',
      () async {
        final router = CommandRouter(bleRepository)
          ..applyProfile(null, capabilities: const {});
        final engine = EffectEngine(router);

        final result = await engine.apply(effectById('rainbow')!);

        expect(result.outcome, EffectOutcome.unsupported);
        verifyNever(() => bleRepository.sendCommand(any()));
      },
    );
  });

  group('EffectEngine — custom profile isolation', () {
    test(
      'routes effects through the executor, never the MR Star transport',
      () async {
        final executor = FakeProfileExecutor(
          verification: const ProfileVerification(
            status: ProfileVerificationStatus.verified,
          ),
        );
        final profile = _customProfile();
        await executor.verify(profile);
        final router = CommandRouter(
          bleRepository,
          executor: executor,
        )..applyProfile(profile, capabilities: const {DeviceCapability.effect});
        final engine = EffectEngine(router);

        await engine.apply(effectById('rainbow')!);

        expect(executor.sent, hasLength(1));
        expect(executor.sent.single.$2.type, 'effect');
        // The custom-profile command must never leak into the MR Star encoder.
        verifyNever(() => bleRepository.sendCommand(any()));
      },
    );

    test(
      'reports unsupported when the assigned profile is not verified',
      () async {
        final executor = FakeProfileExecutor(); // notConnected by default
        final router = CommandRouter(bleRepository, executor: executor)
          ..applyProfile(
            _customProfile(),
            capabilities: const {DeviceCapability.effect},
          );
        final engine = EffectEngine(router);

        final result = await engine.apply(effectById('rainbow')!);

        expect(result.outcome, EffectOutcome.unsupported);
        verifyNever(() => bleRepository.sendCommand(any()));
      },
    );
  });

  group('EffectEngine — device staleness', () {
    test('drops a result that becomes stale when the device changes', () async {
      final completer = Completer<void>();
      when(() => bleRepository.sendCommand(any()))
          .thenAnswer((_) => completer.future);
      final engine = EffectEngine(CommandRouter(bleRepository));
      engine.bindDevice('device-a');

      final pending = engine.apply(effectById('rainbow')!);
      engine.bindDevice('device-b'); // active device changed mid-flight
      completer.complete();

      final result = await pending;
      expect(result.outcome, EffectOutcome.stale);
    });

    test('invalidate() marks in-flight work stale', () async {
      final completer = Completer<void>();
      when(() => bleRepository.sendCommand(any()))
          .thenAnswer((_) => completer.future);
      final engine = EffectEngine(CommandRouter(bleRepository));

      final pending = engine.setSpeed(60);
      engine.invalidate();
      completer.complete();

      expect((await pending).outcome, EffectOutcome.stale);
    });
  });
}
