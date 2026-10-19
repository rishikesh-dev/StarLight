import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:starlight/data/datasources/device_group_datasource.dart';
import 'package:starlight/data/datasources/theme_preferences.dart';
import 'package:starlight/data/repositories/device_group_repository_impl.dart';
import 'package:starlight/domain/entities/connection_state.dart';
import 'package:starlight/domain/entities/device.dart';
import 'package:starlight/domain/entities/light_command.dart';
import 'package:starlight/domain/entities/preset.dart';
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
import 'package:starlight/presentation/bloc/light/light_bloc.dart';
import 'package:starlight/presentation/bloc/room/room_cubit.dart';
import 'package:starlight/presentation/bloc/scene/scene_bloc.dart';
import 'package:starlight/presentation/bloc/scene/scene_event.dart';
import 'package:starlight/presentation/bloc/theme/theme_cubit.dart'
    show ThemeCubit;
import 'package:starlight/presentation/pages/devices/add_device_page.dart';
import 'package:starlight/presentation/pages/devices/device_detail_page.dart';
import 'package:starlight/presentation/pages/home/home_page.dart';
import 'package:starlight/presentation/pages/settings/settings_page.dart';
import 'package:starlight/presentation/theme/app_theme.dart';

class MockBleRepository extends Mock implements BleRepository {}

class MockSavedDeviceRepository extends Mock implements SavedDeviceRepository {}

class MockDeviceRepository extends Mock implements DeviceRepository {}

class MockPresetRepository extends Mock implements PresetRepository {}

class MockSceneRepository extends Mock implements SceneRepository {}

class MockDeviceGroupRepository extends Mock implements DeviceGroupRepository {}

class MockRoomCubit extends Mock implements RoomCubit {}

class MockDeviceRegistryCubit extends Mock implements DeviceRegistryCubit {}

class FakeDevice extends Fake implements Device {}

