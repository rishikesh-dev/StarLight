// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:starlight/presentation/app_shell.dart';
import 'package:starlight/presentation/pages/devices/add_device_page.dart';
import 'package:starlight/presentation/pages/debug/hardware_lab_page.dart';
import 'package:starlight/presentation/pages/effects/effects_studio_page.dart';
import 'package:starlight/presentation/pages/groups/groups_page.dart';
import 'package:starlight/presentation/pages/rooms/rooms_page.dart';
import 'package:starlight/presentation/pages/scenes/scenes_page.dart';
import 'package:starlight/presentation/pages/settings/diagnostics_page.dart';
import 'package:starlight/presentation/pages/devices/device_detail_page.dart';
import 'package:starlight/presentation/theme/app_theme.dart';

import 'package:starlight/core/utils/app_logger.dart';
import 'package:starlight/data/adapters/ble_gatt_profile_executor.dart';
import 'package:starlight/data/adapters/starlight_ble_adapter.dart';
import 'package:starlight/data/datasources/ble_datasource.dart';
import 'package:starlight/data/datasources/device_datasource.dart';
import 'package:starlight/data/datasources/device_group_datasource.dart';
import 'package:starlight/data/datasources/preset_datasource.dart';
import 'package:starlight/data/datasources/profile_datasource.dart';
import 'package:starlight/data/datasources/room_datasource.dart';
import 'package:starlight/data/datasources/scene_datasource.dart';
import 'package:starlight/data/datasources/theme_preferences.dart';
import 'package:starlight/data/repositories/ble_repository_impl.dart';
import 'package:starlight/data/repositories/device_group_repository_impl.dart';
import 'package:starlight/data/repositories/device_profile_repository_impl.dart';
import 'package:starlight/data/repositories/device_repository_impl.dart';
import 'package:starlight/data/repositories/preset_repository_impl.dart';
import 'package:starlight/data/repositories/profile_assignment_repository_impl.dart';
import 'package:starlight/data/repositories/room_repository_impl.dart';
import 'package:starlight/data/repositories/saved_device_repository_impl.dart';
import 'package:starlight/data/repositories/scene_repository_impl.dart';
import 'package:starlight/domain/services/command_router.dart';
import 'package:starlight/domain/services/device_command_dispatcher.dart';
import 'package:starlight/domain/usecases/execute_group_command.dart';
import 'package:starlight/domain/usecases/execute_scene.dart';
import 'package:starlight/presentation/bloc/ble/ble_bloc.dart';
import 'package:starlight/presentation/bloc/ble/ble_event.dart';
import 'package:starlight/presentation/bloc/ble/ble_state.dart';
import 'package:starlight/presentation/bloc/group/group_cubit.dart';
import 'package:starlight/presentation/bloc/light/light_bloc.dart';
import 'package:starlight/presentation/bloc/light/light_event.dart';
import 'package:starlight/presentation/bloc/profile/profile_cubit.dart';
import 'package:starlight/presentation/bloc/registry/device_registry_cubit.dart';
import 'package:starlight/presentation/bloc/room/room_cubit.dart';
import 'package:starlight/presentation/bloc/scene/scene_bloc.dart';
import 'package:starlight/presentation/bloc/theme/theme_cubit.dart';
import 'package:starlight/presentation/bloc/theme/theme_state.dart';

