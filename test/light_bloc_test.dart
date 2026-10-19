import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:starlight/domain/entities/connection_state.dart';
import 'package:starlight/domain/entities/device_capability.dart';
import 'package:starlight/domain/entities/device_state_update.dart';
import 'package:starlight/domain/entities/light_command.dart';
import 'package:starlight/domain/entities/preset.dart';
import 'package:starlight/domain/entities/rgb_color.dart';
import 'package:starlight/domain/repositories/ble_repository.dart';
import 'package:starlight/domain/repositories/preset_repository.dart';
import 'package:starlight/presentation/bloc/light/light_bloc.dart';
import 'package:starlight/presentation/bloc/light/light_event.dart';
import 'package:starlight/presentation/bloc/light/light_state.dart';

class MockBleRepository extends Mock implements BleRepository {}

class MockPresetRepository extends Mock implements PresetRepository {}

void main() {
  late MockBleRepository bleRepository;
  late MockPresetRepository presetRepository;
  late StreamController<DeviceConnectionState> connectionController;
  late StreamController<DeviceStateUpdate> stateUpdateController;

  setUpAll(() {
    registerFallbackValue(const LightCommand(type: 'fallback', bytes: []));
  });

  setUp(() {
    bleRepository = MockBleRepository();
    presetRepository = MockPresetRepository();
    connectionController = StreamController<DeviceConnectionState>.broadcast();
    stateUpdateController = StreamController<DeviceStateUpdate>.broadcast();
    when(() => bleRepository.connectionState)
        .thenAnswer((_) => connectionController.stream);
    when(() => bleRepository.stateUpdates).thenAnswer((_) => Stream.empty());
    when(() => presetRepository.loadPresets()).thenAnswer((_) async => []);
  });

  tearDown(() async {
    await connectionController.close();
    await stateUpdateController.close();
  });

  LightBloc buildBloc() => LightBloc(bleRepository, presetRepository);

  LightState connectedSeed() => const LightOn(
    color: RGBColor(255, 0, 0),
    brightness: 500,
    presets: [],
    isConnected: false,
  );

  group('connection propagation', () {
    blocTest<LightBloc, LightState>(
      're-emits state with isConnected=true when the link comes up',
      build: () {
        when(() => bleRepository.sendCommand(any())).thenAnswer((_) async {});
        return buildBloc();
      },
      act: (bloc) async {
        bloc.add(const ChangeBrightness(500));
        await Future<void>.delayed(Duration.zero);
        connectionController.add(DeviceConnectionState.connected);
      },
      wait: const Duration(milliseconds: 20),
      expect: () => [
        isA<LightOn>()
            .having((s) => s.brightness, 'brightness', 500)
            .having((s) => s.isConnected, 'isConnected', false),
        isA<LightOn>()
            .having((s) => s.brightness, 'brightness', 500)
            .having((s) => s.isConnected, 'isConnected', true),
      ],
    );

    blocTest<LightBloc, LightState>(
      'stays silent when the connection state does not change',
      build: buildBloc,
      seed: connectedSeed,
      act: (bloc) =>
          connectionController.add(DeviceConnectionState.disconnected),
      wait: const Duration(milliseconds: 20),
      expect: () => <LightState>[],
    );
  });

  group('device state updates', () {
    blocTest<LightBloc, LightState>(
      'reflects a real power notification from the device',
      build: () {
        when(() => bleRepository.stateUpdates)
            .thenAnswer((_) => stateUpdateController.stream);
        when(() => bleRepository.sendCommand(any())).thenAnswer((_) async {});
        return buildBloc();
      },
      seed: connectedSeed,
      act: (bloc) async {
        // Establish a known brightness, then let a real device notification
        // turn the light off. The off-state must carry the same brightness.
        bloc.add(const ChangeBrightness(500));
        await Future<void>.delayed(Duration.zero);
        stateUpdateController.add(
          const DeviceStateUpdate(type: StateUpdateType.power, value: false),
        );
      },
      wait: const Duration(milliseconds: 20),
      // The brightness command re-emits a state identical to the seed (so it
      // is deduplicated); only the real device notification produces a new
      // state, and it must preserve the known brightness.
      expect: () => [
        isA<LightOff>().having((s) => s.brightness, 'brightness', 500),
      ],
    );

    blocTest<LightBloc, LightState>(
      'reflects a real color notification from the device',
      build: () {
        when(() => bleRepository.stateUpdates)
            .thenAnswer((_) => stateUpdateController.stream);
        return buildBloc();
      },
      seed: connectedSeed,
      act: (bloc) async {
        stateUpdateController.add(
          const DeviceStateUpdate(
            type: StateUpdateType.color,
            value: {'red': 0, 'green': 255, 'blue': 0},
          ),
        );
      },
      wait: const Duration(milliseconds: 20),
      expect: () => [
        isA<LightOn>().having(
          (s) => s.color,
          'color',
          const RGBColor(0, 255, 0),
        ),
      ],
    );

    test('cancels the stateUpdates subscription on close', () async {
      final controller = StreamController<DeviceStateUpdate>.broadcast();
      addTearDown(controller.close);
      when(() => bleRepository.stateUpdates)
          .thenAnswer((_) => controller.stream);
      final bloc = buildBloc();
      // Allow the constructor subscription to attach.
      await Future<void>.delayed(Duration.zero);
      expect(
        controller.hasListener,
        isTrue,
        reason: 'LightBloc must subscribe to real device state updates',
      );
      await bloc.close();
      expect(
        controller.hasListener,
        isFalse,
        reason: 'LightBloc must cancel its stateUpdates subscription',
      );
    });
  });

  group('command failures', () {
    blocTest<LightBloc, LightState>(
      'a failed power command surfaces as LightError, not silence',
      build: () {
        when(() => bleRepository.sendCommand(any()))
            .thenThrow(Exception('link down'));
        return buildBloc();
      },
      act: (bloc) => bloc.add(const TogglePower(true)),
      expect: () => [isA<LightError>()],
    );

    blocTest<LightBloc, LightState>(
      'a successful power command emits the new on-state',
      build: () {
        when(() => bleRepository.sendCommand(any())).thenAnswer((_) async {});
        return buildBloc();
      },
      act: (bloc) => bloc.add(const TogglePower(true)),
      expect: () => [isA<LightOn>()],
    );
  });

  group('presets', () {
    blocTest<LightBloc, LightState>(
      'LoadPresets emits the stored presets',
      build: () {
        when(() => presetRepository.loadPresets()).thenAnswer(
          (_) async => [
            const Preset(id: 1, name: 'Red', red: 255, green: 0, blue: 0),
          ],
        );
        return buildBloc();
      },
      act: (bloc) => bloc.add(LoadPresets()),
      expect: () => [
        isA<PresetsLoaded>().having((s) => s.presets, 'presets', hasLength(1)),
      ],
    );
  });

  group('effects', () {
    blocTest<LightBloc, LightState>(
      'a confirmed effect write emits EffectChanged carrying the name',
      build: () {
        when(() => bleRepository.sendCommand(any())).thenAnswer((_) async {});
        return buildBloc();
      },
      act: (bloc) => bloc.add(const ChangeEffect('Rainbow')),
      expect: () => [
        isA<EffectChanged>()
            .having((s) => s.effect, 'effect', 'Rainbow')
            .having((s) => s.isOn, 'isOn', true),
      ],
    );

    blocTest<LightBloc, LightState>(
      'a failed effect write surfaces as LightError, not a fake selection',
      build: () {
        when(() => bleRepository.sendCommand(any()))
            .thenThrow(Exception('link down'));
        return buildBloc();
      },
      act: (bloc) => bloc.add(const ChangeEffect('Rainbow')),
      expect: () => [isA<LightError>()],
    );

    blocTest<LightBloc, LightState>(
      'a confirmed speed write emits EffectChanged carrying the value',
      build: () {
        when(() => bleRepository.sendCommand(any())).thenAnswer((_) async {});
        return buildBloc();
      },
      act: (bloc) => bloc.add(const ChangeSpeed(80)),
      expect: () => [
        isA<EffectChanged>()
            .having((s) => s.speed, 'speed', 80)
            .having((s) => s.effect, 'effect', isNull),
      ],
    );

    blocTest<LightBloc, LightState>(
      'the default capability set exposes effect and speed',
      build: buildBloc,
      seed: connectedSeed,
      verify: (bloc) {
        final state = bloc.state;
        expect(state.capabilities, contains(DeviceCapability.effect));
        expect(state.capabilities, contains(DeviceCapability.speed));
      },
    );

    blocTest<LightBloc, LightState>(
      'an unknown effect surfaces as LightError without touching the transport',
      build: buildBloc,
      act: (bloc) => bloc.add(const ChangeEffect('NotARealEffect')),
      expect: () => [isA<LightError>()],
      verify: (_) => verifyNever(() => bleRepository.sendCommand(any())),
    );

    blocTest<LightBloc, LightState>(
      'an out-of-range speed surfaces as LightError without a send',
      build: buildBloc,
      act: (bloc) => bloc.add(const ChangeSpeed(101)),
      expect: () => [isA<LightError>()],
      verify: (_) => verifyNever(() => bleRepository.sendCommand(any())),
    );
  });
}
