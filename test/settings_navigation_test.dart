import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:starlight/data/datasources/theme_preferences.dart';
import 'package:starlight/domain/entities/connection_state.dart';
import 'package:starlight/domain/entities/device.dart';
import 'package:starlight/domain/entities/light_command.dart';
import 'package:starlight/domain/entities/saved_device.dart';
import 'package:starlight/domain/repositories/ble_repository.dart';
import 'package:starlight/domain/repositories/device_repository.dart';
import 'package:starlight/domain/repositories/preset_repository.dart';
import 'package:starlight/domain/repositories/profile_assignment_repository.dart';
import 'package:starlight/domain/repositories/device_profile_repository.dart';
import 'package:starlight/domain/repositories/saved_device_repository.dart';
import 'package:starlight/domain/services/command_router.dart';
import 'package:starlight/presentation/bloc/ble/ble_bloc.dart';
import 'package:starlight/presentation/bloc/light/light_bloc.dart';
import 'package:starlight/presentation/bloc/profile/profile_cubit.dart';
import 'package:starlight/presentation/bloc/theme/theme_cubit.dart';
import 'package:starlight/presentation/pages/effects/effects_studio_page.dart';
import 'package:starlight/presentation/pages/settings/diagnostics_page.dart';
import 'package:starlight/presentation/pages/settings/settings_page.dart';
import 'package:starlight/presentation/theme/app_theme.dart';

import 'support/fake_profile_executor.dart';

class MockBleRepository extends Mock implements BleRepository {}

class MockSavedDeviceRepository extends Mock implements SavedDeviceRepository {}

class MockDeviceRepository extends Mock implements DeviceRepository {}

class MockPresetRepository extends Mock implements PresetRepository {}

class MockDeviceProfileRepository extends Mock
    implements DeviceProfileRepository {}

class MockProfileAssignmentRepository extends Mock
    implements ProfileAssignmentRepository {}

class FakeSavedDevice extends Fake implements SavedDevice {}

class FakeDevice extends Fake implements Device {}

