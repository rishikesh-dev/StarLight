import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:starlight/domain/entities/ble_device.dart';
import 'package:starlight/domain/entities/connection_state.dart';
import 'package:starlight/domain/entities/device.dart';
import 'package:starlight/domain/entities/device_capability.dart';
import 'package:starlight/domain/entities/device_profile.dart';
import 'package:starlight/domain/entities/light_command.dart';
import 'package:starlight/domain/entities/profile_command.dart';
import 'package:starlight/domain/entities/saved_device.dart';
import 'package:starlight/domain/repositories/ble_repository.dart';
import 'package:starlight/domain/repositories/device_profile_repository.dart';
import 'package:starlight/domain/repositories/device_repository.dart';
import 'package:starlight/domain/repositories/preset_repository.dart';
import 'package:starlight/domain/repositories/profile_assignment_repository.dart';
import 'package:starlight/domain/repositories/saved_device_repository.dart';
import 'package:starlight/domain/services/command_router.dart';
import 'package:starlight/presentation/bloc/ble/ble_bloc.dart';
import 'package:starlight/presentation/bloc/ble/ble_event.dart';
import 'package:starlight/presentation/bloc/ble/ble_state.dart';
import 'package:starlight/presentation/bloc/light/light_bloc.dart';
import 'package:starlight/presentation/bloc/light/light_event.dart';
import 'package:starlight/presentation/bloc/profile/profile_cubit.dart';
import 'package:starlight/presentation/pages/devices/device_detail_page.dart';
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

CommandTemplate _template(String source) =>
    CommandTemplate.parse(source).template!;

DeviceProfile _customProfile() => DeviceProfile(
  id: 'profile_custom',
  name: 'Desk strip',
  serviceUuid: 'fff0',
  writeCharacteristicUuid: 'fff3',
  capabilities: const {DeviceCapability.power},
  commands: GattCommandSet(powerOn: _template('A1'), powerOff: _template('A0')),
);

