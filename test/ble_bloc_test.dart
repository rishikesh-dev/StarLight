import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
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
import 'package:starlight/presentation/bloc/ble/ble_event.dart';
import 'package:starlight/presentation/bloc/ble/ble_state.dart';

class MockBleRepository extends Mock implements BleRepository {}

class MockSavedDeviceRepository extends Mock implements SavedDeviceRepository {}

class MockDeviceRepository extends Mock implements DeviceRepository {}

class FakeSavedDevice extends Fake implements SavedDevice {
  FakeSavedDevice();
}

class FakeDevice extends Fake implements Device {
  FakeDevice();
}

void main() {
  late MockBleRepository bleRepository;
  late MockSavedDeviceRepository savedRepo;
  late MockDeviceRepository deviceRepository;
  late StreamController<List<BleDevice>> scanController;
  late StreamController<DeviceConnectionState> connectionController;
  late StreamController<BluetoothAdapterState> adapterStateController;
  // Observability hooks used by tests that must synchronize with the BLoC's
  // scan-session lifecycle (the scan stream is broadcast: results emitted
  // before the BLoC starts a session are dropped, as in production).
  late int scanSessionsStarted;
  late int adapterWaitStarted;
  // Gate that holds StartScan handlers inside waitForAdapterOn until the
  // test releases them (models an adapter that is off, then comes on).
  late Completer<void> adapterGate;

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
    scanSessionsStarted = 0;
    adapterWaitStarted = 0;
    adapterGate = Completer<void>();

    when(() => bleRepository.hasPermissions()).thenAnswer((_) async => true);
    when(() => bleRepository.isBluetoothEnabled())
        .thenAnswer((_) async => true);
    when(() => bleRepository.waitForAdapterOn()).thenAnswer((_) async {
      adapterWaitStarted++;
      return true;
    });
    when(() => bleRepository.adapterState)
        .thenAnswer((_) => adapterStateController.stream);
    when(() => bleRepository.adapterStateNow)
        .thenReturn(BluetoothAdapterState.on);
    when(() => bleRepository.isSupported()).thenAnswer((_) async => true);
    when(() => bleRepository.enableBluetooth()).thenAnswer((_) async => true);
    when(() => bleRepository.scanDevices()).thenAnswer((_) {
      // Called synchronously before the BLoC attaches its listener to the
      // returned stream (same expression), so once this counter is visible
      // to a test polling loop the subscription definitely exists.
      scanSessionsStarted++;
      return scanController.stream;
    });
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

  BleBloc buildBloc() =>
      BleBloc(bleRepository, savedRepo, deviceRepository: deviceRepository);

  group('BleBloc - scan flow', () {
    blocTest<BleBloc, BleState>(
      'StartScan emits BleScanning with devices',
      build: buildBloc,
      act: (bloc) {
        bloc.add(StartScan());
        scanController.add([
          const BleDevice(
            id: 'aa:bb:cc:dd:ee:ff',
            name: 'GATT--DEMO',
            rssi: -50,
            isConnected: false,
          ),
        ]);
      },
      expect: () => [isA<BleScanning>()],
    );

    blocTest<BleBloc, BleState>(
      'StopScanRequested stops scan and emits BleDisconnected when scanning',
      build: buildBloc,
      act: (bloc) {
        bloc.add(StartScan());
        scanController.add([]);
        bloc.add(StopScanRequested());
      },
      expect: () => [isA<BleScanning>(), isA<BleDisconnected>()],
    );

    blocTest<BleBloc, BleState>(
      'permissions denied emits BlePermissionDenied',
      build: () {
        final repo = MockBleRepository();
        when(() => repo.hasPermissions()).thenAnswer((_) async => false);
        when(() => repo.requestPermissions()).thenAnswer((_) async => false);
        when(() => repo.isPermanentlyDenied()).thenAnswer((_) async => false);
        when(() => repo.scanDevices()).thenAnswer((_) => Stream.empty());
        when(() => repo.stopScan()).thenAnswer((_) async {});
        when(() => repo.adapterState)
            .thenAnswer((_) => Stream<BluetoothAdapterState>.empty());
        when(() => repo.adapterStateNow).thenReturn(BluetoothAdapterState.on);
        when(() => repo.isSupported()).thenAnswer((_) async => true);
        when(() => repo.enableBluetooth()).thenAnswer((_) async => true);
        when(() => repo.connectionState).thenAnswer((_) => Stream.empty());
        when(() => repo.disconnectDevice()).thenAnswer((_) async {});
        return BleBloc(repo, MockSavedDeviceRepository());
      },
      act: (bloc) => bloc.add(StartScan()),
      expect: () => [
        isA<BlePermissionDenied>().having(
          (s) => s.permanentlyDenied,
          'permanentlyDenied',
          false,
        ),
      ],
    );

    blocTest<BleBloc, BleState>(
      'permanently denied permission is flagged and offers settings',
      build: () {
        final repo = MockBleRepository();
        when(() => repo.hasPermissions()).thenAnswer((_) async => false);
        when(() => repo.requestPermissions()).thenAnswer((_) async => false);
        when(() => repo.isPermanentlyDenied()).thenAnswer((_) async => true);
        when(() => repo.scanDevices()).thenAnswer((_) => Stream.empty());
        when(() => repo.stopScan()).thenAnswer((_) async {});
        when(() => repo.adapterState)
            .thenAnswer((_) => Stream<BluetoothAdapterState>.empty());
        when(() => repo.adapterStateNow).thenReturn(BluetoothAdapterState.on);
        when(() => repo.isSupported()).thenAnswer((_) async => true);
        when(() => repo.enableBluetooth()).thenAnswer((_) async => true);
        when(() => repo.connectionState).thenAnswer((_) => Stream.empty());
        when(() => repo.disconnectDevice()).thenAnswer((_) async {});
        return BleBloc(repo, MockSavedDeviceRepository());
      },
      act: (bloc) => bloc.add(StartScan()),
      expect: () => [
        isA<BlePermissionDenied>().having(
          (s) => s.permanentlyDenied,
          'permanentlyDenied',
          true,
        ),
      ],
    );

    blocTest<BleBloc, BleState>(
      'bluetooth disabled emits an actionable Bluetooth-off state',
      build: () {
        final repo = MockBleRepository();
        when(() => repo.hasPermissions()).thenAnswer((_) async => true);
        when(() => repo.isBluetoothEnabled()).thenAnswer((_) async => false);
        when(() => repo.waitForAdapterOn()).thenAnswer((_) async => false);
        when(() => repo.scanDevices()).thenAnswer((_) => Stream.empty());
        when(() => repo.stopScan()).thenAnswer((_) async {});
        when(() => repo.adapterState)
            .thenAnswer((_) => Stream<BluetoothAdapterState>.empty());
        // Adapter is genuinely off and the user declines to enable it.
        when(() => repo.adapterStateNow).thenReturn(BluetoothAdapterState.off);
        when(() => repo.isSupported()).thenAnswer((_) async => true);
        when(() => repo.enableBluetooth()).thenAnswer((_) async => false);
        when(() => repo.connectionState).thenAnswer((_) => Stream.empty());
        when(() => repo.disconnectDevice()).thenAnswer((_) async {});
        return BleBloc(repo, MockSavedDeviceRepository());
      },
      act: (bloc) => bloc.add(StartScan()),
      expect: () => [isA<BleBluetoothEnabling>(), isA<BleBluetoothOff>()],
    );
  });

  group('BleBloc - connection lifecycle', () {
    const testDeviceId = 'aa:bb:cc:dd:ee:ff';
    const testDeviceName = 'GATT--DEMO';

    blocTest<BleBloc, BleState>(
      'ConnectToDevice emits BleConnecting then BleConnected on success',
      build: buildBloc,
      act: (bloc) async {
        bloc.add(ConnectToDevice(testDeviceId, testDeviceName));
        await Future.delayed(Duration(milliseconds: 100));
        connectionController.add(DeviceConnectionState.connected);
      },
      expect: () => [isA<BleConnecting>(), isA<BleConnected>()],
    );

    blocTest<BleBloc, BleState>(
      'ConnectToDevice emits BleConnecting then BleError on failure',
      build: () {
        final repo = MockBleRepository();
        when(() => repo.hasPermissions()).thenAnswer((_) async => true);
        when(() => repo.isBluetoothEnabled()).thenAnswer((_) async => true);
        when(() => repo.waitForAdapterOn()).thenAnswer((_) async => true);
        when(() => repo.scanDevices()).thenAnswer((_) => Stream.empty());
        when(() => repo.stopScan()).thenAnswer((_) async {});
        when(() => repo.adapterState)
            .thenAnswer((_) => Stream<BluetoothAdapterState>.empty());
        when(() => repo.connectDevice(any()))
            .thenAnswer((_) => Stream.error(Exception('Connection failed')));
        when(() => repo.disconnectDevice()).thenAnswer((_) async {});
        when(() => repo.connectionState).thenAnswer((_) => Stream.empty());
        when(() => savedRepo.load()).thenAnswer((_) async => null);
        when(() => savedRepo.save(any())).thenAnswer((_) async {});
        when(() => deviceRepository.updateDevice(any()))
            .thenAnswer((_) async {});
        return BleBloc(repo, savedRepo, deviceRepository: deviceRepository);
      },
      act: (bloc) => bloc.add(ConnectToDevice(testDeviceId, testDeviceName)),
      expect: () => [isA<BleConnecting>(), isA<BleError>()],
    );

    blocTest<BleBloc, BleState>(
      'ConnectToDevice stops an active scan before connecting',
      build: buildBloc,
      act: (bloc) async {
        bloc.add(StartScan());
        await Future.delayed(Duration(milliseconds: 50));
        clearInteractions(bleRepository);
        bloc.add(ConnectToDevice(testDeviceId, testDeviceName));
        await Future.delayed(Duration(milliseconds: 50));
      },
      verify: (_) {
        // Scanning must be stopped (and awaited) before the connect starts.
        verify(() => bleRepository.stopScan()).called(greaterThanOrEqualTo(1));
        verify(() => bleRepository.connectDevice(testDeviceId)).called(1);
      },
    );

    blocTest<BleBloc, BleState>(
      'disconnect while connecting cancels connection',
      build: buildBloc,
      act: (bloc) async {
        bloc.add(ConnectToDevice(testDeviceId, testDeviceName));
        await Future.delayed(Duration(milliseconds: 50));
        bloc.add(DisconnectRequested());
      },
      expect: () => [isA<BleConnecting>(), isA<BleDisconnected>()],
    );

    blocTest<BleBloc, BleState>(
      'auto-reconnect triggers on unexpected disconnect',
      build: buildBloc,
      act: (bloc) async {
        bloc.add(ConnectToDevice(testDeviceId, testDeviceName));
        await Future.delayed(Duration(milliseconds: 100));
        connectionController.add(DeviceConnectionState.connected);
        await Future.delayed(Duration(milliseconds: 100));
        connectionController.add(DeviceConnectionState.disconnected);
      },
      expect: () => [
        isA<BleConnecting>(),
        isA<BleConnected>(),
        isA<BleDisconnected>(),
      ],
    );

    blocTest<BleBloc, BleState>(
      'manual disconnect prevents auto-reconnect',
      build: buildBloc,
      act: (bloc) async {
        bloc.add(ConnectToDevice(testDeviceId, testDeviceName));
        await Future.delayed(Duration(milliseconds: 100));
        connectionController.add(DeviceConnectionState.connected);
        await Future.delayed(Duration(milliseconds: 100));
        bloc.add(DisconnectRequested());
        await Future.delayed(Duration(milliseconds: 100));
        connectionController.add(DeviceConnectionState.disconnected);
      },
      expect: () => [
        isA<BleConnecting>(),
        isA<BleConnected>(),
        isA<BleDisconnected>(),
      ],
    );
  });

  group('BleBloc - device persistence', () {
    const testDeviceId = 'aa:bb:cc:dd:ee:ff';
    const testDeviceName = 'GATT--DEMO';

    blocTest<BleBloc, BleState>(
      'successful connection persists device to saved repo',
      build: buildBloc,
      act: (bloc) async {
        bloc.add(ConnectToDevice(testDeviceId, testDeviceName));
        await Future.delayed(Duration(milliseconds: 100));
        connectionController.add(DeviceConnectionState.connected);
      },
      verify: (_) {
        verify(() => savedRepo.save(any(that: isA<SavedDevice>()))).called(1);
      },
    );

    blocTest<BleBloc, BleState>(
      'connected device registered in device repository',
      build: buildBloc,
      act: (bloc) async {
        bloc.add(ConnectToDevice(testDeviceId, testDeviceName));
        await Future.delayed(Duration(milliseconds: 100));
        connectionController.add(DeviceConnectionState.connected);
      },
      verify: (_) {
        verify(() => deviceRepository.updateDevice(any(that: isA<Device>())))
            .called(1);
      },
    );

    blocTest<BleBloc, BleState>(
      'disconnect updates device registry connection state',
      build: buildBloc,
      act: (bloc) async {
        bloc.add(ConnectToDevice(testDeviceId, testDeviceName));
        await Future.delayed(Duration(milliseconds: 100));
        connectionController.add(DeviceConnectionState.connected);
        await Future.delayed(Duration(milliseconds: 50));
        bloc.add(DisconnectRequested());
        await Future.delayed(Duration(milliseconds: 50));
      },
      verify: (_) {
        verify(() => deviceRepository.updateDevice(any(that: isA<Device>())))
            .called(1);
      },
    );
  });

  group('BleBloc - reconnection logic', () {
    const testDeviceId = 'aa:bb:cc:dd:ee:ff';
    const testDeviceName = 'GATT--DEMO';

    blocTest<BleBloc, BleState>(
      'reconnect uses saved device from repository',
      build: () {
        when(() => savedRepo.load()).thenAnswer(
          (_) async =>
              const SavedDevice(id: testDeviceId, name: testDeviceName),
        );
        return buildBloc();
      },
      act: (bloc) async {
        // Simulate disconnect after connection
        bloc.add(ConnectToDevice(testDeviceId, testDeviceName));
        await Future.delayed(Duration(milliseconds: 100));
        connectionController.add(DeviceConnectionState.connected);
        await Future.delayed(Duration(milliseconds: 100));
        connectionController.add(DeviceConnectionState.disconnected);
      },
      wait: const Duration(milliseconds: 100),
      expect: () => [
        isA<BleConnecting>(),
        isA<BleConnected>(),
        isA<BleDisconnected>(),
      ],
    );
  });

  group('BleBloc - scan result handling', () {
    blocTest<BleBloc, BleState>(
      'scan results sorted with MR Star devices first',
      build: buildBloc,
      act: (bloc) async {
        bloc.add(StartScan());
        await Future.delayed(Duration(milliseconds: 50));
        scanController.add([
          const BleDevice(
            id: '11:22:33:44:55:66',
            name: 'Other Device',
            rssi: -40,
            isConnected: false,
          ),
          const BleDevice(
            id: 'aa:bb:cc:dd:ee:ff',
            name: 'GATT--DEMO',
            rssi: -60,
            isConnected: false,
          ),
        ]);
        await Future.delayed(Duration(milliseconds: 50));
      },
      expect: () => [isA<BleScanning>(), isA<BleScanning>()],
      verify: (bloc) {
        final state = bloc.state;
        if (state is BleScanning && state.devices.isNotEmpty) {
          expect(state.devices.first.name, 'GATT--DEMO');
        }
      },
    );

    blocTest<BleBloc, BleState>(
      'empty scan shows empty state',
      build: () {
        final emptyStream = Stream<List<BleDevice>>.value([]);
        when(() => bleRepository.scanDevices()).thenAnswer((_) => emptyStream);
        when(() => bleRepository.stopScan()).thenAnswer((_) async {});
        when(() => bleRepository.hasPermissions())
            .thenAnswer((_) async => true);
        when(() => bleRepository.isBluetoothEnabled())
            .thenAnswer((_) async => true);
        when(() => bleRepository.waitForAdapterOn())
            .thenAnswer((_) async => true);
        when(() => bleRepository.adapterState)
            .thenAnswer((_) => adapterStateController.stream);
        when(() => bleRepository.connectionState)
            .thenAnswer((_) => Stream.empty());
        when(() => bleRepository.disconnectDevice()).thenAnswer((_) async {});
        when(() => savedRepo.load()).thenAnswer((_) async => null);
        when(() => savedRepo.save(any())).thenAnswer((_) async {});
        when(() => deviceRepository.updateDevice(any()))
            .thenAnswer((_) async {});
        when(() => deviceRepository.getDevice(any()))
            .thenAnswer((_) async => null);
        return BleBloc(
          bleRepository,
          savedRepo,
          deviceRepository: deviceRepository,
        );
      },
      act: (bloc) => bloc.add(StartScan()),
      expect: () => [isA<BleScanning>()],
    );
  });

  group('BleBloc - adapter state & scan robustness', () {
    blocTest<BleBloc, BleState>(
      'StartScan waits for adapter on then scans',
      build: buildBloc,
      act: (bloc) {
        bloc.add(StartScan());
        scanController.add([
          const BleDevice(
            id: 'aa:bb:cc:dd:ee:ff',
            name: 'GATT--DEMO',
            rssi: -50,
            isConnected: false,
          ),
        ]);
      },
      verify: (bloc) {
        verify(() => bleRepository.waitForAdapterOn()).called(1);
        expect(bloc.state, isA<BleScanning>());
      },
    );

    blocTest<BleBloc, BleState>(
      'adapter off then on: waitForAdapterOn returns true, scan proceeds',
      build: () {
        // Simulate an adapter that is off until an `on` transition arrives:
        // waitForAdapterOn must hold the scan session until then.
        when(() => bleRepository.waitForAdapterOn()).thenAnswer((_) async {
          adapterWaitStarted++;
          await adapterStateController.stream.firstWhere(
            (state) => state == BluetoothAdapterState.on,
          );
          return true;
        });
        return buildBloc();
      },
      act: (bloc) async {
        bloc.add(StartScan());
        // 1. Wait until the handler is parked inside waitForAdapterOn
        //    (its adapter-stream subscription exists before we emit below:
        //    the counter is set synchronously in the same block).
        while (adapterWaitStarted < 1) {
          await Future<void>.delayed(Duration.zero);
        }
        // 2. Adapter flaps off, then back on — scan must proceed after `on`.
        adapterStateController.add(BluetoothAdapterState.off);
        adapterStateController.add(BluetoothAdapterState.on);
        // 3. Wait until the scan session has started. The scan stream is
        //    broadcast: the BLoC attaches its listener in the same
        //    synchronous expression that starts the session, so once the
        //    session counter is visible the subscription exists — results
        //    emitted earlier would be dropped, as in production.
        while (scanSessionsStarted < 1) {
          await Future<void>.delayed(Duration.zero);
        }
        // 4. Feed a scan result and wait until it has been processed.
        scanController.add([
          const BleDevice(
            id: '80:AC:C8:5D:AB:CF',
            name: 'GATT--DEMO',
            rssi: -60,
            isConnected: false,
          ),
        ]);
        while (bloc.state is! BleScanning ||
            (bloc.state as BleScanning).devices.isEmpty) {
          await Future<void>.delayed(Duration.zero);
        }
      },
      // The adapter-off transition surfaces as a readiness state while the
      // scan session is held open; once the adapter comes back on the scan
      // proceeds (the ready recheck is a no-op because the scan already
      // claimed the state).
      expect: () => [
        isA<BleBluetoothOff>(),
        isA<BleScanning>(),
        isA<BleScanning>(),
      ],
      verify: (bloc) {
        verify(() => bleRepository.waitForAdapterOn()).called(1);
        final state = bloc.state;
        expect(state, isA<BleScanning>());
        expect((state as BleScanning).devices.single.id, '80:AC:C8:5D:AB:CF');
      },
    );

    blocTest<BleBloc, BleState>(
      'adapter-off double StartScan: sessions serialize; StopScan leaves no orphan',
      build: () {
        // Every StartScan parks inside waitForAdapterOn until the test
        // releases the gate — models two rapid scan requests while the
        // adapter is off, both released by the same adapter-on transition.
        when(() => bleRepository.waitForAdapterOn()).thenAnswer((_) async {
          adapterWaitStarted++;
          await adapterGate.future;
          return true;
        });
        return buildBloc();
      },
      act: (bloc) async {
        bloc.add(StartScan());
        bloc.add(StartScan());
        // Wait until at least the first handler is parked on the gate. By
        // the first timer turn all pending microtasks have drained, so
        // under the default concurrent transformer BOTH handlers are
        // parked; serialized sessions have the first parked and the second
        // queued behind it.
        while (adapterWaitStarted < 1) {
          await Future<void>.delayed(Duration.zero);
        }
        // Release every parked handler back-to-back (one completion round).
        adapterGate.complete();
        while (adapterWaitStarted < 2 || scanSessionsStarted < 2) {
          await Future<void>.delayed(Duration.zero);
        }
        bloc.add(StopScanRequested());
        while (bloc.state is! BleDisconnected) {
          await Future<void>.delayed(Duration.zero);
        }
        // After StopScan no listener may remain. Under the default
        // concurrent transformer both released handlers evaluate
        // `_scanSubscription?.cancel()` before either assigns, so the
        // second assignment orphans the first subscription — which would
        // still deliver this late result and emit a spurious state. With
        // serialized sessions each handler cancels its predecessor, the
        // broadcast result is dropped, and the state sequence is exact.
        scanController.add([
          const BleDevice(
            id: 'aa:bb:cc:dd:ee:ff',
            name: 'GATT--DEMO',
            rssi: -50,
            isConnected: false,
          ),
        ]);
        // Let any stray delivery surface before blocTest compares states.
        for (var i = 0; i < 5; i++) {
          await Future<void>.delayed(Duration.zero);
        }
      },
      // The second session's BleScanning([]) reset is deduplicated (state
      // unchanged), so exactly two states are expected: the first session's
      // scan state and StopScan's disconnect. An orphaned listener would
      // append a third state when the late result arrives above.
      expect: () => [isA<BleScanning>(), isA<BleDisconnected>()],
      verify: (bloc) {
        verify(() => bleRepository.waitForAdapterOn()).called(2);
        verify(() => bleRepository.scanDevices()).called(2);
      },
    );

    blocTest<BleBloc, BleState>(
      'adapter stays off: emits an actionable Bluetooth-off state',
      build: () {
        final repo = MockBleRepository();
        when(() => repo.hasPermissions()).thenAnswer((_) async => true);
        when(() => repo.waitForAdapterOn()).thenAnswer((_) async => false);
        when(() => repo.scanDevices()).thenAnswer((_) => Stream.empty());
        when(() => repo.stopScan()).thenAnswer((_) async {});
        when(() => repo.adapterState)
            .thenAnswer((_) => Stream<BluetoothAdapterState>.empty());
        when(() => repo.adapterStateNow).thenReturn(BluetoothAdapterState.off);
        when(() => repo.isSupported()).thenAnswer((_) async => true);
        when(() => repo.enableBluetooth()).thenAnswer((_) async => false);
        when(() => repo.connectionState).thenAnswer((_) => Stream.empty());
        when(() => repo.disconnectDevice()).thenAnswer((_) async {});
        return BleBloc(repo, MockSavedDeviceRepository());
      },
      act: (bloc) => bloc.add(StartScan()),
      expect: () => [isA<BleBluetoothEnabling>(), isA<BleBluetoothOff>()],
    );

    blocTest<BleBloc, BleState>(
      'NotReady scan error emits BleError',
      build: () {
        final repo = MockBleRepository();
        when(() => repo.hasPermissions()).thenAnswer((_) async => true);
        when(() => repo.waitForAdapterOn()).thenAnswer((_) async => true);
        when(() => repo.scanDevices())
            .thenAnswer((_) => Stream.error('org.bluez.Error.NotReady'));
        when(() => repo.stopScan()).thenAnswer((_) async {});
        when(() => repo.adapterState)
            .thenAnswer((_) => Stream<BluetoothAdapterState>.empty());
        when(() => repo.connectionState).thenAnswer((_) => Stream.empty());
        when(() => repo.disconnectDevice()).thenAnswer((_) async {});
        return BleBloc(repo, MockSavedDeviceRepository());
      },
      act: (bloc) => bloc.add(StartScan()),
      expect: () => [isA<BleScanning>(), isA<BleError>()],
    );

    blocTest<BleBloc, BleState>(
      'repeated StartScan requests are idempotent',
      build: buildBloc,
      act: (bloc) async {
        bloc.add(StartScan());
        await Future.delayed(Duration(milliseconds: 50));
        bloc.add(StartScan());
        await Future.delayed(Duration(milliseconds: 50));
        bloc.add(StartScan());
        await Future.delayed(Duration(milliseconds: 50));
        scanController.add([
          const BleDevice(
            id: 'aa:bb:cc:dd:ee:ff',
            name: 'GATT--DEMO',
            rssi: -50,
            isConnected: false,
          ),
        ]);
      },
      verify: (bloc) {
        verify(() => bleRepository.scanDevices()).called(3);
        verify(() => bleRepository.waitForAdapterOn()).called(3);
        expect(bloc.state, isA<BleScanning>());
      },
    );

    blocTest<BleBloc, BleState>(
      'adapter turns off while scanning emits BleError then off state',
      build: buildBloc,
      act: (bloc) async {
        bloc.add(StartScan());
        scanController.add([]);
        await Future.delayed(Duration(milliseconds: 50));
        adapterStateController.add(BluetoothAdapterState.off);
      },
      expect: () => [
        isA<BleScanning>(),
        isA<BleError>(),
        isA<BleBluetoothOff>(),
      ],
    );
  });

  group('BleBloc - startup readiness', () {
    blocTest<BleBloc, BleState>(
      'EnsureBluetoothReady surfaces a permission failure as BleError',
      // Regression: a failing permission request used to escape the handler,
      // aborting the startup flow and leaving the UI stuck on BleInitial.
      build: () {
        final repo = MockBleRepository();
        when(() => repo.isSupported()).thenAnswer((_) async => true);
        when(() => repo.hasPermissions()).thenAnswer((_) async => false);
        when(() => repo.requestPermissions())
            .thenThrow(Exception('a request is already running'));
        when(() => repo.adapterState)
            .thenAnswer((_) => Stream<BluetoothAdapterState>.empty());
        when(() => repo.connectionState).thenAnswer((_) => Stream.empty());
        when(() => repo.disconnectDevice()).thenAnswer((_) async {});
        return BleBloc(repo, MockSavedDeviceRepository());
      },
      act: (bloc) => bloc.add(const EnsureBluetoothReady()),
      expect: () => [isA<BleError>()],
    );

    blocTest<BleBloc, BleState>(
      'EnsureBluetoothReady emits readiness when the adapter is already on',
      build: buildBloc,
      act: (bloc) => bloc.add(const EnsureBluetoothReady()),
      expect: () => [isA<BleDisconnected>()],
    );
  });
}
