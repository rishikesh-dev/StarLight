import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:starlight/data/datasources/theme_preferences.dart';
import 'package:starlight/domain/entities/light_command.dart';
import 'package:starlight/domain/repositories/ble_repository.dart';
import 'package:starlight/domain/repositories/device_repository.dart';
import 'package:starlight/domain/repositories/preset_repository.dart';
import 'package:starlight/domain/repositories/scene_repository.dart';
import 'package:starlight/domain/repositories/saved_device_repository.dart';
import 'package:starlight/presentation/app_shell.dart';
import 'package:starlight/presentation/bloc/registry/device_registry_cubit.dart';
import 'package:starlight/presentation/bloc/ble/ble_bloc.dart';
import 'package:starlight/presentation/bloc/ble/ble_state.dart';
import 'package:starlight/presentation/bloc/light/light_bloc.dart';
import 'package:starlight/data/datasources/device_group_datasource.dart';
import 'package:starlight/data/repositories/device_group_repository_impl.dart';
import 'package:starlight/domain/services/command_router.dart';
import 'package:starlight/domain/services/device_command_dispatcher.dart'
    show DeviceCommandDispatcher;
import 'package:starlight/domain/usecases/execute_scene.dart';
import 'package:starlight/presentation/bloc/room/room_cubit.dart';
import 'package:starlight/presentation/bloc/scene/scene_bloc.dart'
    show SceneBloc;
import 'package:starlight/presentation/bloc/scene/scene_event.dart'
    show ExecuteScene;
import 'package:starlight/presentation/bloc/theme/theme_cubit.dart'
    show ThemeCubit;
import 'package:starlight/presentation/app_shell.dart';

class MockBleRepository extends Mock implements BleRepository {}

class MockSavedDeviceRepository extends Mock implements SavedDeviceRepository {}

class MockDeviceRepository extends Mock implements DeviceRepository {}

class MockPresetRepository extends Mock implements PresetRepository {}

class MockSceneRepository extends Mock implements SceneRepository {}

class MockRoomCubit extends Mock implements RoomCubit {}

class MockDeviceRegistryCubit extends Mock implements DeviceRegistryCubit {}

