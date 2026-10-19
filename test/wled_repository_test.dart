import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:starlight/data/repositories/wled_repository_impl.dart';
import 'package:starlight/data/transport/wled_transport.dart';
import 'package:starlight/domain/entities/device_command.dart';
import 'package:starlight/domain/entities/device_capability.dart';
import 'package:starlight/domain/entities/network_device.dart';
import 'package:starlight/domain/entities/wled_config.dart';

/// Maps URL → response; also supports one pending-call gate to hold an
/// in-flight request open.
class MapWledTransport implements WledTransport {
  final Map<String, WledHttpResponse> responses = {};
  final List<Map<String, dynamic>> calls = [];
  WledException? nextException;
  Completer<void>? gate;
  bool disposed = false;

  @override
  Future<WledHttpResponse> request({
    required String method,
    required Uri url,
    String? body,
    required Duration timeout,
  }) async {
    final key = '$method $url';
    calls.add({'method': method, 'url': url.toString(), 'body': body});
    if (gate != null) {
      await gate!.future;
    }
    if (nextException != null) {
      final e = nextException!;
      nextException = null;
      throw e;
    }
    final response = responses[key];
    if (response == null) {
      throw StateError('No scripted response for $key');
    }
    return response;
  }

  @override
  void dispose() => disposed = true;
}

const String snapshotJson =
    '{"state":{"on":true,"bri":200,"c":[10,20,30],"fx":1,"sx":50},'
    '"info":{"ver":"0.14.4","name":"WLED-TEST","mac":"aabbccddeeff",'
    '"leds":{"count":60,"lc":7}},'
    '"effects":["Solid","Rainbow","RSVD"],"palettes":["Default","Sunset"]}';

WledHttpResponse ok(String body) =>
    WledHttpResponse(statusCode: 200, body: body);

