import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:starlight/domain/entities/connection_state.dart';
import 'package:starlight/domain/entities/light_command.dart';
import 'package:starlight/domain/repositories/ble_repository.dart';
import 'package:starlight/domain/repositories/preset_repository.dart';
import 'package:starlight/presentation/bloc/light/light_bloc.dart';
import 'package:starlight/presentation/bloc/light/light_event.dart';
import 'package:starlight/presentation/bloc/light/light_state.dart';
import 'package:starlight/presentation/bloc/light/light_state_view.dart';

class MockBleRepository extends Mock implements BleRepository {}

class MockPresetRepository extends Mock implements PresetRepository {}

/// Custom-effect playback bookkeeping at the bloc level: a selection is only
/// recorded after the player's first frame was accepted, manual control takes
/// over, and disconnecting stops the stream.
void main() {
  late MockBleRepository bleRepository;
  late MockPresetRepository presetRepository;
  late StreamController<DeviceConnectionState> connectionController;

  setUpAll(() {
    registerFallbackValue(const LightCommand(type: 'fallback', bytes: []));
  });

  setUp(() {
    bleRepository = MockBleRepository();
    presetRepository = MockPresetRepository();
    connectionController = StreamController<DeviceConnectionState>.broadcast();
    when(() => bleRepository.connectionState)
        .thenAnswer((_) => connectionController.stream);
    when(() => bleRepository.stateUpdates).thenAnswer((_) => Stream.empty());
    when(() => bleRepository.sendCommand(any())).thenAnswer((_) async {});
    when(() => presetRepository.loadPresets()).thenAnswer((_) async => []);
  });

  tearDown(() async {
    await connectionController.close();
  });

  LightBloc buildBloc() {
    final bloc = LightBloc(bleRepository, presetRepository);
    addTearDown(bloc.close);
    return bloc;
  }

  Future<void> flush() =>
      Future<void>.delayed(const Duration(milliseconds: 20));

  test(
    'records a custom effect only once the first frame was accepted',
    () async {
      final bloc = buildBloc();

      bloc.add(const PlayCustomEffect('custom-aurora'));
      await flush();

      expect(bloc.state, isA<EffectChanged>());
      final state = bloc.state as EffectChanged;
      expect(state.customEffectId, 'custom-aurora');
      expect(state.customPlaying, isTrue);
      // Streaming colours replaced any device pattern.
      expect(state.effect, isNull);
    },
  );

  test(
    'emits an error and records nothing when the first frame fails',
    () async {
      when(() => bleRepository.sendCommand(any()))
          .thenThrow(Exception('link down'));
      final bloc = buildBloc();

      bloc.add(const PlayCustomEffect('custom-aurora'));
      await flush();

      expect(bloc.state, isA<LightError>());
      expect(bloc.state.lightCustomPlaying, isFalse);
      expect(bloc.state.lightCustomEffectId, isNull);
    },
  );

  test('rejects a preview-only effect without sending anything', () async {
    final bloc = buildBloc();

    bloc.add(const PlayCustomEffect('custom-meteor'));
    await flush();

    expect(bloc.state, isA<LightError>());
    verifyNever(() => bleRepository.sendCommand(any()));
  });

  test('rejects an unknown effect id', () async {
    final bloc = buildBloc();

    bloc.add(const PlayCustomEffect('does-not-exist'));
    await flush();

    expect(bloc.state, isA<LightError>());
  });

  test('stopping clears the custom playback bookkeeping', () async {
    final bloc = buildBloc();

    bloc.add(const PlayCustomEffect('custom-aurora'));
    await flush();
    expect(bloc.state.lightCustomPlaying, isTrue);

    bloc.add(const StopCustomEffect());
    await flush();

    expect(bloc.state.lightCustomPlaying, isFalse);
    expect(bloc.state.lightCustomEffectId, isNull);
  });

  test('configuring parameters is reflected live while playing', () async {
    final bloc = buildBloc();

    bloc.add(const PlayCustomEffect('custom-aurora'));
    await flush();

    bloc.add(
      const ConfigureCustomEffect(speed: 20, intensity: 40, paletteId: 'ember'),
    );
    await flush();

    final state = bloc.state as EffectChanged;
    expect(state.customSpeed, 20);
    expect(state.customIntensity, 40);
    expect(state.customPaletteId, 'ember');
  });

  test('a manual brightness change takes over from custom playback', () async {
    final bloc = buildBloc();

    bloc.add(const PlayCustomEffect('custom-aurora'));
    await flush();
    expect(bloc.state.lightCustomPlaying, isTrue);

    bloc.add(const ChangeBrightness(500));
    await flush();

    expect(bloc.state.lightCustomPlaying, isFalse);
    expect(bloc.state.lightCustomEffectId, isNull);
  });

  test('disconnecting stops custom playback', () async {
    final bloc = buildBloc();

    bloc.add(const ChangeBrightness(500));
    await flush();
    connectionController.add(DeviceConnectionState.connected);
    await flush();

    bloc.add(const PlayCustomEffect('custom-aurora'));
    await flush();
    expect(bloc.state.lightCustomPlaying, isTrue);

    connectionController.add(DeviceConnectionState.disconnected);
    await flush();

    expect(bloc.state.lightCustomPlaying, isFalse);
    expect(bloc.state.lightCustomEffectId, isNull);
  });
}
