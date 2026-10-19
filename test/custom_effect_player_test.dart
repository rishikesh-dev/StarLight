import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:starlight/domain/entities/effect.dart';
import 'package:starlight/domain/entities/light_command.dart';
import 'package:starlight/domain/repositories/ble_repository.dart';
import 'package:starlight/domain/services/command_router.dart';
import 'package:starlight/domain/services/custom_effect_player.dart';
import 'package:starlight/domain/services/effect_engine.dart';

class MockBleRepository extends Mock implements BleRepository {}

const _fast = Duration(milliseconds: 50);

void main() {
  late MockBleRepository ble;
  late CommandRouter router;

  setUpAll(() {
    registerFallbackValue(const LightCommand(type: 'fallback', bytes: []));
  });

  setUp(() {
    ble = MockBleRepository();
    when(() => ble.sendCommand(any())).thenAnswer((_) async {});
    router = CommandRouter(ble);
  });

  CustomEffectPlayer buildPlayer({Duration frameInterval = _fast}) =>
      CustomEffectPlayer(router, frameInterval: frameInterval);

  EffectDefinition effect(String id) => effectById(id)!;

  group('safety invariants', () {
    test('clamps a sub-50ms frame interval to the floor', () {
      final player = buildPlayer(
        frameInterval: const Duration(milliseconds: 1),
      );
      expect(player.frameInterval, _fast);
    });

    test('starts idle', () {
      final player = buildPlayer();
      expect(player.isPlaying, isFalse);
      expect(player.effectId, isNull);
    });
  });

  group('validate', () {
    test('accepts a colour-sequence custom effect', () {
      expect(buildPlayer().validate(effect('custom-aurora')), isNull);
    });

    test('rejects a device pattern (not a custom effect)', () {
      final result = buildPlayer().validate(effect('cmode3'));
      expect(result?.outcome, EffectOutcome.unsupported);
    });

    test('rejects an addressable-only effect (preview only)', () {
      expect(
        buildPlayer().validate(effect('custom-meteor'))?.outcome,
        EffectOutcome.unsupported,
      );
      expect(
        buildPlayer().validate(effect('custom-starlight'))?.outcome,
        EffectOutcome.unsupported,
      );
    });

    test('rejects speed outside the advertised range', () {
      final result = buildPlayer().validate(
        effect('custom-aurora'),
        speed: 101,
      );
      expect(result?.outcome, EffectOutcome.invalidParameter);
      expect(result?.code, 'speed_out_of_range');
    });

    test('rejects intensity outside the advertised range', () {
      final result = buildPlayer().validate(
        effect('custom-aurora'),
        intensity: -1,
      );
      expect(result?.outcome, EffectOutcome.invalidParameter);
      expect(result?.code, 'intensity_out_of_range');
    });

    test('refuses when the active route lacks the colour capability', () {
      router.applyProfile(null, capabilities: const {});
      final result = buildPlayer().validate(effect('custom-aurora'));
      expect(result?.outcome, EffectOutcome.unsupported);
    });
  });

  group('start', () {
    test('streams colour commands and never a device-mode packet', () async {
      final player = buildPlayer();
      final result = await player.start(effect('custom-aurora'));
      expect(result.outcome, EffectOutcome.sent);
      expect(player.isPlaying, isTrue);
      expect(player.effectId, 'custom-aurora');

      await Future<void>.delayed(const Duration(milliseconds: 130));
      player.stop();

      final commands = verify(() => ble.sendCommand(captureAny())).captured
          .cast<LightCommand>();
      expect(commands, isNotEmpty);
      for (final command in commands) {
        expect(command.bytes.first, 0xBC);
        expect(
          command.bytes[1],
          0x04,
          reason: 'custom playback must only write the colour command',
        );
      }
    });

    test('refuses a preview-only effect without writing', () async {
      final player = buildPlayer();
      final result = await player.start(effect('custom-meteor'));
      expect(result.outcome, EffectOutcome.unsupported);
      expect(player.isPlaying, isFalse);
      verifyNever(() => ble.sendCommand(any()));
    });

    test('refuses a device pattern without writing', () async {
      final result = await buildPlayer().start(effect('cmode3'));
      expect(result.outcome, EffectOutcome.unsupported);
      verifyNever(() => ble.sendCommand(any()));
    });

    test('reports a transport failure on the very first frame', () async {
      when(() => ble.sendCommand(any())).thenThrow(Exception('boom'));
      final player = buildPlayer();
      final result = await player.start(effect('custom-aurora'));
      expect(result.outcome, EffectOutcome.transportError);
      expect(player.isPlaying, isFalse);
    });

    test('maps a not_connected routing failure', () async {
      when(() => ble.sendCommand(any()))
          .thenThrow(CommandRoutingException('not_connected', 'no link'));
      final result = await buildPlayer().start(effect('custom-aurora'));
      expect(result.outcome, EffectOutcome.notConnected);
    });
  });

  group('streaming', () {
    test('keeps producing frames while playing', () async {
      final player = buildPlayer();
      await player.start(effect('custom-aurora'));
      await Future<void>.delayed(const Duration(milliseconds: 170));
      player.stop();

      final count = verify(() => ble.sendCommand(captureAny())).captured.length;
      expect(count, greaterThanOrEqualTo(2));
    });

    test('sends nothing after stop()', () async {
      var calls = 0;
      when(() => ble.sendCommand(any())).thenAnswer((_) async {
        calls++;
      });
      final player = buildPlayer();
      await player.start(effect('custom-aurora'));
      await Future<void>.delayed(const Duration(milliseconds: 120));
      player.stop();
      final afterStop = calls;
      await Future<void>.delayed(const Duration(milliseconds: 140));
      expect(calls, afterStop);
    });

    test('coalesces frames while a write is still in flight', () async {
      var calls = 0;
      when(() => ble.sendCommand(any())).thenAnswer((_) async {
        calls++;
      });
      final player = buildPlayer();
      await player.start(effect('custom-aurora'));
      expect(calls, 1);

      final gate = Completer<void>();
      when(() => ble.sendCommand(any())).thenAnswer((_) {
        calls++;
        return gate.future;
      });

      await Future<void>.delayed(const Duration(milliseconds: 160));
      // Only one frame may be in flight; the ticks in between were dropped.
      expect(calls, 2);

      player.stop();
      gate.complete();
    });

    test('stops and reports when a frame write fails', () async {
      final player = buildPlayer();
      EffectCommandResult? stopped;
      player.onStopped = (result) => stopped = result;

      await player.start(effect('custom-aurora'));
      when(() => ble.sendCommand(any())).thenThrow(Exception('link lost'));

      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(stopped, isNotNull);
      expect(stopped!.outcome, EffectOutcome.transportError);
      expect(player.isPlaying, isFalse);
      expect(player.effectId, isNull);
    });

    test('invalidate stops playback immediately', () async {
      final player = buildPlayer();
      await player.start(effect('custom-aurora'));
      expect(player.isPlaying, isTrue);

      player.invalidate();
      expect(player.isPlaying, isFalse);
      expect(player.effectId, isNull);
    });
  });

  group('updateParameters', () {
    test('ignores out-of-range values instead of clamping', () {
      final player = buildPlayer();
      player.updateParameters(speed: 999, intensity: -5);
      // Defaults (50/70) are still in range, so validation still passes. If the
      // invalid values had been applied, validate() would reject speed.
      expect(player.validate(effect('custom-aurora')), isNull);
    });
  });
}
