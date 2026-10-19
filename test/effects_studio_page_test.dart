import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:starlight/core/ble/protocol_encoder.dart';
import 'package:starlight/domain/entities/connection_state.dart';
import 'package:starlight/domain/entities/effect.dart';
import 'package:starlight/domain/entities/light_command.dart';
import 'package:starlight/domain/repositories/ble_repository.dart';
import 'package:starlight/domain/repositories/preset_repository.dart';
import 'package:starlight/domain/repositories/saved_device_repository.dart';
import 'package:starlight/domain/services/command_router.dart';
import 'package:starlight/presentation/bloc/ble/ble_bloc.dart';
import 'package:starlight/presentation/bloc/light/light_bloc.dart';
import 'package:starlight/presentation/bloc/light/light_event.dart';
import 'package:starlight/presentation/pages/effects/effects_studio_page.dart';
import 'package:starlight/presentation/theme/app_theme.dart';

class MockBleRepository extends Mock implements BleRepository {}

class MockPresetRepository extends Mock implements PresetRepository {}

class MockSavedDeviceRepository extends Mock implements SavedDeviceRepository {}

bool _sameBytes(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < b.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Effects Studio widget coverage: the two effect kinds, the honest status
/// language, filtering, and the gating/behaviour when disconnected or failing.
void main() {
  late MockBleRepository bleRepository;
  late MockPresetRepository presetRepository;
  late MockSavedDeviceRepository savedRepo;
  late StreamController<DeviceConnectionState> connectionController;
  late StreamController<BluetoothAdapterState> adapterStateController;

  setUpAll(() {
    registerFallbackValue(const LightCommand(type: 'fallback', bytes: []));
  });

  setUp(() {
    bleRepository = MockBleRepository();
    presetRepository = MockPresetRepository();
    savedRepo = MockSavedDeviceRepository();
    connectionController = StreamController<DeviceConnectionState>.broadcast();
    adapterStateController =
        StreamController<BluetoothAdapterState>.broadcast();

    when(() => bleRepository.adapterState)
        .thenAnswer((_) => adapterStateController.stream);
    when(() => bleRepository.adapterStateNow)
        .thenReturn(BluetoothAdapterState.on);
    when(() => bleRepository.connectionState)
        .thenAnswer((_) => connectionController.stream);
    when(() => bleRepository.stateUpdates).thenAnswer((_) => Stream.empty());
    when(() => bleRepository.sendCommand(any())).thenAnswer((_) async {});
    when(() => bleRepository.disconnectDevice()).thenAnswer((_) async {});
    when(() => presetRepository.loadPresets()).thenAnswer((_) async => []);
  });

  tearDown(() async {
    await connectionController.close();
    await adapterStateController.close();
  });

  Future<LightBloc> pumpStudio(
    WidgetTester tester, {
    LightBloc? bloc,
    Size size = const Size(430, 2600),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final bleBloc = BleBloc(bleRepository, savedRepo);
    addTearDown(bleBloc.close);
    final lightBloc = bloc ?? LightBloc(bleRepository, presetRepository);
    addTearDown(lightBloc.close);

    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<BleBloc>.value(value: bleBloc),
          BlocProvider<LightBloc>.value(value: lightBloc),
        ],
        child: MaterialApp(
          theme: buildAppTheme(),
          home: const EffectsStudioPage(),
        ),
      ),
    );
    await tester.pump();
    return lightBloc;
  }

  /// Drives the bloc into a connected state so command actions are enabled.
  Future<void> connect(WidgetTester tester, LightBloc bloc) async {
    bloc.add(const ChangeBrightness(500));
    await tester.pump();
    connectionController.add(DeviceConnectionState.connected);
    await tester.pump();
    await tester.pump();
  }

  testWidgets(
    'shows both device patterns and custom effects with a device chip',
    (tester) async {
      await pumpStudio(tester);

      // A custom effect is selected by default so the signature preview shows.
      expect(find.text('Aurora'), findsWidgets);
      expect(find.text('CUSTOM'), findsOneWidget);
      expect(find.text('Rainbow'), findsWidgets);
      expect(find.text('No device'), findsOneWidget);
      expect(find.text('Preview'), findsOneWidget);
    },
  );

  testWidgets('encodes and sends a device pattern when Send is tapped', (
    tester,
  ) async {
    final bloc = await pumpStudio(tester);
    await connect(tester, bloc);

    await tester.tap(find.text('Rainbow'));
    await tester.pump();

    await tester.tap(find.text('Send to device'));
    await tester.pump();
    await tester.pump();

    final captured = verify(() => bleRepository.sendCommand(captureAny()))
        .captured
        .cast<LightCommand>();
    expect(
      captured.any(
        (c) => _sameBytes(
          c.bytes,
          ProtocolEncoder.setMode(effectById('rainbow')!.protocolModeId!),
        ),
      ),
      isTrue,
    );
    // A device pattern is only ever reported as sent.
    expect(find.text('Sent'), findsOneWidget);
  });

  testWidgets('plays a custom effect as streamed colour and shows Playing', (
    tester,
  ) async {
    final bloc = await pumpStudio(tester);
    await connect(tester, bloc);

    await tester.tap(find.text('Play on device'));
    await tester.pump();
    await tester.pump();

    final captured = verify(() => bleRepository.sendCommand(captureAny()))
        .captured
        .cast<LightCommand>();
    expect(captured.any((c) => c.bytes[1] == 0x04), isTrue);
    expect(find.text('Playing'), findsOneWidget);
    expect(find.text('Stop'), findsOneWidget);

    // Stop the stream so the player's bounded frame timer is not left pending.
    await tester.tap(find.text('Stop'));
    await tester.pump();
  });

  testWidgets('marks an addressable-only effect as preview only', (
    tester,
  ) async {
    await pumpStudio(tester);

    await tester.tap(find.text('Meteor'));
    await tester.pump();

    expect(find.text('Preview only'), findsWidgets);
    // Selecting a preview-only effect must never dispatch a command.
    verifyNever(() => bleRepository.sendCommand(any()));
  });

  testWidgets('explains that playback needs a connection', (tester) async {
    await pumpStudio(tester);
    expect(find.text('Connect a device to play this effect.'), findsOneWidget);
  });

  testWidgets('filters by source (device vs custom)', (tester) async {
    final bloc = await pumpStudio(tester);
    await connect(tester, bloc);

    await tester.tap(find.text('Device'));
    await tester.pump();

    expect(find.text('Rainbow'), findsWidgets);
    expect(find.text('Starlight'), findsNothing);
  });

  testWidgets('filters by category', (tester) async {
    final bloc = await pumpStudio(tester);
    await connect(tester, bloc);

    await tester.tap(find.text('Rhythm').first);
    await tester.pump();

    expect(find.text('Soft Breath'), findsWidgets);
    expect(find.text('Rainbow'), findsNothing);
  });

  testWidgets('reports a failed send and never fakes the selection', (
    tester,
  ) async {
    final bloc = await pumpStudio(tester);
    await connect(tester, bloc);

    await tester.tap(find.text('Rainbow'));
    await tester.pump();

    when(() => bleRepository.sendCommand(any()))
        .thenThrow(Exception('link down'));

    await tester.tap(find.text('Send to device'));
    await tester.pump();
    await tester.pump();

    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.textContaining('link down'), findsOneWidget);
    expect(find.text('Sent'), findsNothing);
  });

  testWidgets('stays usable while disconnected and does not send', (
    tester,
  ) async {
    await pumpStudio(tester);

    await tester.tap(find.text('Rainbow'));
    await tester.pump();

    expect(find.text('Rainbow'), findsWidgets);
    expect(find.text('Connect a device to send this pattern.'), findsOneWidget);
    verifyNever(() => bleRepository.sendCommand(any()));
  });

  testWidgets('lays out without overflow on a narrow phone', (tester) async {
    await pumpStudio(tester, size: const Size(360, 1600));

    expect(find.text('Aurora'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('gates dispatch when the profile exposes no capabilities', (
    tester,
  ) async {
    final router = CommandRouter(bleRepository)
      ..applyProfile(null, capabilities: const {});
    final bloc = LightBloc(bleRepository, presetRepository, router: router);
    await pumpStudio(tester, bloc: bloc);
    // A real (non-initial) state carries the empty capability set.
    bloc.add(LoadPresets());
    await tester.pump();
    await tester.pump();
    connectionController.add(DeviceConnectionState.connected);
    await tester.pump();
    await tester.pump();

    await tester.tap(find.text('Rainbow'));
    await tester.pump();

    expect(
      find.text(
        'This device/profile does not accept controller effect commands.',
      ),
      findsOneWidget,
    );
    verifyNever(() => bleRepository.sendCommand(any()));
  });
}
