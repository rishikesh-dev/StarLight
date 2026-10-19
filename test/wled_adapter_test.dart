import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:starlight/data/adapters/wled_http_adapter.dart';
import 'package:starlight/data/transport/wled_transport.dart';
import 'package:starlight/domain/entities/device_command.dart';
import 'package:starlight/domain/entities/wled_config.dart';

/// Scripted fake for [WledTransport]. Each call consumes the next scripted
/// response/exception in FIFO order; calls are recorded for assertions.
class FakeWledTransport implements WledTransport {
  final List<Scripted> script = [];
  final List<TransportCall> calls = [];
  int _index = 0;
  bool disposed = false;

  @override
  Future<WledHttpResponse> request({
    required String method,
    required Uri url,
    String? body,
    required Duration timeout,
  }) async {
    calls.add(TransportCall(method, url, body, timeout));
    if (_index >= script.length) {
      throw StateError('No scripted response for call ${calls.length}');
    }
    final item = script[_index++];
    if (item.exception != null) throw item.exception!;
    return item.response!;
  }

  @override
  void dispose() => disposed = true;
}

class Scripted {
  final WledHttpResponse? response;
  final Object? exception;
  const Scripted(this.response, [this.exception]);
}

class TransportCall {
  final String method;
  final Uri url;
  final String? body;
  final Duration timeout;
  const TransportCall(this.method, this.url, this.body, this.timeout);
}

WledHttpAdapter makeAdapter(
  FakeWledTransport transport, {
  String host = 'wled.local',
  int port = 80,
  bool https = false,
}) {
  return WledHttpAdapter(
    transport: transport,
    config: WledConfig(host: host, port: port, useHttps: https),
  );
}

