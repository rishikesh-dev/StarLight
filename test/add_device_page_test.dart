import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:starlight/domain/entities/ble_device.dart';
import 'package:starlight/domain/entities/connection_state.dart';
import 'package:starlight/domain/entities/device.dart';
import 'package:starlight/domain/entities/saved_device.dart';
import 'package:starlight/domain/repositories/ble_repository.dart';
import 'package:starlight/domain/repositories/device_repository.dart';
import 'package:starlight/domain/repositories/saved_device_repository.dart';
import 'package:starlight/presentation/bloc/ble/ble_bloc.dart';
import 'package:starlight/presentation/bloc/ble/ble_state.dart';
import 'package:starlight/presentation/pages/devices/add_device_page.dart';
import 'package:starlight/presentation/theme/app_theme.dart';

class MockBleRepository extends Mock implements BleRepository {}

class MockSavedDeviceRepository extends Mock implements SavedDeviceRepository {}

class MockDeviceRepository extends Mock implements DeviceRepository {}

class FakeSavedDevice extends Fake implements SavedDevice {}

class FakeDevice extends Fake implements Device {}

/// Device discovery UX coverage: activation-driven scanning, the idle prompt,
/// the empty-scanning state, and name/id search filtering.
void main() {
  late MockBleRepository bleRepository;
  late MockSavedDeviceRepository savedRepo;
  late MockDeviceRepository deviceRepository;
  late StreamController<List<BleDevice>> scanController;
  late StreamController<DeviceConnectionState> connectionController;
  late StreamController<BluetoothAdapterState> adapterStateController;

  const livingRoom = BleDevice(
    id: 'AA:BB:CC:DD:EE:FF',
    name: 'GATT--DEMO Living Room',
    rssi: -50,
  );
  const kitchen = BleDevice(
    id: '11:22:33:44:55:66',
    name: 'Kitchen Strip',
    rssi: -70,
  );

  setUpAll(() {
    registerFallbackValue(
      const BleDevice(id: '', name: '', rssi: 0, isConnected: false),
    );
    registerFallbackValue(FakeSavedDevice());
    registerFallbackValue(FakeDevice());
  });

  setUp(() {
    bleRepository = MockBleRepository();
    savedRepo = MockSavedDeviceRepository();
    deviceRepository = MockDeviceRepository();
    scanController = StreamController<List<BleDevice>>.broadcast();
    connectionController = StreamController<DeviceConnectionState>.broadcast();
    adapterStateController =
        StreamController<BluetoothAdapterState>.broadcast();

    when(() => bleRepository.hasPermissions()).thenAnswer((_) async => true);
    when(() => bleRepository.isBluetoothEnabled())
        .thenAnswer((_) async => true);
    when(() => bleRepository.waitForAdapterOn()).thenAnswer((_) async => true);
    when(() => bleRepository.adapterState)
        .thenAnswer((_) => adapterStateController.stream);
    when(() => bleRepository.adapterStateNow)
        .thenReturn(BluetoothAdapterState.on);
    when(() => bleRepository.isSupported()).thenAnswer((_) async => true);
    when(() => bleRepository.enableBluetooth()).thenAnswer((_) async => true);
    when(() => bleRepository.scanDevices())
        .thenAnswer((_) => scanController.stream);
    when(() => bleRepository.stopScan()).thenAnswer((_) async {});
    when(() => bleRepository.connectDevice(any()))
        .thenAnswer((_) => connectionController.stream);
    when(() => bleRepository.disconnectDevice()).thenAnswer((_) async {});
    when(() => bleRepository.connectionState)
        .thenAnswer((_) => connectionController.stream);
    when(() => savedRepo.load()).thenAnswer((_) async => null);
    when(() => savedRepo.save(any())).thenAnswer((_) async {});
    when(() => deviceRepository.updateDevice(any())).thenAnswer((_) async {});
    when(() => deviceRepository.getDevice(any())).thenAnswer((_) async => null);
  });

  tearDown(() async {
    await scanController.close();
    await connectionController.close();
    await adapterStateController.close();
  });

  Future<BleBloc> pumpPage(WidgetTester tester, {bool active = false}) async {
    final bloc = BleBloc(
      bleRepository,
      savedRepo,
      deviceRepository: deviceRepository,
    );
    addTearDown(bloc.close);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: BlocProvider<BleBloc>.value(
          value: bloc,
          child: AddDevicePage(embedded: true, active: active),
        ),
      ),
    );
    await tester.pump();
    return bloc;
  }

  /// Pumps several frames so the BLoC's awaited handlers can run. We cannot use
  /// `pumpAndSettle` because the scanning state shows an indeterminate
  /// [CircularProgressIndicator] that never settles.
  Future<void> settle(WidgetTester tester, [int times = 6]) async {
    for (var i = 0; i < times; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
  }

  testWidgets('shows the scan prompt while inactive and does not scan', (
    tester,
  ) async {
    final bloc = await pumpPage(tester);
    expect(find.text('Find your device'), findsOneWidget);
    expect(find.text('Scan for devices'), findsOneWidget);
    expect(bloc.state, isA<BleInitial>());
    verifyNever(() => bleRepository.scanDevices());
  });

  testWidgets('scans automatically when the page becomes active', (
    tester,
  ) async {
    final bloc = await pumpPage(tester, active: true);
    await settle(tester);
    expect(bloc.state, isA<BleScanning>());
    expect(find.text('Searching for devices…'), findsOneWidget);
  });

  testWidgets('tapping Scan for devices starts a scan', (tester) async {
    final bloc = await pumpPage(tester);
    await tester.tap(find.text('Scan for devices'));
    await settle(tester);
    expect(bloc.state, isA<BleScanning>());
    expect(find.text('Searching for devices…'), findsOneWidget);
  });

  testWidgets('lists discovered devices and filters by name', (tester) async {
    await pumpPage(tester, active: true);
    await settle(tester);
    scanController.add([livingRoom, kitchen]);
    await settle(tester);

    expect(find.text('GATT--DEMO Living Room'), findsOneWidget);
    expect(find.text('Kitchen Strip'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'living');
    await tester.pump();

    expect(find.text('GATT--DEMO Living Room'), findsOneWidget);
    expect(find.text('Kitchen Strip'), findsNothing);
  });

  testWidgets('filters by device id and reports no matches', (tester) async {
    await pumpPage(tester, active: true);
    await settle(tester);
    scanController.add([livingRoom, kitchen]);
    await settle(tester);

    await tester.enterText(find.byType(TextField), '11:22:33');
    await tester.pump();
    expect(find.text('Kitchen Strip'), findsOneWidget);
    expect(find.text('GATT--DEMO Living Room'), findsNothing);

    await tester.enterText(find.byType(TextField), 'does-not-exist');
    await tester.pump();

    expect(find.textContaining('No devices match'), findsOneWidget);
  });

  testWidgets('reflects a Bluetooth-off state with a turn-on action', (
    tester,
  ) async {
    when(() => bleRepository.adapterStateNow)
        .thenReturn(BluetoothAdapterState.off);
    when(() => bleRepository.waitForAdapterOn()).thenAnswer((_) async => false);
    when(() => bleRepository.enableBluetooth()).thenAnswer((_) async => false);

    await pumpPage(tester, active: true);
    await settle(tester);

    expect(find.text('Bluetooth is off'), findsOneWidget);
    expect(find.text('Turn on Bluetooth'), findsOneWidget);
  });
}
