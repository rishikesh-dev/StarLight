import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:starlight/core/ble/ble_constants.dart';
import 'package:starlight/core/ble/ble_permission_gateway.dart';
import 'package:starlight/core/ble/ble_platform.dart';
import 'package:starlight/core/errors/exceptions.dart';
import 'package:starlight/data/datasources/ble_datasource.dart';

/// Test double for [BlePlatform] that records scan/adapter interactions and
/// lets tests drive adapter transitions deterministically.
class FakeBlePlatform implements BlePlatform {
  final StreamController<BluetoothAdapterState> adapterStateController =
      StreamController<BluetoothAdapterState>.broadcast();
  final StreamController<List<ScanResult>> scanResultsController =
      StreamController<List<ScanResult>>.broadcast();

  BluetoothAdapterState currentAdapterState = BluetoothAdapterState.off;

  int startScanCalls = 0;
  int stopScanCalls = 0;
  int turnOnCalls = 0;

  /// Optional gate: when set, [startScan] waits for it to complete.
  Completer<void>? startScanGate;

  /// Optional gate: when set, [turnOn] waits for it to complete.
  Completer<void>? turnOnGate;

  /// When true, [turnOn] throws (models the user declining).
  bool turnOnShouldThrow = false;

  @override
  Stream<BluetoothAdapterState> get adapterState =>
      adapterStateController.stream;

  @override
  BluetoothAdapterState get adapterStateNow => currentAdapterState;

  @override
  Stream<List<ScanResult>> get scanResults => scanResultsController.stream;

  @override
  Future<void> startScan({
    Duration? timeout,
    AndroidScanMode androidScanMode = AndroidScanMode.lowPower,
    bool continuousUpdates = false,
  }) async {
    startScanCalls++;
    final gate = startScanGate;
    if (gate != null) await gate.future;
  }

  @override
  Future<void> stopScan() async {
    stopScanCalls++;
  }

  @override
  Future<bool> get isSupported async => true;

  @override
  Future<void> turnOn({int timeout = 60}) async {
    turnOnCalls++;
    if (turnOnShouldThrow) {
      throw Exception('user rejected');
    }
    final gate = turnOnGate;
    if (gate != null) await gate.future;
  }

  Future<void> dispose() async {
    await adapterStateController.close();
    await scanResultsController.close();
  }
}

/// Test double for [BlePermissionGateway] that records calls and returns canned
/// results. Used to assert how [BleDataSource] delegates the permission flow
/// without touching platform channels or showing system dialogs.
class FakeBlePermissionGateway implements BlePermissionGateway {
  bool hasPermissions = true;
  bool permanentlyDenied = false;
  bool requestResult = true;
  Object? requestError;

  int hasCalls = 0;
  int isPermanentlyDeniedCalls = 0;
  int requestCalls = 0;
  int openSettingsCalls = 0;

  @override
  Future<bool> hasRequiredPermissions() async {
    hasCalls++;
    return hasPermissions;
  }

  @override
  Future<bool> isPermanentlyDenied() async {
    isPermanentlyDeniedCalls++;
    return permanentlyDenied;
  }

  @override
  Future<bool> requestRequiredPermissions() async {
    requestCalls++;
    final error = requestError;
    if (error != null) throw error;
    return requestResult;
  }

  @override
  Future<void> openSystemSettings() async {
    openSettingsCalls++;
  }
}

class MockBluetoothDevice extends Mock implements BluetoothDevice {}

class MockBluetoothService extends Mock implements BluetoothService {}

class MockBluetoothCharacteristic extends Mock
    implements BluetoothCharacteristic {}

/// A mock platform device plus the stream used to drive its connection state.
class FakeDevice {
  final MockBluetoothDevice device;
  final StreamController<BluetoothConnectionState> controller;
  final MockBluetoothCharacteristic writeChar;
  final MockBluetoothCharacteristic notifyChar;

