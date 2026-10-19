import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:starlight/data/datasources/theme_preferences.dart';
import 'package:starlight/domain/entities/ble_device.dart';
import 'package:starlight/domain/entities/connection_state.dart';
import 'package:starlight/domain/entities/device.dart';
import 'package:starlight/domain/entities/light_command.dart';
import 'package:starlight/domain/entities/saved_device.dart';
import 'package:starlight/domain/repositories/ble_repository.dart';
import 'package:starlight/domain/repositories/device_group_repository.dart';
import 'package:starlight/domain/repositories/device_repository.dart';
import 'package:starlight/domain/repositories/preset_repository.dart';
import 'package:starlight/domain/repositories/scene_repository.dart';
import 'package:starlight/domain/repositories/saved_device_repository.dart';
import 'package:starlight/domain/services/command_router.dart';
import 'package:starlight/domain/services/device_command_dispatcher.dart';
import 'package:starlight/domain/usecases/execute_scene.dart';
import 'package:starlight/presentation/bloc/registry/device_registry_cubit.dart';
import 'package:starlight/presentation/bloc/ble/ble_bloc.dart';
import 'package:starlight/presentation/bloc/ble/ble_event.dart';
import 'package:starlight/presentation/bloc/light/light_bloc.dart';
import 'package:starlight/presentation/bloc/room/room_cubit.dart';
import 'package:starlight/presentation/bloc/scene/scene_bloc.dart';
import 'package:starlight/presentation/bloc/theme/theme_cubit.dart';
import 'package:starlight/presentation/pages/home/home_page.dart';
import 'package:starlight/presentation/pages/settings/settings_page.dart';

class MockBleRepository extends Mock implements BleRepository {}

class MockSavedDeviceRepository extends Mock implements SavedDeviceRepository {}

class MockDeviceRepository extends Mock implements DeviceRepository {}

class MockPresetRepository extends Mock implements PresetRepository {}

class MockSceneRepository extends Mock implements SceneRepository {}

class MockDeviceGroupRepository extends Mock implements DeviceGroupRepository {}

class MockRoomCubit extends Mock implements RoomCubit {}

class MockDeviceRegistryCubit extends Mock implements DeviceRegistryCubit {}

class FakeSavedDevice extends Fake implements SavedDevice {}

class FakeDevice extends Fake implements Device {}

