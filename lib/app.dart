import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:starlight/presentation/app_shell.dart';
import 'package:starlight/presentation/pages/devices/add_device_page.dart';
import 'package:starlight/presentation/pages/devices/devices_page.dart';
import 'package:starlight/presentation/pages/home/home_page.dart';
import 'package:starlight/presentation/pages/scenes/scene_create_page.dart';
import 'package:starlight/presentation/pages/scenes/scenes_page.dart';
import 'package:starlight/presentation/pages/automations/automations_page.dart';
import 'package:starlight/presentation/pages/controller/light_controller_page.dart';
import 'package:starlight/presentation/theme/app_theme.dart';

import 'package:starlight/core/utils/app_logger.dart';
import 'package:starlight/data/datasources/ble_datasource.dart';
import 'package:starlight/data/datasources/preset_datasource.dart';
import 'package:starlight/data/datasources/device_datasource.dart';
import 'package:starlight/data/datasources/room_datasource.dart';
import 'package:starlight/data/datasources/scene_datasource.dart';
import 'package:starlight/data/datasources/favorite_datasource.dart';
import 'package:starlight/data/repositories/ble_repository_impl.dart';
import 'package:starlight/data/repositories/device_repository_impl.dart';
import 'package:starlight/data/repositories/preset_repository_impl.dart';
import 'package:starlight/data/repositories/scene_repository_impl.dart';
import 'package:starlight/domain/usecases/execute_scene.dart';
import 'package:starlight/presentation/bloc/ble/ble_bloc.dart';
import 'package:starlight/presentation/bloc/ble/ble_event.dart';
import 'package:starlight/presentation/bloc/light/light_bloc.dart';
import 'package:starlight/presentation/bloc/scene/scene_bloc.dart';

class App extends StatefulWidget {
  const App({super.key});

  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> {
  late final BleRepositoryImpl _bleRepository;
  late final DeviceRepositoryImpl _deviceRepository;
  late final PresetRepositoryImpl _presetRepository;
  late final SceneRepositoryImpl _sceneRepository;
  BleBloc? _bleBloc;
  LightBloc? _lightBloc;
  SceneBloc? _sceneBloc;

  @override
  void initState() {
    super.initState();
    AppLog.info('App: initializing dependencies');
    _init();
  }

  @override
  void dispose() {
    AppLog.info('App: disposing, closing blocs');
    _bleBloc?.close();
    _lightBloc?.close();
    _sceneBloc?.close();
    super.dispose();
  }

  Future<void> _init() async {
    AppLog.debug('App._init: reading SharedPreferences');
    final prefs = await SharedPreferences.getInstance();

    final bleDataSource = BleDataSource();
    _bleRepository = BleRepositoryImpl(bleDataSource);
    final deviceDataSource = DeviceDataSource(prefs);
    _deviceRepository = DeviceRepositoryImpl(
      deviceDataSource: deviceDataSource,
    );
    await _deviceRepository.loadPersistedDevices();

    final presetRepository = PresetRepositoryImpl(PresetDataSource(prefs));
    final sceneRepository = SceneRepositoryImpl(SceneDataSource(prefs));

    final bleBloc = BleBloc(_bleRepository);
    final lightBloc = LightBloc(_bleRepository, presetRepository);
    final sceneBloc = SceneBloc(sceneRepository, ExecuteScene(_deviceRepository));

    if (!mounted) return;
    AppLog.info('App: dependencies ready, showing UI');
    setState(() {
      _bleBloc = bleBloc;
      _lightBloc = lightBloc;
      _sceneBloc = sceneBloc;
    });
  }

  @override
  Widget build(BuildContext context) {
    final bleBloc = _bleBloc;
    final lightBloc = _lightBloc;
    final sceneBloc = _sceneBloc;

    if (bleBloc == null || lightBloc == null || sceneBloc == null) {
      return MaterialApp(
        theme: buildAppTheme(),
        home: const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    return MaterialApp(
      title: 'StarLight',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: MultiBlocProvider(
        providers: [
          BlocProvider.value(value: bleBloc),
          BlocProvider.value(value: lightBloc),
          BlocProvider.value(value: sceneBloc),
        ],
        child: const AppShell(),
      ),
      routes: {
        '/add-device': (_) => const AddDevicePage(),
        '/scene-create': (_) => const SceneCreatePage(),
        '/controller': (_) => const LightControllerPage(),
      },
    );
  }
}