  FakeDevice._(this.device, this.controller, this.writeChar, this.notifyChar);
}

MockBluetoothCharacteristic _makeChar(String uuid) {
  final c = MockBluetoothCharacteristic();
  when(() => c.uuid).thenReturn(Guid(uuid));
  when(() => c.descriptors).thenReturn(<BluetoothDescriptor>[]);
  when(() => c.onValueReceived)
      .thenAnswer((_) => const Stream<List<int>>.empty());
  return c;
}

FakeDevice _makeDevice(String id, {bool notifySucceeds = true}) {
  final controller = StreamController<BluetoothConnectionState>.broadcast();
  final device = MockBluetoothDevice();
  when(() => device.remoteId).thenReturn(DeviceIdentifier(id));
  when(() => device.isConnected).thenReturn(true);
  when(
    () => device.connect(
      autoConnect: any(named: 'autoConnect'),
      timeout: any(named: 'timeout'),
    ),
  ).thenAnswer((_) async {});
  when(() => device.disconnect()).thenAnswer((_) async {});
  when(() => device.connectionState).thenAnswer((_) => controller.stream);

  final write = _makeChar(BleConstants.writeCharUuid);
  final notify = _makeChar(BleConstants.notifyCharUuid);
  when(() => notify.setNotifyValue(any())).thenAnswer((_) async {
    if (!notifySucceeds) {
      throw Exception('notify failed');
    }
    return true;
  });

  final service = MockBluetoothService();
  when(() => service.uuid).thenReturn(Guid(BleConstants.serviceUuid));
  when(() => service.characteristics).thenReturn([write, notify]);
  when(() => device.discoverServices()).thenAnswer((_) async => [service]);

  return FakeDevice._(device, controller, write, notify);
}