/// Guards the startup regression where the permission dialog emits
/// [AppLifecycleState.inactive], which the shell used to treat as "backgrounded"
/// and answer with [StopScanRequested] — tearing down the scan while the
/// startup readiness flow was still running.
void main() {
  late MockBleRepository bleRepository;
  late MockSavedDeviceRepository savedRepo;
  late MockDeviceRepository deviceRepository;
  late MockPresetRepository presetRepository;
  late MockSceneRepository sceneRepository;
  late MockRoomCubit roomCubit;
  late MockDeviceRegistryCubit deviceRegistryCubit;
  late StreamController<BluetoothAdapterState> adapterStateController;

  setUpAll(() {
    registerFallbackValue(const LightCommand(type: 'fallback', bytes: []));
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    bleRepository = MockBleRepository();
    savedRepo = MockSavedDeviceRepository();
    deviceRepository = MockDeviceRepository();
    presetRepository = MockPresetRepository();
    sceneRepository = MockSceneRepository();
    roomCubit = MockRoomCubit();
    deviceRegistryCubit = MockDeviceRegistryCubit();
    adapterStateController =
        StreamController<BluetoothAdapterState>.broadcast();

    when(() => bleRepository.adapterState)
        .thenAnswer((_) => adapterStateController.stream);
    when(() => bleRepository.adapterStateNow)
        .thenReturn(BluetoothAdapterState.on);
    when(() => bleRepository.hasPermissions()).thenAnswer((_) async => true);
    when(() => bleRepository.isBluetoothEnabled())
        .thenAnswer((_) async => true);
    when(() => bleRepository.waitForAdapterOn()).thenAnswer((_) async => true);
    when(() => bleRepository.isSupported()).thenAnswer((_) async => true);
    when(() => bleRepository.enableBluetooth()).thenAnswer((_) async => true);
    when(() => bleRepository.scanDevices()).thenAnswer((_) => Stream.empty());
    when(() => bleRepository.stopScan()).thenAnswer((_) async => {});
    when(() => bleRepository.disconnectDevice()).thenAnswer((_) async => {});
    when(() => bleRepository.connectionState).thenAnswer((_) => Stream.empty());
    when(() => bleRepository.stateUpdates).thenAnswer((_) => Stream.empty());
    when(() => bleRepository.sendCommand(any())).thenAnswer((_) async => {});
    when(() => bleRepository.readRssi()).thenAnswer((_) async => null);
    when(() => presetRepository.loadPresets()).thenAnswer((_) async => []);
    when(() => sceneRepository.loadScenes()).thenAnswer((_) async => []);
    when(() => roomCubit.state).thenReturn(const RoomState(rooms: []));
    when(() => roomCubit.stream)
        .thenAnswer((_) => Stream.value(const RoomState(rooms: [])));
    when(() => deviceRegistryCubit.state)
        .thenReturn(const DeviceRegistryState(devices: []));
    when(
      () => deviceRegistryCubit.stream,
    ).thenAnswer((_) => Stream.value(const DeviceRegistryState(devices: [])));
  });

  tearDown(() async {
    await adapterStateController.close();
  });

  Future<BleBloc> pumpShell(WidgetTester tester) async {
    final bloc = BleBloc(
      bleRepository,
      savedRepo,
      deviceRepository: deviceRepository,
    );
    addTearDown(bloc.close);
    final lightBloc = LightBloc(bleRepository, presetRepository);
    addTearDown(lightBloc.close);
    final sceneBloc = SceneBloc(
      sceneRepository,
      ExecuteScene(
        devices: deviceRepository,
        groups: DeviceGroupRepositoryImpl(
          DeviceGroupDataSource(await SharedPreferences.getInstance()),
          deviceRepository,
        ),
        dispatcher: DeviceCommandDispatcher(CommandRouter(bleRepository)),
      ),
    );
    addTearDown(sceneBloc.close);
    final themeCubit = ThemeCubit(
      ThemePreferences(await SharedPreferences.getInstance()),
    );
    addTearDown(themeCubit.close);
    await tester.pumpWidget(
      MaterialApp(
        home: MultiBlocProvider(
          providers: [
            BlocProvider<BleBloc>.value(value: bloc),
            BlocProvider<LightBloc>.value(value: lightBloc),
            BlocProvider<SceneBloc>.value(value: sceneBloc),
            BlocProvider<RoomCubit>.value(value: roomCubit),
            BlocProvider<DeviceRegistryCubit>.value(value: deviceRegistryCubit),
            BlocProvider<ThemeCubit>.value(value: themeCubit),
          ],
          child: const AppShell(),
        ),
      ),
    );
    await tester.pump();
    return bloc;
  }

  testWidgets('shell renders the nav bar with no demo status strip', (
    tester,
  ) async {
    await pumpShell(tester);

    // The bottom bar reserves its own space and is the only persistent chrome;
    // the old fabricated demo strip (device/address, ON, brightness, colour)
    // is gone from the shell entirely — real state lives on Home and in
    // Diagnostics.
    expect(find.byType(BottomBar), findsOneWidget);
    expect(find.text('GATT--DEMO'), findsNothing);
    expect(find.text('ON'), findsNothing);
    expect(find.text('100%'), findsNothing);
    expect(find.text('#FF0000'), findsNothing);
    // Home content renders above the bar, not underneath it.
    expect(find.text('No lights yet'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('inactive (system dialog) does not stop the scan', (
    tester,
  ) async {
    await pumpShell(tester);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();

    verifyNever(() => bleRepository.stopScan());
  });

  testWidgets('paused (backgrounded) stops the scan', (tester) async {
    await pumpShell(tester);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();

    verify(() => bleRepository.stopScan()).called(1);

    // Restore frame scheduling for the rest of the test run.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });

  testWidgets('resumed re-checks the adapter without requesting enable', (
    tester,
  ) async {
    final bloc = await pumpShell(tester);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    expect(bloc.state, isA<BleDisconnected>());
    verifyNever(() => bleRepository.stopScan());
    verifyNever(() => bleRepository.enableBluetooth());
  });
}