/// Proves the active theme reaches every primary screen: the page subtree sees
/// the themed [AppTokens], and representative widgets consume the light
/// palette's colours (not hardcoded graphite values).
void main() {
  late MockBleRepository bleRepository;
  late MockSavedDeviceRepository savedRepo;
  late MockDeviceRepository deviceRepository;
  late MockPresetRepository presetRepository;
  late MockSceneRepository sceneRepository;
  late MockDeviceGroupRepository groupRepository;
  late MockRoomCubit roomCubit;
  late MockDeviceRegistryCubit deviceRegistryCubit;
  late StreamController<DeviceConnectionState> connectionController;
  late StreamController<BluetoothAdapterState> adapterStateController;

  const presets = [Preset(id: 1, name: 'Green', red: 0, green: 255, blue: 0)];

  setUpAll(() {
    registerFallbackValue(const LightCommand(type: 'fallback', bytes: []));
    registerFallbackValue(const SavedDevice(id: 'fallback', name: 'fallback'));
    registerFallbackValue(FakeDevice());
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    bleRepository = MockBleRepository();
    savedRepo = MockSavedDeviceRepository();
    deviceRepository = MockDeviceRepository();
    presetRepository = MockPresetRepository();
    sceneRepository = MockSceneRepository();
    groupRepository = MockDeviceGroupRepository();
    roomCubit = MockRoomCubit();
    deviceRegistryCubit = MockDeviceRegistryCubit();
    connectionController = StreamController<DeviceConnectionState>.broadcast();
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
    when(() => presetRepository.loadPresets()).thenAnswer((_) async => presets);
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
    await connectionController.close();
    await adapterStateController.close();
  });

  BleBloc newBleBloc() {
    final bloc = BleBloc(
      bleRepository,
      savedRepo,
      deviceRepository: deviceRepository,
    );
    addTearDown(bloc.close);
    return bloc;
  }

  LightBloc newLightBloc() {
    final bloc = LightBloc(bleRepository, presetRepository);
    addTearDown(bloc.close);
    return bloc;
  }

  Future<void> pumpThemed(WidgetTester tester, Widget home) async {
    tester.view.physicalSize = const Size(420, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(option: kLightTheme),
        home: home,
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  Future<void> pumpHomeThemed(WidgetTester tester) async {
    final bleBloc = newBleBloc();
    final lightBloc = newLightBloc();
    final sceneBloc = SceneBloc(
      sceneRepository,
      ExecuteScene(
        devices: deviceRepository,
        groups: groupRepository,
        dispatcher: DeviceCommandDispatcher(CommandRouter(bleRepository)),
      ),
    );
    addTearDown(sceneBloc.close);
    await pumpThemed(
      tester,
      MultiBlocProvider(
        providers: [
          BlocProvider<BleBloc>.value(value: bleBloc),
          BlocProvider<LightBloc>.value(value: lightBloc),
          BlocProvider<SceneBloc>.value(value: sceneBloc),
          BlocProvider<RoomCubit>.value(value: roomCubit),
          BlocProvider<DeviceRegistryCubit>.value(value: deviceRegistryCubit),
        ],
        child: HomePage(onAddDevice: () {}),
      ),
    );
  }

  bool hasSurfaceColor(WidgetTester tester, Color color) {
    return tester.widgetList<Container>(find.byType(Container)).any((c) {
          if (c.color == color) return true;
          final d = c.decoration;
          return d is BoxDecoration && d.color == color;
        }) ||
        tester.widgetList<Material>(find.byType(Material)).any((m) {
          // Material color is on the widget itself
          return m.color == color;
        });
  }

  testWidgets('Home consumes the light palette', (tester) async {
    await pumpHomeThemed(tester);

    final context = tester.element(find.byType(HomePage));
    expect(context.tokens, AppTokens.light);
    // The HomePage uses surfaceHigh for hero card and room chips
    expect(hasSurfaceColor(tester, AppTokens.light.surfaceHigh), isTrue);
  });

  testWidgets('Add Device consumes the light palette', (tester) async {
    final bleBloc = newBleBloc();
    await pumpThemed(
      tester,
      BlocProvider<BleBloc>.value(
        value: bleBloc,
        child: const AddDevicePage(embedded: true, active: false),
      ),
    );

    final context = tester.element(find.byType(AddDevicePage));
    expect(context.tokens, AppTokens.light);
    final icon = tester
        .widgetList<Icon>(find.byIcon(Icons.bluetooth_searching))
        .first;
    expect(icon.color, AppTokens.light.onSurfaceVariant);
  });

  testWidgets('Device Detail consumes the light palette', (tester) async {
    final bleBloc = newBleBloc();
    final lightBloc = newLightBloc();
    await pumpThemed(
      tester,
      MultiBlocProvider(
        providers: [
          BlocProvider<BleBloc>.value(value: bleBloc),
          BlocProvider<LightBloc>.value(value: lightBloc),
        ],
        child: const DeviceDetailPage(),
      ),
    );

    final context = tester.element(find.byType(DeviceDetailPage));
    expect(context.tokens, AppTokens.light);
    final icon = tester.widget<Icon>(find.byIcon(Icons.devices_other));
    expect(icon.color, AppTokens.light.onSurfaceVariant);
  });

  testWidgets('Settings consumes the light palette', (tester) async {
    final bleBloc = newBleBloc();
    final themeCubit = ThemeCubit(
      ThemePreferences(await SharedPreferences.getInstance()),
    );
    addTearDown(themeCubit.close);
    await pumpThemed(
      tester,
      MultiBlocProvider(
        providers: [
          BlocProvider<BleBloc>.value(value: bleBloc),
          BlocProvider<ThemeCubit>.value(value: themeCubit),
        ],
        child: const SettingsPage(),
      ),
    );

    final context = tester.element(find.byType(SettingsPage));
    expect(context.tokens, AppTokens.light);
    expect(find.text('Appearance'), findsOneWidget);
    expect(hasSurfaceColor(tester, AppTokens.light.surface), isTrue);
  });
}