void main() {
  late FakeBlePlatform platform;
  late BleDataSource dataSource;

  setUpAll(() {
    registerFallbackValue(const Duration(seconds: 0));
    registerFallbackValue(<int>[]);
    registerFallbackValue(false);
  });

  Future<void> settle([int iterations = 10]) async {
    for (var i = 0; i < iterations; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  /// Runs a full connect against [fd] and waits until the write characteristic
  /// is installed (i.e. discovery/subscription finished).
  Future<void> connect(FakeDevice fd, String id) async {
    dataSource.connectToDevice(id);
    for (var i = 0; i < 200 && !fd.controller.hasListener; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    fd.controller.add(BluetoothConnectionState.connected);
    for (var i = 0; i < 200 && dataSource.writeCharacteristic == null; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(
      dataSource.writeCharacteristic,
      isNotNull,
      reason: 'connect should install the write characteristic',
    );
  }

  setUp(() {
    platform = FakeBlePlatform();
    dataSource = BleDataSource(platform: platform);
  });

  tearDown(() async {
    await platform.dispose();
  });

  group('BleDataSource permissions', () {
    late FakeBlePermissionGateway permissions;

    setUp(() {
      permissions = FakeBlePermissionGateway();
      dataSource = BleDataSource(platform: platform, permissions: permissions);
    });

    test('requestPermissions issues exactly one batched request', () async {
      expect(await dataSource.requestPermissions(), isTrue);

      expect(
        permissions.requestCalls,
        1,
        reason:
            'Android rejects concurrent runtime-permission requests; the data '
            'source must issue a single batched request',
      );
    });

    test('requestPermissions reports a denial', () async {
      permissions.requestResult = false;
      expect(await dataSource.requestPermissions(), isFalse);
    });

    test('hasPermissions delegates to the gateway', () async {
      permissions.hasPermissions = false;
      expect(await dataSource.hasPermissions(), isFalse);

      permissions.hasPermissions = true;
      expect(await dataSource.hasPermissions(), isTrue);
      expect(permissions.hasCalls, 2);
    });

    test('isPermanentlyDenied delegates to the gateway', () async {
      permissions.permanentlyDenied = true;
      expect(await dataSource.isPermanentlyDenied(), isTrue);
      expect(permissions.isPermanentlyDeniedCalls, 1);
    });

    test('openSystemSettings delegates to the gateway', () async {
      await dataSource.openSystemSettings();
      expect(permissions.openSettingsCalls, 1);
    });
  });

  group('BleDataSource scan sessions', () {
    test(
      'a superseded scan session cannot start a second platform scan',
      () async {
        // Adapter starts off so both scan sessions park inside
        // waitForAdapterOn until the test drives an adapter `on` transition.
        platform.currentAdapterState = BluetoothAdapterState.off;

        // Start two overlapping scan sessions while the adapter is off.
        dataSource.scanDevices();
        dataSource.scanDevices();

        // Let both handlers reach the adapter wait.
        await Future<void>.delayed(Duration.zero);

        // Adapter comes on: both parked waits resolve, but only the current
        // (second) session may actually start a platform scan.
        platform.currentAdapterState = BluetoothAdapterState.on;
        platform.adapterStateController.add(BluetoothAdapterState.on);

        await settle(5);

        expect(
          platform.startScanCalls,
          1,
          reason: 'a stale scan session must not start a platform scan',
        );
      },
    );

    test('stopScan invalidates the active session', () async {
      platform.currentAdapterState = BluetoothAdapterState.off;
      dataSource.scanDevices();
      await Future<void>.delayed(Duration.zero);
      await dataSource.stopScan();

      platform.currentAdapterState = BluetoothAdapterState.on;
      platform.adapterStateController.add(BluetoothAdapterState.on);
      await settle(5);

      expect(platform.startScanCalls, 0);
    });
  });

  group('BleDataSource enableBluetooth', () {
    test('returns true only once the adapter is confirmed on', () async {
      platform.currentAdapterState = BluetoothAdapterState.off;
      platform.turnOnGate = Completer<void>();

      final future = dataSource.enableBluetooth();
      // Simulate the adapter reaching on before turnOn resolves.
      platform.currentAdapterState = BluetoothAdapterState.on;
      platform.turnOnGate!.complete();

      expect(await future, isTrue);
      expect(platform.turnOnCalls, 1);
    });

    test(
      'duplicate enable requests do not open the system dialog twice',
      () async {
        platform.currentAdapterState = BluetoothAdapterState.off;
        platform.turnOnGate = Completer<void>();

        final first = dataSource.enableBluetooth();
        final second = dataSource.enableBluetooth();
        await Future<void>.delayed(Duration.zero);

        expect(
          platform.turnOnCalls,
          1,
          reason: 'only one system enable request may be in flight',
        );

        platform.currentAdapterState = BluetoothAdapterState.on;
        platform.turnOnGate!.complete();
        await first;
        await second;
        expect(platform.turnOnCalls, 1);
      },
    );

    test('returns false when the user declines to enable Bluetooth', () async {
      platform.currentAdapterState = BluetoothAdapterState.off;
      platform.turnOnShouldThrow = true;

      expect(await dataSource.enableBluetooth(), isFalse);
    });

    test(
      'returns true without requesting when the adapter is already on',
      () async {
        platform.currentAdapterState = BluetoothAdapterState.on;

        expect(await dataSource.enableBluetooth(), isTrue);
        expect(platform.turnOnCalls, 0);
      },
    );
  });

  group('BleDataSource command queue', () {
    test('rejects a pending command with a disconnection error', () async {
      final fd = _makeDevice('AA:BB:CC:DD:EE:01');
      final gate = Completer<void>();
      when(() => fd.writeChar.write(any(), withoutResponse: true))
          .thenAnswer((_) => gate.future);

      dataSource = BleDataSource(
        platform: platform,
        deviceFactory: (id) => fd.device,
      );
      await connect(fd, 'AA:BB:CC:DD:EE:01');

      final pending = dataSource.writeCommand(
        Uint8List.fromList([0xBC, 0x01, 0x55]),
      );
      var completed = false;
      unawaited(
        pending.then((_) => completed = true, onError: (_) => completed = true),
      );
      await settle(3);
      expect(completed, isFalse, reason: 'the write is still in flight');

      await dataSource.disconnect();

      await expectLater(pending, throwsA(isA<DisconnectedException>()));
      expect(fd.writeChar, isNotNull);
    });

    test('does not start a second write before the first completes', () async {
      final fd = _makeDevice('AA:BB:CC:DD:EE:02');
      final gates = <Completer<void>>[];
      when(() => fd.writeChar.write(any(), withoutResponse: true))
          .thenAnswer((_) {
            final g = Completer<void>();
            gates.add(g);
            return g.future;
          });

      dataSource = BleDataSource(
        platform: platform,
        deviceFactory: (id) => fd.device,
      );
      await connect(fd, 'AA:BB:CC:DD:EE:02');

      final first = dataSource.writeCommand(Uint8List.fromList([1]));
      final second = dataSource.writeCommand(Uint8List.fromList([2]));
      await settle(3);

      expect(gates.length, 1, reason: 'second write must wait for the first');

      gates[0].complete();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(gates.length, 2, reason: 'second write starts after the first');

      gates[1].complete();
      await first;
      await second;
    });

    test('a write failure surfaces to the caller', () async {
      final fd = _makeDevice('AA:BB:CC:DD:EE:03');
      when(() => fd.writeChar.write(any(), withoutResponse: true))
          .thenThrow(Exception('io error'));

      dataSource = BleDataSource(
        platform: platform,
        deviceFactory: (id) => fd.device,
      );
      await connect(fd, 'AA:BB:CC:DD:EE:03');

      await expectLater(
        dataSource.writeCommand(Uint8List.fromList([1])),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('BleDataSource connection lifecycle', () {
    test('notification failure connects command-only', () async {
      final fd = _makeDevice('AA:BB:CC:DD:EE:04', notifySucceeds: false);
      when(() => fd.writeChar.write(any(), withoutResponse: true))
          .thenAnswer((_) async {});

      dataSource = BleDataSource(
        platform: platform,
        deviceFactory: (id) => fd.device,
      );
      await connect(fd, 'AA:BB:CC:DD:EE:04');

      expect(dataSource.isConnected, isTrue);
      expect(
        dataSource.notificationsReady,
        isFalse,
        reason: 'notifications could not be enabled, so only commands work',
      );
      // Writes still work in command-only mode.
      await dataSource.writeCommand(Uint8List.fromList([1]));
    });

    test('notifications are reported ready when enabled', () async {
      final fd = _makeDevice('AA:BB:CC:DD:EE:05');
      dataSource = BleDataSource(
        platform: platform,
        deviceFactory: (id) => fd.device,
      );
      await connect(fd, 'AA:BB:CC:DD:EE:05');

      expect(dataSource.notificationsReady, isTrue);
    });

    test('switching devices tears down the previous session', () async {
      final a = _makeDevice('AA:BB:CC:DD:EE:06');
      final b = _makeDevice('AA:BB:CC:DD:EE:07');
      final devices = {
        'AA:BB:CC:DD:EE:06': a.device,
        'AA:BB:CC:DD:EE:07': b.device,
      };

      dataSource = BleDataSource(
        platform: platform,
        deviceFactory: (id) => devices[id]!,
      );

      await connect(a, 'AA:BB:CC:DD:EE:06');
      await connect(b, 'AA:BB:CC:DD:EE:07');

      verify(() => a.device.disconnect()).called(1);
      expect(dataSource.device, same(b.device));

      // A late disconnect from the superseded session must not clobber the
      // current one.
      a.controller.add(BluetoothConnectionState.disconnected);
      await settle(3);
      expect(dataSource.device, same(b.device));
    });
  });
}
