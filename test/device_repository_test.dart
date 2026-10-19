import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:starlight/data/datasources/device_datasource.dart';
import 'package:starlight/data/repositories/device_repository_impl.dart';
import 'package:starlight/domain/adapters/device_adapter.dart';
import 'package:starlight/domain/entities/connection_state.dart';
import 'package:starlight/domain/entities/device.dart';
import 'package:starlight/domain/entities/device_event.dart';
import 'package:starlight/domain/entities/device_state.dart';
import 'package:starlight/domain/entities/device_type.dart';
import 'package:starlight/domain/repositories/device_repository.dart';

/// In-memory adapter used to exercise the shared command/event contract
/// without any real transport.
class FakeAdapter implements DeviceAdapter {
  final StreamController<DeviceConnectionState> connectionController =
      StreamController<DeviceConnectionState>.broadcast();
  final List<DeviceCommand> sentCommands = [];
  CommandResult resultToReturn = const CommandResult.ok();
  bool emitOnDisconnect = true;

  @override
  String get deviceTypeId => 'fake';

  @override
  String get transport => 'fake';

  @override
  Device createDevice({
    required String id,
    required String name,
    required String address,
    Map<String, dynamic> metadata = const {},
  }) {
    return Device(
      id: id,
      name: name,
      type: DeviceType.other,
      transport: 'fake',
      address: address,
      capabilities: const [],
      connectionState: DeviceConnectionState.disconnected,
      state: LightState(isOn: false, isConnected: false),
    );
  }

  @override
  Stream<DeviceConnectionState> connect(Device device) =>
      connectionController.stream;

  @override
  Future<void> disconnect(Device device) async {
    if (emitOnDisconnect) {
      connectionController.add(DeviceConnectionState.disconnected);
    }
  }

  @override
  Future<CommandResult> sendCommand(
    Device device,
    DeviceCommand command,
  ) async {
    sentCommands.add(command);
    return resultToReturn;
  }

  @override
  Future<DeviceState> readState(Device device) async => device.state;

  @override
  bool canHandle(Device device) => device.transport == 'fake';
}

Device _device(
  String id, {
  DeviceConnectionState state = DeviceConnectionState.disconnected,
}) {
  return Device(
    id: id,
    name: 'Device $id',
    type: DeviceType.other,
    transport: 'fake',
    address: 'addr-$id',
    capabilities: const [],
    connectionState: state,
    state: LightState(isOn: false, isConnected: false),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeAdapter adapter;

  DeviceRepositoryImpl repository() =>
      DeviceRepositoryImpl(adapters: [adapter]);

  setUp(() {
    adapter = FakeAdapter();
  });

  group('command contract', () {
    test('unknown device returns an explicit failure, no throw', () async {
      final repo = repository();
      final result = await repo.sendCommand(
        'missing',
        DeviceCommand.power(true),
      );

      expect(result.success, isFalse);
      expect(result.error, 'device_not_found');
    });

    test('disconnected device returns not_connected', () async {
      final repo = repository();
      await repo.addDevice(_device('dev-1'));

      final result = await repo.sendCommand('dev-1', DeviceCommand.power(true));

      expect(result.success, isFalse);
      expect(result.error, 'not_connected');
      expect(adapter.sentCommands, isEmpty);
    });

    test('device without a matching adapter returns no_adapter', () async {
      final repo = repository();
      final foreign = _device('dev-x').copyWith(
        transport: 'wifi',
        connectionState: DeviceConnectionState.connected,
      );
      await repo.addDevice(foreign);

      final result = await repo.sendCommand('dev-x', DeviceCommand.power(true));

      expect(result.success, isFalse);
      expect(result.error, 'no_adapter');
    });

    test('successful command is forwarded and reported as ok', () async {
      final repo = repository();
      await repo.addDevice(
        _device('dev-1', state: DeviceConnectionState.connected),
      );

      final result = await repo.sendCommand(
        'dev-1',
        DeviceCommand.brightness(500),
      );

      expect(result.success, isTrue);
      expect(adapter.sentCommands.single.type, 'brightness');
      expect(adapter.sentCommands.single.parameters['value'], 500);
    });

    test('adapter failure is propagated verbatim', () async {
      final repo = repository();
      await repo.addDevice(
        _device('dev-1', state: DeviceConnectionState.connected),
      );
      adapter.resultToReturn = const CommandResult.failure(
        'not_connected',
        'write characteristic missing',
      );

      final result = await repo.sendCommand('dev-1', DeviceCommand.power(true));

      expect(result.success, isFalse);
      expect(result.error, 'not_connected');
      expect(result.message, 'write characteristic missing');
    });
  });

  group('event contract', () {
    test('connect emits a connected event and updates the registry', () async {
      final repo = repository();
      await repo.addDevice(_device('dev-1'));

      final events = <DeviceEvent>[];
      final sub = repo.events.listen(events.add);

      repo.connectDevice('dev-1');
      adapter.connectionController.add(DeviceConnectionState.connected);
      await Future<void>.delayed(Duration.zero);

      expect(events, hasLength(1));
      expect(events.single.kind, DeviceEventKind.connected);
      expect(events.single.deviceId, 'dev-1');
      final stored = await repo.getDevice('dev-1');
      expect(stored!.connectionState, DeviceConnectionState.connected);

      await sub.cancel();
    });

    test('disconnect emits exactly one disconnected event', () async {
      final repo = repository();
      await repo.addDevice(
        _device('dev-1', state: DeviceConnectionState.connected),
      );

      final events = <DeviceEvent>[];
      final sub = repo.events.listen(events.add);

      repo.connectDevice('dev-1');
      adapter.connectionController.add(DeviceConnectionState.connected);
      await Future<void>.delayed(Duration.zero);

      await repo.disconnectDevice('dev-1');
      await Future<void>.delayed(Duration.zero);

      final disconnects = events
          .where((e) => e.kind == DeviceEventKind.disconnected)
          .toList();
      expect(
        disconnects,
        hasLength(1),
        reason: 'one disconnect must never be reported twice',
      );
      final stored = await repo.getDevice('dev-1');
      expect(stored!.connectionState, DeviceConnectionState.disconnected);

      await sub.cancel();
    });

    test(
      'adapter that stays silent still produces a disconnected event',
      () async {
        adapter.emitOnDisconnect = false;
        final repo = repository();
        await repo.addDevice(
          _device('dev-1', state: DeviceConnectionState.connected),
        );

        final events = <DeviceEvent>[];
        final sub = repo.events.listen(events.add);

        await repo.disconnectDevice('dev-1');
        await Future<void>.delayed(Duration.zero);

        expect(
          events.where((e) => e.kind == DeviceEventKind.disconnected),
          hasLength(1),
        );
        await sub.cancel();
      },
    );
  });

  group('persistence', () {
    test('registered devices survive a restart as disconnected', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final dataSource = DeviceDataSource(prefs);

      final first = DeviceRepositoryImpl(
        adapters: [adapter],
        deviceDataSource: dataSource,
      );
      await first.addDevice(_device('dev-1'));
      expect(await first.getDevice('dev-1'), isNotNull);

      final second = DeviceRepositoryImpl(
        adapters: [adapter],
        deviceDataSource: dataSource,
      );
      await second.loadPersistedDevices();

      final restored = await second.getDevice('dev-1');
      expect(restored, isNotNull);
      expect(restored!.name, 'Device dev-1');
      expect(restored.connectionState, DeviceConnectionState.disconnected);
    });
  });
}