void main() {
  group('WledHttpAdapter.fetchSnapshot', () {
    test('GETs /json and parses the combined response', () async {
      final transport = FakeWledTransport()
        ..script.add(
          const Scripted(
            WledHttpResponse(
              statusCode: 200,
              body:
                  '{"state":{"on":true,"bri":128,"c":[1,2,3]},'
                  '"info":{"ver":"0.14.4","mac":"aa"},"effects":["Solid"],'
                  '"palettes":["Default"]}',
            ),
          ),
        );
      final adapter = makeAdapter(transport);

      final snapshot = await adapter.fetchSnapshot();

      expect(transport.calls.single.method, 'GET');
      expect(transport.calls.single.url.path, '/json');
      expect(snapshot.info.version, '0.14.4');
      expect(snapshot.state.on, isTrue);
      expect(snapshot.effects, ['Solid']);
    });

    test('uses https scheme when configured', () async {
      final transport = FakeWledTransport()
        ..script.add(
          const Scripted(
            WledHttpResponse(
              statusCode: 200,
              body: '{"state":{"on":true,"bri":1},"info":{"ver":"1"}}',
            ),
          ),
        );
      final adapter = makeAdapter(transport, host: 'wled.local', https: true);
      await adapter.fetchSnapshot();
      expect(transport.calls.single.url.scheme, 'https');
      expect(transport.calls.single.url.port, 80);
    });

    test('non-2xx status becomes http_error with status code', () async {
      final transport = FakeWledTransport()
        ..script.add(
          const Scripted(
            WledHttpResponse(statusCode: 500, body: 'Internal Server Error'),
          ),
        );
      final adapter = makeAdapter(transport);

      await expectLater(
        adapter.fetchSnapshot(),
        throwsA(
          isA<WledException>().having((e) => e.code, 'code', 'http_error'),
        ),
      );
    });

    test('malformed JSON becomes malformed_json', () async {
      final transport = FakeWledTransport()
        ..script.add(
          const Scripted(
            WledHttpResponse(statusCode: 200, body: 'this is not json'),
          ),
        );
      await expectLater(
        makeAdapter(transport).fetchSnapshot(),
        throwsA(
          isA<WledException>().having((e) => e.code, 'code', 'malformed_json'),
        ),
      );
    });

    test('JSON that is not an object becomes malformed_json', () async {
      final transport = FakeWledTransport()
        ..script.add(
          const Scripted(WledHttpResponse(statusCode: 200, body: '[1,2,3]')),
        );
      await expectLater(
        makeAdapter(transport).fetchSnapshot(),
        throwsA(
          isA<WledException>().having((e) => e.code, 'code', 'malformed_json'),
        ),
      );
    });

    test('TimeoutException becomes timeout', () async {
      final transport = FakeWledTransport()
        ..script.add(Scripted(null, TimeoutException('boom')));
      await expectLater(
        makeAdapter(transport).fetchSnapshot(),
        throwsA(isA<WledException>().having((e) => e.code, 'code', 'timeout')),
      );
    });
  });

  group('WledHttpAdapter.sendUpdate', () {
    test(
      'POSTs to /json/state with v:true and returns confirmed state',
      () async {
        final transport = FakeWledTransport()
          ..script.add(
            const Scripted(
              WledHttpResponse(
                statusCode: 200,
                body: '{"on":true,"bri":128,"c":[9,8,7]}',
              ),
            ),
          );
        final adapter = makeAdapter(transport);

        final outcome = await adapter.sendUpdate({'on': true, 'bri': 128});

        final call = transport.calls.single;
        expect(call.method, 'POST');
        expect(call.url.path, '/json/state');
        expect(call.body, isNotNull);
        expect(
          call.body!.contains('"v":true'),
          isTrue,
          reason: 'v:true must be sent so the device echoes state',
        );
        expect(outcome.confirmed, isNotNull);
        expect(outcome.confirmed!.on, isTrue);
        expect(outcome.confirmed!.brightness, 128);
      },
    );

    test('{"success":true} alone yields null confirmed state', () async {
      final transport = FakeWledTransport()
        ..script.add(
          const Scripted(
            WledHttpResponse(statusCode: 200, body: '{"success":true}'),
          ),
        );
      final outcome = await makeAdapter(transport).sendUpdate({'on': false});
      expect(outcome.confirmed, isNull);
    });

    test('HTTP error surfaces as WledException', () async {
      final transport = FakeWledTransport()
        ..script.add(
          const Scripted(WledHttpResponse(statusCode: 404, body: 'not found')),
        );
      await expectLater(
        makeAdapter(transport).sendUpdate({'on': true}),
        throwsA(
          isA<WledException>().having((e) => e.code, 'code', 'http_error'),
        ),
      );
    });
  });

  group('WledPayload.build', () {
    test('power on/off', () {
      final on = WledPayload.build(
        DeviceCommand.power(true),
        segmentBased: true,
        effects: const [],
      );
      expect(on.patch, {'on': true});
      final off = WledPayload.build(
        DeviceCommand.power(false),
        segmentBased: true,
        effects: const [],
      );
      expect(off.patch, {'on': false});
    });

    test('brightness percent maps to 0-255', () {
      final mid = WledPayload.build(
        DeviceCommand.brightness(50),
        segmentBased: false,
        effects: const [],
      );
      expect(mid.patch, {'bri': 128}); // 50*255/100 = 127.5 -> 128
      final max = WledPayload.build(
        DeviceCommand.brightness(100),
        segmentBased: false,
        effects: const [],
      );
      expect(max.patch, {'bri': 255});
      final zero = WledPayload.build(
        DeviceCommand.brightness(0),
        segmentBased: false,
        effects: const [],
      );
      expect(zero.patch, {'bri': 0});
    });

    test('brightness out of range is rejected', () {
      final bad = WledPayload.build(
        DeviceCommand.brightness(101),
        segmentBased: false,
        effects: const [],
      );
      expect(bad.isRejected, isTrue);
      expect(bad.error, 'invalid_value');
    });

    test('color legacy vs segment format', () {
      final legacy = WledPayload.build(
        DeviceCommand.color(255, 0, 0),
        segmentBased: false,
        effects: const [],
      );
      expect(legacy.patch, {
        'c': [255, 0, 0],
      });

      final seg = WledPayload.build(
        DeviceCommand.color(255, 0, 0),
        segmentBased: true,
        effects: const [],
      );
      expect(seg.patch, {
        'seg': {
          'col': [
            [255, 0, 0],
          ],
        },
      });
    });

    test('color channel out of range is rejected', () {
      final bad = WledPayload.build(
        DeviceCommand.color(256, 0, 0),
        segmentBased: false,
        effects: const [],
      );
      expect(bad.isRejected, isTrue);
    });

    test('effect by id and by name', () {
      const effects = ['Solid', 'Rainbow', 'Bounce'];
      final byId = WledPayload.build(
        DeviceCommand.effect('Rainbow', id: 1),
        segmentBased: true,
        effects: effects,
      );
      expect(byId.patch, {
        'seg': {'fx': 1},
      });

      final byName = WledPayload.build(
        DeviceCommand.effect('bounce', id: null),
        segmentBased: false,
        effects: effects,
      );
      expect(byName.patch, {'fx': 2});
    });

    test('unknown effect name is rejected', () {
      final bad = WledPayload.build(
        DeviceCommand.effect('Not There'),
        segmentBased: false,
        effects: const ['Solid'],
      );
      expect(bad.isRejected, isTrue);
      expect(bad.error, 'effect_not_found');
    });

    test('palette only on segment firmware', () {
      final seg = WledPayload.build(
        DeviceCommand.palette(3),
        segmentBased: true,
        effects: const [],
      );
      expect(seg.patch, {
        'seg': {'pal': 3},
      });

      final legacy = WledPayload.build(
        DeviceCommand.palette(3),
        segmentBased: false,
        effects: const [],
      );
      expect(legacy.isRejected, isTrue);
      expect(legacy.error, 'unsupported_command');
    });

    test('unsupported command type is rejected', () {
      final bad = WledPayload.build(
        DeviceCommand.colorTemperature(3000),
        segmentBased: true,
        effects: const [],
      );
      expect(bad.isRejected, isTrue);
      expect(bad.error, 'unsupported_command');
    });
  });
}