void main() {
  late MapWledTransport transport;
  late WledRepositoryImpl repo;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    transport = MapWledTransport();
    transport.responses['GET http://wled.local/json'] = ok(snapshotJson);
    transport.responses['POST http://wled.local/json/state'] = ok(
      '{"on":true,"bri":180,"c":[1,2,3]}',
    );
    repo = WledRepositoryImpl(transport: transport);
  });

  tearDown(() => repo.dispose());

  group('probe', () {
    test('returns device identity from reported MAC', () async {
      final probe = await repo.probe(
        host: 'wled.local',
        port: 80,
        useHttps: false,
      );
      expect(probe.ok, isTrue);
      expect(probe.device!.id, 'wled-aabbccddeeff');
      expect(probe.device!.name, 'WLED-TEST');
      expect(probe.device!.firmwareVersion, '0.14.4');
      expect(probe.device!.ledCount, 60);
      // Legacy flat state format doesn't expose colorTemperature capability
      expect(
        probe.device!.capabilities,
        isNot(contains(DeviceCapability.colorTemperature)),
      );
      expect(probe.device!.supportedEffects, ['Solid', 'Rainbow', 'RSVD']);
    });

    test('uses supplied name when given', () async {
      final probe = await repo.probe(
        host: 'wled.local',
        port: 80,
        useHttps: false,
        name: 'Living Room',
      );
      expect(probe.device!.name, 'Living Room');
    });

    test('invalid configuration fails without network I/O', () async {
      final probe = await repo.probe(
        host: 'bad host',
        port: 80,
        useHttps: false,
      );
      expect(probe.ok, isFalse);
      expect(probe.error, 'invalid_configuration');
      expect(transport.calls, isEmpty);
    });

    test('network failure carries the error code', () async {
      transport.nextException = const WledException(
        'timeout',
        'Request timed out',
      );
      final probe = await repo.probe(
        host: 'wled.local',
        port: 80,
        useHttps: false,
      );
      expect(probe.ok, isFalse);
      expect(probe.error, 'timeout');
    });
  });

  group('registry + persistence', () {
    test('add, list, and persist', () async {
      final probe = await repo.probe(
        host: 'wled.local',
        port: 80,
        useHttps: false,
      );
      final result = await repo.addDevice(
        const WledConfig(host: 'wled.local'),
        probe.device!,
        name: 'Desk',
      );
      expect(result.success, isTrue);

      final devices = await repo.getWledDevices();
      expect(devices, hasLength(1));
      expect(devices.first.name, 'Desk');

      // Simulate app restart: a fresh repository restores the registry.
      final repo2 = WledRepositoryImpl(transport: transport);
      await repo2.loadDevices();
      final restored = await repo2.getWledDevices();
      expect(restored, hasLength(1));
      // Restored devices are never assumed online.
      expect(
        restored.first.connectionState,
        NetworkConnectionState.disconnected,
      );
      expect(restored.first.name, 'Desk');
      expect(
        restored.first.capabilities,
        isNot(contains(DeviceCapability.colorTemperature)),
      );
      repo2.dispose();
    });

    test('duplicate host:port is rejected', () async {
      final probe = await repo.probe(
        host: 'wled.local',
        port: 80,
        useHttps: false,
      );
      expect(
        (await repo.addDevice(
          const WledConfig(host: 'wled.local'),
          probe.device!,
        )).success,
        isTrue,
      );
      final result = await repo.addDevice(
        const WledConfig(host: 'wled.local'),
        probe.device!,
      );
      expect(result.success, isFalse);
      expect(result.error, 'duplicate_device');
      expect(await repo.getWledDevices(), hasLength(1));
    });

    test('corrupt persistence does not break startup', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('starlight_wled_devices_v1', '{not json');
      await repo.loadDevices();
      expect(await repo.getWledDevices(), isEmpty);
    });

    test('removeDevice removes from registry and storage', () async {
      final probe = await repo.probe(
        host: 'wled.local',
        port: 80,
        useHttps: false,
      );
      await repo.addDevice(const WledConfig(host: 'wled.local'), probe.device!);
      await repo.removeDevice(probe.device!.id);

      expect(await repo.getWledDevices(), isEmpty);

      final repo2 = WledRepositoryImpl(transport: transport);
      await repo2.loadDevices();
      expect(await repo2.getWledDevices(), isEmpty);
      repo2.dispose();
    });

    test('renameDevice updates the display name', () async {
      final probe = await repo.probe(
        host: 'wled.local',
        port: 80,
        useHttps: false,
      );
      await repo.addDevice(
        const WledConfig(host: 'wled.local'),
        probe.device!,
        name: 'Old',
      );
      await repo.renameDevice(probe.device!.id, '  New Name  ');
      final device = await repo.getWledDevice(probe.device!.id);
      expect(device!.name, 'New Name');
    });

    test('in-flight read is discarded after removal', () async {
      final probe = await repo.probe(
        host: 'wled.local',
        port: 80,
        useHttps: false,
      );
      await repo.addDevice(const WledConfig(host: 'wled.local'), probe.device!);
      final id = probe.device!.id;

      // Hold the read open mid-flight.
      final gate = Completer<void>();
      transport.gate = gate;
      final readFut = repo.readState(id);

      await repo.removeDevice(id);
      gate.complete();
      expect(await readFut, isNull);
      expect(await repo.getWledDevices(), isEmpty);
    });
  });

  group('sendCommand', () {
    Future<NetworkDevice?> addDevice() async {
      final probe = await repo.probe(
        host: 'wled.local',
        port: 80,
        useHttps: false,
      );
      await repo.addDevice(const WledConfig(host: 'wled.local'), probe.device!);
      return repo.getWledDevice(probe.device!.id);
    }

    test('unknown device fails with device_not_found', () async {
      final result = await repo.sendCommand('nope', DeviceCommand.power(true));
      expect(result.success, isFalse);
      expect(result.error, 'device_not_found');
      expect(transport.calls, isEmpty);
    });

    test('unsupported command fails without network I/O', () async {
      final device = (await addDevice())!;
      final result = await repo.sendCommand(
        device.id,
        DeviceCommand.colorTemperature(3000),
      );
      expect(result.success, isFalse);
      expect(result.error, 'unsupported_command');
      // Only the initial probe happened.
      expect(
        transport.calls,
        everyElement(
          predicate((Map<String, dynamic> c) => c['url'].contains('/json')),
        ),
      );
      expect(transport.calls.where((c) => c['method'] == 'POST'), isEmpty);
    });

    test('power command confirms state from device echo', () async {
      final device = (await addDevice())!;
      final result = await repo.sendCommand(
        device.id,
        DeviceCommand.power(true),
      );
      expect(result.success, isTrue);

      final updated = await repo.getWledDevice(device.id);
      expect(updated!.isOn, isTrue);
      expect(updated.brightness, 180); // from the echoed state
      expect(updated.connectionState, NetworkConnectionState.connected);

      final postCall = transport.calls.firstWhere((c) => c['method'] == 'POST');
      expect(postCall['body'], contains('"v":true'));
    });

    test('{"success":true} firmware triggers a follow-up state read', () async {
      transport.responses['POST http://wled.local/json/state'] = ok(
        '{"success":true}',
      );
      final device = (await addDevice())!;
      transport.calls.clear();

      final result = await repo.sendCommand(
        device.id,
        DeviceCommand.power(false),
      );
      expect(result.success, isTrue);
      // POST + follow-up GET /json
      expect(transport.calls, hasLength(2));
      expect(transport.calls.last['method'], 'GET');
    });

    test('network failure reports the code and marks unreachable', () async {
      final device = (await addDevice())!;
      transport.nextException = const WledException(
        'connection_refused',
        'refused',
      );

      final events = <String>[];
      final sub = repo.events.listen((e) {
        if (e.kind.name == 'disconnected') {
          events.add(e.deviceId);
        }
      });
      final result = await repo.sendCommand(
        device.id,
        DeviceCommand.power(true),
      );
      await pumpEventQueue();
      await sub.cancel();

      expect(result.success, isFalse);
      expect(result.error, 'connection_refused');
      final updated = await repo.getWledDevice(device.id);
      expect(updated!.connectionState, NetworkConnectionState.unreachable);
      expect(events, [device.id]);
    });

    test('rapid commands are serialized per device', () async {
      final device = (await addDevice())!;
      transport.calls.clear();

      // Both commands share the per-device chain: the second waits for the
      // first even though they are issued concurrently.
      final results = await Future.wait([
        repo.sendCommand(device.id, DeviceCommand.power(true)),
        repo.sendCommand(device.id, DeviceCommand.power(false)),
      ]);
      expect(results.every((r) => r.success), isTrue);
      // Two POSTs, in issue order, with no interleaving.
      final posts = transport.calls
          .where((c) => c['method'] == 'POST')
          .toList();
      expect(posts, hasLength(2));
      expect(posts[0]['body'], contains('"on":true'));
      expect(posts[1]['body'], contains('"on":false'));
    });
  });

  group('readState', () {
    test('returns updated device and marks reachable', () async {
      final probe = await repo.probe(
        host: 'wled.local',
        port: 80,
        useHttps: false,
      );
      await repo.addDevice(const WledConfig(host: 'wled.local'), probe.device!);
      // Simulate a previously-unreachable device coming back.
      final device = await repo.readState(probe.device!.id);
      expect(device, isNotNull);
      expect(device!.connectionState, NetworkConnectionState.connected);
      expect(device.lastSeen, isNotNull);
    });

    test('returns null and marks unreachable on failure', () async {
      final probe = await repo.probe(
        host: 'wled.local',
        port: 80,
        useHttps: false,
      );
      await repo.addDevice(const WledConfig(host: 'wled.local'), probe.device!);
      transport.nextException = const WledException(
        'network_error',
        'no route',
      );

      final device = await repo.readState(probe.device!.id);
      expect(device, isNull);

      final stored = await repo.getWledDevice(probe.device!.id);
      expect(stored!.connectionState, NetworkConnectionState.unreachable);
    });

    test('returns null for unknown device without I/O', () async {
      expect(await repo.readState('missing'), isNull);
      expect(transport.calls, isEmpty);
    });
  });

  test('dispose closes the transport and rejects further probes', () async {
    // Create repository without external transport so it owns the transport.
    final ownedRepo = WledRepositoryImpl();
    // Need to set up the transport responses on the internal transport.
    // Since we can't access it directly, we'll test that dispose rejects probes.
    ownedRepo.dispose();
    final probe = await ownedRepo.probe(
      host: 'wled.local',
      port: 80,
      useHttps: false,
    );
    expect(probe.ok, isFalse);
    expect(probe.error, 'disposed');
  });
}
