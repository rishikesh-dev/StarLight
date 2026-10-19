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

class FakeSavedDevice extends Fake implements SavedDevice {}

class FakeDevice extends Fake implements Device {}

/// Coverage for the paired-device lifecycle added for the device UX redesign:
/// loading the saved pairing, reconnecting on demand, renaming, and forgetting.
/// These never auto-connect and never fabricate a connection.
void main() {
  late MockBleRepository bleRepository;
  late MockSavedDeviceRepository savedRepo;
  late MockDeviceRepository deviceRepository;
  late StreamController<DeviceConnectionState> connectionController;
  late StreamController<BluetoothAdapterState> adapterStateController;

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
    when(() => bleRepository.scanDevices()).thenAnswer((_) => Stream.empty());
    when(() => bleRepository.stopScan()).thenAnswer((_) async {});
    when(() => bleRepository.connectDevice(any()))
        .thenAnswer((_) => connectionController.stream);
    when(() => bleRepository.disconnectDevice()).thenAnswer((_) async {});
    when(() => bleRepository.connectionState)
        .thenAnswer((_) => connectionController.stream);
    when(() => savedRepo.load()).thenAnswer((_) async => null);
    when(() => savedRepo.save(any())).thenAnswer((_) async {});
    when(() => savedRepo.remove()).thenAnswer((_) async {});
    when(() => deviceRepository.updateDevice(any())).thenAnswer((_) async {});
    when(() => deviceRepository.removeDevice(any())).thenAnswer((_) async {});
    when(() => deviceRepository.getDevice(any())).thenAnswer((_) async => null);
  });

  tearDown(() async {
    await connectionController.close();
    await adapterStateController.close();
  });

  BleBloc buildBloc() =>
      BleBloc(bleRepository, savedRepo, deviceRepository: deviceRepository);

  group('LoadPairedDevice', () {
    blocTest<BleBloc, BleState>(
      'surfaces the persisted device without connecting',
      build: buildBloc,
      setUp: () => when(() => savedRepo.load()).thenAnswer(
        (_) async =>
            const SavedDevice(id: 'AA:BB:CC:DD:EE:FF', name: 'Living Room'),
      ),
      act: (bloc) => bloc.add(const LoadPairedDevice()),
      expect: () => [
        isA<BleDisconnected>()
            .having((s) => s.device, 'device', isNotNull)
            .having((s) => s.device!.name, 'device name', 'Living Room')
            .having((s) => s.device!.id, 'device id', 'AA:BB:CC:DD:EE:FF'),
      ],
      verify: (_) => verifyNever(() => bleRepository.connectDevice(any())),
    );

    test('is a no-op when nothing has been paired', () async {
      final bloc = buildBloc();
      addTearDown(bloc.close);
      bloc.add(const LoadPairedDevice());
      await pumpEventQueue();
      expect(bloc.state, isA<BleInitial>());
    });
  });

  group('ReconnectRequested', () {
    test(
      'connects to the persisted device and emits a connecting state',
      () async {
        when(
          () => savedRepo.load(),
        ).thenAnswer((_) async => const SavedDevice(id: 'AA:BB', name: 'Lamp'));
        final bloc = buildBloc();
        addTearDown(bloc.close);

        bloc.add(const ReconnectRequested());
        final state = await bloc.stream.firstWhere((s) => s is BleConnecting);

        expect((state as BleConnecting).deviceId, 'AA:BB');
        verify(() => bleRepository.connectDevice('AA:BB')).called(1);
      },
    );

    test('is a no-op when nothing has been paired', () async {
      final bloc = buildBloc();
      addTearDown(bloc.close);
      bloc.add(const ReconnectRequested());
      await pumpEventQueue();
      expect(bloc.state, isA<BleInitial>());
      verifyNever(() => bleRepository.connectDevice(any()));
    });
  });

  group('RenameDevice', () {
    test('persists the new name and re-emits the paired device', () async {
      when(() => savedRepo.load())
          .thenAnswer((_) async => const SavedDevice(id: 'AA:BB', name: 'Old'));
      final saved = <SavedDevice>[];
      when(() => savedRepo.save(any())).thenAnswer((invocation) async {
        saved.add(invocation.positionalArguments.first as SavedDevice);
      });

      final bloc = buildBloc();
      addTearDown(bloc.close);

      bloc.add(const LoadPairedDevice());
      await bloc.stream.firstWhere(
        (s) => s is BleDisconnected && s.device != null,
      );

      bloc.add(const RenameDevice('New Lamp'));
      final state = await bloc.stream.firstWhere(
        (s) => s is BleDisconnected && s.device?.name == 'New Lamp',
      );

      expect((state as BleDisconnected).device!.name, 'New Lamp');
      expect(saved.last.id, 'AA:BB');
      expect(saved.last.name, 'New Lamp');
    });

    test('ignores an empty name', () async {
      when(() => savedRepo.load())
          .thenAnswer((_) async => const SavedDevice(id: 'AA:BB', name: 'Old'));
      final bloc = buildBloc();
      addTearDown(bloc.close);

      bloc.add(const LoadPairedDevice());
      await bloc.stream.firstWhere(
        (s) => s is BleDisconnected && s.device != null,
      );

      bloc.add(const RenameDevice('   '));
      await pumpEventQueue();

      verifyNever(() => savedRepo.save(any()));
      final state = bloc.state as BleDisconnected;
      expect(state.device!.name, 'Old');
    });
  });

  group('ForgetDevice', () {
    test(
      'disconnects, clears the pairing and removes it from the registry',
      () async {
        when(
          () => savedRepo.load(),
        ).thenAnswer((_) async => const SavedDevice(id: 'AA:BB', name: 'Lamp'));

        final bloc = buildBloc();
        addTearDown(bloc.close);

        bloc.add(const LoadPairedDevice());
        await bloc.stream.firstWhere(
          (s) => s is BleDisconnected && s.device != null,
        );

        bloc.add(const ForgetDevice());
        final state = await bloc.stream.firstWhere(
          (s) => s is BleDisconnected && s.device == null,
        );

        expect(
          (state as BleDisconnected).connectionState,
          DeviceConnectionState.disconnected,
        );
        verify(() => savedRepo.remove()).called(1);
        verify(() => deviceRepository.removeDevice('AA:BB')).called(1);
      },
    );
  });
}