void main() {
  late MockBleRepository bleRepository;
  late MockSavedDeviceRepository savedRepo;
  late MockDeviceRepository deviceRepository;
  late MockPresetRepository presetRepository;
  late MockSceneRepository sceneRepository;
  late MockDeviceGroupRepository groupRepository;
  late MockRoomCubit roomCubit;
  late MockDeviceRegistryCubit deviceRegistryCubit;
  late StreamController<List<BleDevice>> scanController;
  late StreamController<DeviceConnectionState> connectionController;
  late StreamController<BluetoothAdapterState> adapterStateController;

  setUpAll(() {
    registerFallbackValue(
      const BleDevice(id: '', name: '', rssi: 0, isConnected: false),
    );
    registerFallbackValue(FakeSavedDevice());
    registerFallbackValue(FakeDevice());
    registerFallbackValue(const LightCommand(type: 'fallback', bytes: []));
  });

  setUp(() {
    bleRepository = MockBleRepository();
    savedRepo = MockSavedDeviceRepository();
    deviceRepository = MockDeviceRepository();
    presetRepository = MockPresetRepository();
    sceneRepository = MockSceneRepository();
    groupRepository = MockDeviceGroupRepository();
    roomCubit = MockRoomCubit();
    deviceRegistryCubit = MockDeviceRegistryCubit();
    scanController = StreamController<List<BleDevice>>.broadcast();
    connectionController = StreamController<DeviceConnectionState>.broadcast();
    adapterStateController =
        StreamController<BluetoothAdapterState>.broadcast();

    when(() => bleRepository.hasPermissions()).thenAnswer((_) async => true);
    when(() => bleRepository.waitForAdapterOn()).thenAnswer((_) async => true);
    when(() => bleRepository.adapterState)
        .thenAnswer((_) => adapterStateController.stream);
    when(() => bleRepository.adapterStateNow)
        .thenReturn(BluetoothAdapterState.on);
    when(() => bleRepository.isSupported()).thenAnswer((_) async => true);
    when(() => bleRepository.enableBluetooth()).thenAnswer((_) async => true);
    when(() => bleRepository.scanDevices())
        .thenAnswer((_) => scanController.stream);
    when(() => bleRepository.stopScan()).thenAnswer((_) async => {});
    when(() => bleRepository.connectDevice(any()))
        .thenAnswer((_) => connectionController.stream);
    when(() => bleRepository.disconnectDevice()).thenAnswer((_) async => {});
    when(() => bleRepository.connectionState)
        .thenAnswer((_) => connectionController.stream);
    when(() => bleRepository.stateUpdates).thenAnswer((_) => Stream.empty());
    when(() => bleRepository.sendCommand(any())).thenAnswer((_) async => {});
    when(() => bleRepository.readRssi()).thenAnswer((_) async => null);
    when(() => savedRepo.load()).thenAnswer((_) async => null);
    when(() => savedRepo.save(any())).thenAnswer((_) async => {});
    when(() => deviceRepository.updateDevice(any()))
        .thenAnswer((_) async => {});
    when(() => deviceRepository.getDevice(any())).thenAnswer((_) async => null);
    when(() => presetRepository.loadPresets()).thenAnswer((_) async => []);
    when(() => sceneRepository.loadScenes()).thenAnswer((_) async => []);
    when(() => groupRepository.getGroups()).thenAnswer((_) async => []);
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
    await scanController.close();
    await connectionController.close();
    await adapterStateController.close();
  });

  Future<BleBloc> pumpHome(WidgetTester tester) async {
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
        groups: groupRepository,
        dispatcher: DeviceCommandDispatcher(CommandRouter(bleRepository)),
      ),
    );
    addTearDown(sceneBloc.close);
    await tester.pumpWidget(
      MaterialApp(
        home: MultiBlocProvider(
          providers: [
            BlocProvider<BleBloc>.value(value: bloc),
            BlocProvider<LightBloc>.value(value: lightBloc),
            BlocProvider<SceneBloc>.value(value: sceneBloc),
            BlocProvider<RoomCubit>.value(value: roomCubit),
            BlocProvider<DeviceRegistryCubit>.value(value: deviceRegistryCubit),
          ],
          child: HomePage(onAddDevice: () {}),
        ),
      ),
    );
    await tester.pump();
    return bloc;
  }

  testWidgets('home shows a clear no-device state initially', (tester) async {
    await pumpHome(tester);
    expect(find.text('No lights yet'), findsOneWidget);
    expect(find.text('Add Device'), findsWidgets);
  });

  testWidgets('home reflects a Bluetooth-off state with a turn-on action', (
    tester,
  ) async {
    when(() => bleRepository.isBluetoothEnabled())
        .thenAnswer((_) async => false);
    when(() => bleRepository.adapterStateNow)
        .thenReturn(BluetoothAdapterState.off);
    when(() => bleRepository.enableBluetooth()).thenAnswer((_) async => false);

    final bloc = await pumpHome(tester);
    bloc.add(const EnsureBluetoothReady());
    await tester.pumpAndSettle();

    expect(find.text('Bluetooth is off'), findsOneWidget);
    expect(find.text('Turn on Bluetooth'), findsOneWidget);
  });

  testWidgets('home reflects a permanently denied permission with settings', (
    tester,
  ) async {
    when(() => bleRepository.hasPermissions()).thenAnswer((_) async => false);
    when(() => bleRepository.requestPermissions())
        .thenAnswer((_) async => false);
    when(() => bleRepository.isPermanentlyDenied())
        .thenAnswer((_) async => true);

    final bloc = await pumpHome(tester);
    bloc.add(const EnsureBluetoothReady());
    await tester.pumpAndSettle();

    expect(find.text('Permission needed'), findsOneWidget);
    expect(find.text('Open settings'), findsOneWidget);
  });

  testWidgets('settings reflects the Bluetooth-off state', (tester) async {
    when(() => bleRepository.isBluetoothEnabled())
        .thenAnswer((_) async => false);
    when(() => bleRepository.adapterStateNow)
        .thenReturn(BluetoothAdapterState.off);
    when(() => bleRepository.enableBluetooth()).thenAnswer((_) async => false);

    final bloc = BleBloc(
      bleRepository,
      savedRepo,
      deviceRepository: deviceRepository,
    );
    addTearDown(bloc.close);
    SharedPreferences.setMockInitialValues({});
    final themeCubit = ThemeCubit(
      ThemePreferences(await SharedPreferences.getInstance()),
    );
    addTearDown(themeCubit.close);
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: MultiBlocProvider(
          providers: [
            BlocProvider<BleBloc>.value(value: bloc),
            BlocProvider<ThemeCubit>.value(value: themeCubit),
          ],
          child: const SettingsPage(),
        ),
      ),
    );
    bloc.add(const EnsureBluetoothReady());
    await tester.pumpAndSettle();

    expect(find.text('Bluetooth is off'), findsOneWidget);
    // The Appearance section is part of Settings.
    expect(find.text('Appearance'), findsOneWidget);
    expect(find.text('Graphite + Purple'), findsOneWidget);
  });
}