/// Settings must never present a dead destination: every row either navigates
/// somewhere real or is visibly labelled as unavailable.
void main() {
  late MockBleRepository bleRepository;
  late MockSavedDeviceRepository savedRepo;
  late MockDeviceRepository deviceRepository;
  late MockPresetRepository presetRepository;
  late MockDeviceProfileRepository profileRepository;
  late MockProfileAssignmentRepository assignmentRepository;
  late FakeProfileExecutor profileExecutor;
  late StreamController<DeviceConnectionState> connectionController;
  late StreamController<BluetoothAdapterState> adapterController;

  setUpAll(() {
    registerFallbackValue(const LightCommand(type: 'fallback', bytes: []));
    registerFallbackValue(FakeSavedDevice());
    registerFallbackValue(FakeDevice());
  });

  setUp(() {
    bleRepository = MockBleRepository();
    savedRepo = MockSavedDeviceRepository();
    deviceRepository = MockDeviceRepository();
    presetRepository = MockPresetRepository();
    profileRepository = MockDeviceProfileRepository();
    assignmentRepository = MockProfileAssignmentRepository();
    profileExecutor = FakeProfileExecutor();
    connectionController = StreamController<DeviceConnectionState>.broadcast();
    adapterController = StreamController<BluetoothAdapterState>.broadcast();

    when(() => bleRepository.adapterState)
        .thenAnswer((_) => adapterController.stream);
    when(() => bleRepository.adapterStateNow)
        .thenReturn(BluetoothAdapterState.on);
    when(() => bleRepository.isBluetoothEnabled())
        .thenAnswer((_) async => true);
    when(() => bleRepository.hasPermissions()).thenAnswer((_) async => true);
    when(() => bleRepository.waitForAdapterOn()).thenAnswer((_) async => true);
    when(() => bleRepository.isSupported()).thenAnswer((_) async => true);
    when(() => bleRepository.enableBluetooth()).thenAnswer((_) async => true);
    when(() => bleRepository.scanDevices()).thenAnswer((_) => Stream.empty());
    when(() => bleRepository.stopScan()).thenAnswer((_) async {});
    when(() => bleRepository.connectionState)
        .thenAnswer((_) => connectionController.stream);
    when(() => bleRepository.stateUpdates).thenAnswer((_) => Stream.empty());
    when(() => bleRepository.sendCommand(any())).thenAnswer((_) async {});
    when(() => bleRepository.disconnectDevice()).thenAnswer((_) async {});
    when(() => savedRepo.load()).thenAnswer((_) async => null);
    when(() => savedRepo.save(any())).thenAnswer((_) async {});
    when(() => deviceRepository.updateDevice(any())).thenAnswer((_) async {});
    when(() => deviceRepository.getDevice(any())).thenAnswer((_) async => null);
    when(() => presetRepository.loadPresets()).thenAnswer((_) async => []);
    when(() => profileRepository.loadProfiles()).thenAnswer((_) async => []);
    when(() => assignmentRepository.loadAssignments())
        .thenAnswer((_) async => <String, String>{});
  });

  tearDown(() async {
    await connectionController.close();
    await adapterController.close();
  });

  Future<void> pumpSettings(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 2200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final bleBloc = BleBloc(
      bleRepository,
      savedRepo,
      deviceRepository: deviceRepository,
    );
    final lightBloc = LightBloc(bleRepository, presetRepository);
    addTearDown(bleBloc.close);
    addTearDown(lightBloc.close);

    final router = CommandRouter(bleRepository, executor: profileExecutor);
    final profileCubit = ProfileCubit(
      repository: profileRepository,
      assignments: assignmentRepository,
      executor: profileExecutor,
      router: router,
    );
    addTearDown(profileCubit.close);
    addTearDown(profileExecutor.dispose);
    addTearDown(router.dispose);
    await profileCubit.load();

    SharedPreferences.setMockInitialValues({});
    final themeCubit = ThemeCubit(
      ThemePreferences(await SharedPreferences.getInstance()),
    );
    addTearDown(themeCubit.close);

    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<BleBloc>.value(value: bleBloc),
          BlocProvider<LightBloc>.value(value: lightBloc),
          BlocProvider<ProfileCubit>.value(value: profileCubit),
          BlocProvider<ThemeCubit>.value(value: themeCubit),
        ],
        child: MaterialApp(
          theme: buildAppTheme(),
          home: const SettingsPage(),
          routes: {
            '/effects': (_) => const EffectsStudioPage(),
            '/diagnostics': (_) => const DiagnosticsPage(),
          },
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('lists real destinations and labels the unavailable ones', (
    tester,
  ) async {
    await pumpSettings(tester);

    expect(find.widgetWithText(ListTile, 'Device profiles'), findsOneWidget);
    expect(find.widgetWithText(ListTile, 'Effects library'), findsOneWidget);
    expect(find.widgetWithText(ListTile, 'Diagnostics'), findsOneWidget);

    // Placeholders are honest about not being implemented.
    expect(
      find.widgetWithText(ListTile, 'Installed extensions'),
      findsOneWidget,
    );
    expect(find.widgetWithText(ListTile, 'Integrations'), findsOneWidget);
    expect(find.text('Not implemented in this build'), findsNWidgets(2));
  });

  testWidgets('opens the Effects Studio', (tester) async {
    await pumpSettings(tester);

    await tester.tap(find.widgetWithText(ListTile, 'Effects library'));
    // The studio runs a continuous preview animation, so a bounded pump is
    // used instead of pumpAndSettle (the animation never settles by design).
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(EffectsStudioPage), findsOneWidget);
    expect(find.text('Effects Studio'), findsOneWidget);
    expect(find.text('CUSTOM'), findsWidgets);
  });

  testWidgets('opens Diagnostics', (tester) async {
    await pumpSettings(tester);

    await tester.tap(find.widgetWithText(ListTile, 'Diagnostics'));
    await tester.pumpAndSettle();

    expect(find.text('GATT (MR Star)'), findsOneWidget);
    expect(find.text('Last confirmed light values'), findsOneWidget);
  });
}