/// Device details / controller screen coverage: identity + real connection
/// status, capability-gated controls, reconnect, rename and forget.
void main() {
  late MockBleRepository bleRepository;
  late MockSavedDeviceRepository savedRepo;
  late MockDeviceRepository deviceRepository;
  late MockPresetRepository presetRepository;
  late MockDeviceProfileRepository profileRepository;
  late MockProfileAssignmentRepository assignmentRepository;
  late StreamController<DeviceConnectionState> connectionController;
  late StreamController<BluetoothAdapterState> adapterStateController;

  const savedId = 'AA:BB:CC:DD:EE:FF';

  setUpAll(() {
    registerFallbackValue(
      const BleDevice(id: '', name: '', rssi: 0, isConnected: false),
    );
    registerFallbackValue(const LightCommand(type: 'fallback', bytes: []));
    registerFallbackValue(FakeSavedDevice());
    registerFallbackValue(FakeDevice());
    registerFallbackValue(DeviceProfile.mrStar);
  });

  setUp(() {
    bleRepository = MockBleRepository();
    savedRepo = MockSavedDeviceRepository();
    deviceRepository = MockDeviceRepository();
    presetRepository = MockPresetRepository();
    profileRepository = MockDeviceProfileRepository();
    assignmentRepository = MockProfileAssignmentRepository();
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
    when(() => bleRepository.stopScan()).thenAnswer((_) async {});
    when(() => bleRepository.connectDevice(any()))
        .thenAnswer((_) => connectionController.stream);
    when(() => bleRepository.disconnectDevice()).thenAnswer((_) async {});
    when(() => bleRepository.connectionState)
        .thenAnswer((_) => connectionController.stream);
    when(() => bleRepository.stateUpdates).thenAnswer((_) => Stream.empty());
    when(() => bleRepository.sendCommand(any())).thenAnswer((_) async {});
    when(() => bleRepository.readRssi()).thenAnswer((_) async => null);
    when(() => savedRepo.load())
        .thenAnswer((_) async => const SavedDevice(id: savedId, name: 'Lamp'));
    when(() => savedRepo.save(any())).thenAnswer((_) async {});
    when(() => savedRepo.remove()).thenAnswer((_) async {});
    when(() => deviceRepository.updateDevice(any())).thenAnswer((_) async {});
    when(() => deviceRepository.removeDevice(any())).thenAnswer((_) async {});
    when(() => deviceRepository.getDevice(any())).thenAnswer((_) async => null);
    when(() => presetRepository.loadPresets()).thenAnswer((_) async => []);
    when(() => profileRepository.loadProfiles())
        .thenAnswer((_) async => [DeviceProfile.mrStar]);
    when(() => profileRepository.saveProfile(any())).thenAnswer((_) async {});
    when(() => profileRepository.deleteProfile(any())).thenAnswer((_) async {});
    final assignmentStore = <String, String>{};
    when(() => assignmentRepository.loadAssignments())
        .thenAnswer((_) async => Map<String, String>.of(assignmentStore));
    when(() => assignmentRepository.assign(any(), any()))
        .thenAnswer((invocation) async {
          assignmentStore[invocation.positionalArguments[0] as String] =
              invocation.positionalArguments[1] as String;
        });
    when(() => assignmentRepository.unassign(any()))
        .thenAnswer((invocation) async {
          assignmentStore.remove(invocation.positionalArguments[0] as String);
        });
  });

  tearDown(() async {
    await connectionController.close();
    await adapterStateController.close();
  });

  Future<(BleBloc, LightBloc, ProfileCubit)> pumpPage(
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(400, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final bleBloc = BleBloc(
      bleRepository,
      savedRepo,
      deviceRepository: deviceRepository,
    );
    final executor = FakeProfileExecutor();
    final router = CommandRouter(bleRepository, executor: executor);
    final lightBloc = LightBloc(
      bleRepository,
      presetRepository,
      router: router,
    );
    final profileCubit = ProfileCubit(
      repository: profileRepository,
      assignments: assignmentRepository,
      executor: executor,
      router: router,
    );
    addTearDown(bleBloc.close);
    addTearDown(lightBloc.close);
    addTearDown(profileCubit.close);

    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<BleBloc>.value(value: bleBloc),
          BlocProvider<LightBloc>.value(value: lightBloc),
          BlocProvider<ProfileCubit>.value(value: profileCubit),
        ],
        child: MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<bool>(
                    builder: (_) => const DeviceDetailPage(),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return (bleBloc, lightBloc, profileCubit);
  }

  /// Pumps a few frames so the BLoC's async handlers (load, connect, rename)
  /// settle before assertions. The details page has no infinite animations, so
  /// this is just an async-flush helper.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 4; i++) {
      await tester.pump();
    }
  }

  testWidgets('shows an empty state when no device is available', (
    tester,
  ) async {
    when(() => savedRepo.load()).thenAnswer((_) async => null);
    final (bleBloc, _, _) = await pumpPage(tester);
    bleBloc.add(const LoadPairedDevice());
    await settle(tester);

    expect(find.text('No device selected'), findsOneWidget);
  });

  testWidgets('shows the paired device and can reconnect', (tester) async {
    final (bleBloc, _, _) = await pumpPage(tester);
    bleBloc.add(const LoadPairedDevice());
    await settle(tester);

    expect(find.text('Lamp'), findsWidgets);
    expect(find.text(savedId), findsOneWidget);
    expect(find.text('Disconnected'), findsOneWidget);
    expect(find.text('Reconnect'), findsOneWidget);

    await tester.tap(find.text('Reconnect'));
    await tester.pump();
    verify(() => bleRepository.connectDevice(savedId)).called(1);
  });

  testWidgets('shows connected status and the supported controls', (
    tester,
  ) async {
    final (bleBloc, _, _) = await pumpPage(tester);
    bleBloc.add(const ConnectToDevice(savedId, 'Lamp'));
    await settle(tester);
    connectionController.add(DeviceConnectionState.connected);
    await settle(tester);

    expect(bleBloc.state, isA<BleConnected>());
    expect(find.text('Connected'), findsOneWidget);
    expect(find.text('Brightness'), findsWidgets);
    expect(find.text('Supported controls'), findsOneWidget);
    expect(find.text('Power'), findsOneWidget);
    expect(find.text('Color'), findsOneWidget);
    // No colour-temperature control: the protocol has no such command.
    expect(find.text('Color Temperature'), findsNothing);
  });

  testWidgets('assigns a custom profile from the device profile dropdown', (
    tester,
  ) async {
    when(() => profileRepository.loadProfiles())
        .thenAnswer((_) async => [DeviceProfile.mrStar, _customProfile()]);
    final (bleBloc, _, profileCubit) = await pumpPage(tester);
    bleBloc.add(const LoadPairedDevice());
    await settle(tester);
    await profileCubit.load();
    await settle(tester);

    expect(find.text('Device profile'), findsOneWidget);
    expect(find.text('Built-in (MR Star)'), findsOneWidget);

    await tester.tap(find.text('Built-in (MR Star)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Desk strip').last);
    await tester.pumpAndSettle();

    verify(() => assignmentRepository.assign(savedId, 'profile_custom'))
        .called(1);
    expect(find.text('Desk strip'), findsOneWidget);
    // The assignment is real but unverified: the UI says so rather than
    // pretending the profile works.
    expect(find.text('Not verified'), findsOneWidget);
  });

  testWidgets('hides controls when the assigned profile is not verified', (
    tester,
  ) async {
    when(() => profileRepository.loadProfiles())
        .thenAnswer((_) async => [DeviceProfile.mrStar, _customProfile()]);
    final (bleBloc, lightBloc, profileCubit) = await pumpPage(tester);
    lightBloc.add(LoadPresets());
    await settle(tester);
    bleBloc.add(const LoadPairedDevice());
    await settle(tester);

    await profileCubit.load();
    await profileCubit.assignProfile(savedId, 'profile_custom');
    await profileCubit.onActiveDeviceChanged(savedId);
    await settle(tester);

    expect(find.text('Supported controls'), findsOneWidget);
    expect(find.text('Power'), findsNothing);
    expect(find.textContaining('None available'), findsOneWidget);
  });

  testWidgets('shows last-known controls disabled while disconnected', (
    tester,
  ) async {
    final (bleBloc, lightBloc, _) = await pumpPage(tester);
    lightBloc.add(const TogglePower(false));
    await settle(tester);
    bleBloc.add(const LoadPairedDevice());
    await settle(tester);

    expect(find.text('Last known'), findsOneWidget);
    expect(find.text('Brightness'), findsWidgets);
    expect(find.text('Connect to view and control this device.'), findsNothing);
  });

  testWidgets('renames the paired device', (tester) async {
    final (bleBloc, _, _) = await pumpPage(tester);
    bleBloc.add(const LoadPairedDevice());
    await settle(tester);

    await tester.tap(find.byTooltip('Rename device'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Desk Lamp');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    verify(
      () => savedRepo.save(
        any(
          that: isA<SavedDevice>().having((s) => s.name, 'name', 'Desk Lamp'),
        ),
      ),
    ).called(1);
  });

  testWidgets('forgets the device after confirmation', (tester) async {
    final (bleBloc, _, _) = await pumpPage(tester);
    bleBloc.add(const LoadPairedDevice());
    await settle(tester);

    await tester.tap(find.text('Forget device'));
    await tester.pumpAndSettle();

    expect(find.text('Forget device?'), findsOneWidget);
    await tester.tap(find.text('Forget'));
    await tester.pumpAndSettle();

    verify(() => savedRepo.remove()).called(1);
    verify(() => deviceRepository.removeDevice(savedId)).called(1);
  });
}