class App extends StatefulWidget {
  const App({super.key});

  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> {
  late final BleRepositoryImpl _bleRepository;
  late final DeviceRepositoryImpl _deviceRepository;
  BleBloc? _bleBloc;
  LightBloc? _lightBloc;
  SceneBloc? _sceneBloc;
  DeviceRegistryCubit? _deviceRegistryCubit;
  RoomCubit? _roomCubit;
  GroupCubit? _groupCubit;
  ThemeCubit? _themeCubit;
  ProfileCubit? _profileCubit;
  BleGattProfileExecutor? _profileExecutor;
  CommandRouter? _commandRouter;
  StreamSubscription<BleState>? _activeDeviceSub;

  @override
  void initState() {
    super.initState();
    AppLog.info('App: initializing dependencies');
    _init();
  }

  @override
  void dispose() {
    AppLog.info('App: disposing, closing blocs');
    _activeDeviceSub?.cancel();
    _bleBloc?.close();
    _lightBloc?.close();
    _sceneBloc?.close();
    _deviceRegistryCubit?.close();
    _roomCubit?.close();
    _groupCubit?.close();
    _themeCubit?.close();
    _profileCubit?.close();
    _profileExecutor?.dispose();
    _commandRouter?.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    final initStart = DateTime.now();
    AppLog.debug('App._init: reading SharedPreferences');
    final prefs = await SharedPreferences.getInstance();

    final themeCubit = ThemeCubit(ThemePreferences(prefs));

    final bleDataSource = BleDataSource();
    _bleRepository = BleRepositoryImpl(bleDataSource);
    final deviceDataSource = DeviceDataSource(prefs);
    _deviceRepository = DeviceRepositoryImpl(
      deviceDataSource: deviceDataSource,
      adapters: [StarLightBleAdapter(bleDataSource)],
    );

    final presetRepository = PresetRepositoryImpl(PresetDataSource(prefs));
    final sceneRepository = SceneRepositoryImpl(SceneDataSource(prefs));
    final savedDeviceRepository = SavedDeviceRepositoryImpl(prefs);

    // The device registry is loaded *before* any room/group feature reads it,
    // so a legacy room payload can still find the devices it refers to when the
    // membership migration runs.
    await _deviceRepository.loadPersistedDevices();

    final roomRepository = RoomRepositoryImpl(
      RoomDataSource(prefs),
      _deviceRepository,
    );
    final groupRepository = DeviceGroupRepositoryImpl(
      DeviceGroupDataSource(prefs),
      _deviceRepository,
      roomRepository: roomRepository,
    );

    // Custom device profiles: one persistence path, one executor (which itself
    // routes through the single BLE owner) and one router shared by the light
    // bloc and the profile cubit.
    final profileRepository = DeviceProfileRepositoryImpl(
      ProfileDataSource(prefs),
    );
    final assignmentRepository = ProfileAssignmentRepositoryImpl(prefs);
    final profileExecutor = BleGattProfileExecutor(bleDataSource);
    final commandRouter = CommandRouter(
      _bleRepository,
      executor: profileExecutor,
    );
    _profileExecutor = profileExecutor;
    _commandRouter = commandRouter;

    // Every scene/group command goes through this dispatcher, so all of them
    // share the router's verification gate and the single BLE command queue.
    final dispatcher = DeviceCommandDispatcher(commandRouter);

    final bleBloc = BleBloc(
      _bleRepository,
      savedDeviceRepository,
      deviceRepository: _deviceRepository,
    );
    final lightBloc = LightBloc(
      _bleRepository,
      presetRepository,
      router: commandRouter,
      profileStateUpdates: profileExecutor.stateUpdates,
    );
    final sceneBloc = SceneBloc(
      sceneRepository,
      ExecuteScene(
        devices: _deviceRepository,
        groups: groupRepository,
        dispatcher: dispatcher,
      ),
    );
    final deviceRegistryCubit = DeviceRegistryCubit(_deviceRepository);
    final roomCubit = RoomCubit(roomRepository, registry: deviceRegistryCubit);
    final groupCubit = GroupCubit(
      groupRepository,
      ExecuteGroupCommand(
        groups: groupRepository,
        devices: _deviceRepository,
        dispatcher: dispatcher,
      ),
    );
    final profileCubit = ProfileCubit(
      repository: profileRepository,
      assignments: assignmentRepository,
      executor: profileExecutor,
      router: commandRouter,
    );

    // Keep the profile cubit's notion of "the connected device" in step with
    // BLE; verification and routing follow the real connection.
    _activeDeviceSub = bleBloc.stream.listen((state) {
      final deviceId = state is BleConnected ? state.device.id : null;
      profileCubit.onActiveDeviceChanged(deviceId);
      // Keep the light bloc's effect engine bound to the same device so
      // in-flight effect work is invalidated when the device changes.
      lightBloc.onActiveDeviceChanged(deviceId);
    });

    if (!mounted) return;
    AppLog.info(
      'App: dependencies ready in '
      '${DateTime.now().difference(initStart).inMilliseconds}ms, showing UI',
    );
    setState(() {
      _bleBloc = bleBloc;
      _lightBloc = lightBloc;
      _sceneBloc = sceneBloc;
      _deviceRegistryCubit = deviceRegistryCubit;
      _roomCubit = roomCubit;
      _groupCubit = groupCubit;
      _themeCubit = themeCubit;
      _profileCubit = profileCubit;
    });

    // Inspect the adapter once the UI exists and request the system enable
    // flow if Bluetooth is off. Idempotent and non-blocking.
    // Load the persisted pairing first so the UI can show the saved device and
    // offer a reconnect (loading never connects on its own).
    bleBloc.add(const LoadPairedDevice());
    bleBloc.add(const EnsureBluetoothReady());

    // The remaining work is not required for the first frame: presets and
    // profiles load after the UI is on screen so startup is not blocked on
    // local storage I/O. Rooms, groups and scenes are already loaded — the
    // cubits kicked that off during construction.
    lightBloc.add(LoadPresets());
    unawaited(profileCubit.load());
  }

  @override
  Widget build(BuildContext context) {
    final bleBloc = _bleBloc;
    final lightBloc = _lightBloc;
    final sceneBloc = _sceneBloc;
    final deviceRegistryCubit = _deviceRegistryCubit;
    final roomCubit = _roomCubit;
    final groupCubit = _groupCubit;
    final themeCubit = _themeCubit;
    final profileCubit = _profileCubit;

    if (bleBloc == null ||
        lightBloc == null ||
        sceneBloc == null ||
        deviceRegistryCubit == null ||
        roomCubit == null ||
        groupCubit == null ||
        themeCubit == null ||
        profileCubit == null) {
      return MaterialApp(
        theme: themeCubit == null
            ? buildAppTheme()
            : buildAppTheme(
                option: themeCubit.state.theme,
                accentOverride: themeCubit.state.customAccent,
              ),
        home: const Scaffold(body: Center(child: CircularProgressIndicator())),
      );
    }

    return BlocProvider<ThemeCubit>.value(
      value: themeCubit,
      child: BlocBuilder<ThemeCubit, ThemeState>(
        builder: (context, themeState) {
          // Providers wrap the MaterialApp (not just `home`) so pushed routes
          // like /controller and the profile pages can read them too.
          return MultiBlocProvider(
            providers: [
              BlocProvider.value(value: bleBloc),
              BlocProvider.value(value: lightBloc),
              BlocProvider.value(value: sceneBloc),
              BlocProvider.value(value: deviceRegistryCubit),
              BlocProvider.value(value: roomCubit),
              BlocProvider.value(value: groupCubit),
              BlocProvider.value(value: profileCubit),
            ],
            child: MaterialApp(
              title: 'StarLight',
              debugShowCheckedModeBanner: false,
              theme: buildAppTheme(
                option: themeState.theme,
                accentOverride: themeState.customAccent,
              ),
              home: const AppShell(),
              routes: {
                '/add-device': (_) => const AddDevicePage(),
                '/rooms': (_) => const RoomsPage(),
                '/groups': (_) => const GroupsPage(),
                '/scenes': (_) => const ScenesPage(),
                '/controller': (_) => const DeviceDetailPage(),
                '/effects': (_) => const EffectsStudioPage(),
                '/diagnostics': (_) => const DiagnosticsPage(),
                HardwareLabPage.routeName: (_) => const HardwareLabPage(),
              },
            ),
          );
        },
      ),
    );
  }
}
