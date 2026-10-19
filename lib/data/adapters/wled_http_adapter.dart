// SPDX-License-Identifier: Apache-2.0

// Public named parameters map onto private fields so the API stays
// readable from the repository layer.
// ignore_for_file: prefer_initializing_formals
import 'dart:async';
import 'dart:convert';
import 'dart:io' show SocketException;

import 'package:starlight/data/models/wled_snapshot.dart';
import 'package:starlight/data/transport/wled_transport.dart';
import 'package:starlight/domain/entities/device_command.dart';
import 'package:starlight/domain/entities/wled_config.dart';

/// Outcome of a WLED state update.
///
/// [confirmed] is the state object the device echoed back (WLED answers a
/// state POST with the resulting state when sent with `"v": true`). It is
/// null when the firmware only answered `{"success": true}` — the caller
/// must not treat that as state confirmation.
class WledCommandOutcome {
  final WledLightState? confirmed;

  const WledCommandOutcome({this.confirmed});
}

/// Talks to one WLED device using the documented JSON API
/// (https://kno.wled.ge/interfaces/json-api/):
///
/// - `GET /json` — combined state, info, effect names and palette names.
/// - `POST /json/state` — partial state update; StarLight always sends
///   `"v": true` so the response echoes the resulting state and a command
///   is only counted as applied after that response (or a follow-up read)
///   has been evaluated.
///
/// All failures surface as [WledException] with a stable [WledException.code];
/// callers (the repository) map those onto the shared [CommandResult]
/// contract. This adapter performs no retries and no optimistic state.
class WledHttpAdapter {
  final WledTransport _transport;
  final WledConfig _config;

  WledHttpAdapter({
    required WledTransport transport,
    required WledConfig config,
  }) : _transport = transport,
       _config = config;

  Uri get _base => Uri(
    scheme: _config.useHttps ? 'https' : 'http',
    host: _config.host,
    port: _config.port,
  );

  /// Reads the full device snapshot (state + info + effect/palette names).
  Future<WledSnapshot> fetchSnapshot() async {
    final response = await _request('GET', '/json');
    return WledSnapshot.fromJson(_decode(response, 'state'));
  }

  /// Applies a partial state update and returns the device-confirmed state.
  Future<WledCommandOutcome> sendUpdate(Map<String, dynamic> patch) async {
    final body = jsonEncode({...patch, 'v': true});
    final response = await _request('POST', '/json/state', body: body);
    final json = _decode(response, 'state update');
    if (json.length == 1 && json['success'] == true) {
      return const WledCommandOutcome(confirmed: null);
    }
    final stateJson = json['state'] is Map ? json['state'] : json;
    return WledCommandOutcome(confirmed: WledLightState.fromJson(stateJson));
  }

  Future<WledHttpResponse> _request(
    String method,
    String path, {
    String? body,
  }) async {
    final url = _base.replace(path: path);
    try {
      final response = await _transport.request(
        method: method,
        url: url,
        body: body,
        timeout: Duration(seconds: _config.timeoutSeconds),
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw WledException(
          'http_error',
          'WLED returned HTTP ${response.statusCode}',
          statusCode: response.statusCode,
        );
      }
      return response;
    } on WledException {
      rethrow;
    } on TimeoutException {
      throw WledException('timeout', 'Request to ${_config.host} timed out');
    } on SocketException catch (e) {
      throw WledException.fromSocket(e, _config.host);
    }
  }

  Map<String, dynamic> _decode(WledHttpResponse response, String what) {
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is! Map) {
        throw const FormatException('expected a JSON object');
      }
      return Map<String, dynamic>.from(decoded);
    } on FormatException {
      throw WledException(
        'malformed_json',
        'WLED returned an invalid JSON response',
      );
    }
  }
}

/// Maps the shared [DeviceCommand] contract onto WLED state-patch fields.
///
/// Conventions:
/// - `brightness`/`speed` parameters are percentages (0-100); WLED uses
///   0-255, so values are scaled (100 -> 255).
/// - `color` parameters are 0-255 per channel.
/// - `effect` resolves `parameters['id']` when present, otherwise matches
///   `parameters['name']` against the device-reported effect list.
///
/// Returns null (with an error code) for anything WLED cannot express:
/// out-of-range values, unknown effects, or commands the firmware does not
/// support (e.g. palettes on legacy firmware).
/// Result of building a WLED payload: either a state patch to send or an
/// explicit rejection reason.
class WledPayload {
  final Map<String, dynamic> patch;
  final String? error;

  const WledPayload._(this.patch, this.error);

  factory WledPayload.ok(Map<String, dynamic> patch) =>
      WledPayload._(patch, null);

  factory WledPayload.reject(String error) => WledPayload._(const {}, error);

  bool get isRejected => error != null;

  static WledPayload build(
    DeviceCommand command, {
    required bool segmentBased,
    required List<String> effects,
  }) {
    switch (command.type) {
      case 'power':
        final on = command.parameters['on'];
        if (on is! bool) return WledPayload.reject('invalid_value');
        return WledPayload.ok({'on': on});

      case 'brightness':
        final percent = _percent(command.parameters['value']);
        if (percent == null) return WledPayload.reject('invalid_value');
        return WledPayload.ok({'bri': _to255(percent)});

      case 'color':
        final r = _channel(command.parameters['red']);
        final g = _channel(command.parameters['green']);
        final b = _channel(command.parameters['blue']);
        if (r == null || g == null || b == null) {
          return WledPayload.reject('invalid_value');
        }
        final color = [r, g, b];
        return segmentBased
            ? WledPayload.ok({
                'seg': {
                  'col': [color],
                },
              })
            : WledPayload.ok({'c': color});

      case 'effect':
        final id = _resolveEffectId(command, effects);
        if (id == null) {
          return WledPayload.reject(
            command.parameters.containsKey('name')
                ? 'effect_not_found'
                : 'invalid_value',
          );
        }
        return segmentBased
            ? WledPayload.ok({
                'seg': {'fx': id},
              })
            : WledPayload.ok({'fx': id});

      case 'palette':
        final id = _channel(command.parameters['id']);
        if (id == null) return WledPayload.reject('invalid_value');
        if (!segmentBased) {
          // Palettes only exist in the 0.14+ segment API.
          return WledPayload.reject('unsupported_command');
        }
        return WledPayload.ok({
          'seg': {'pal': id},
        });

      case 'speed':
        final percent = _percent(command.parameters['value']);
        if (percent == null) return WledPayload.reject('invalid_value');
        return segmentBased
            ? WledPayload.ok({
                'seg': {'sx': _to255(percent)},
              })
            : WledPayload.ok({'sx': _to255(percent)});

      default:
        return WledPayload.reject('unsupported_command');
    }
  }

  static int? _resolveEffectId(DeviceCommand command, List<String> effects) {
    // Some callers (e.g. the MQTT adapter) nest the id under `params`.
    final parameters = command.parameters;
    Object? direct = parameters['id'];
    if (direct == null && parameters['params'] is Map) {
      direct = (parameters['params'] as Map)['id'];
    }
    if (direct is int && direct >= 0 && direct < 256) return direct;
    final name = parameters['name'];
    if (name is! String || name.trim().isEmpty) return null;
    final wanted = name.trim().toLowerCase();
    for (var i = 0; i < effects.length; i++) {
      if (effects[i].toLowerCase() == wanted) return i;
    }
    return null;
  }

  /// 0-100 inclusive, else null.
  static int? _percent(Object? value) {
    if (value is int) return value >= 0 && value <= 100 ? value : null;
    if (value is double) {
      return value >= 0 && value <= 100 ? value.round() : null;
    }
    return null;
  }

  /// 0-255 inclusive, else null.
  static int? _channel(Object? value) {
    if (value is int) return value >= 0 && value <= 255 ? value : null;
    if (value is double) {
      final v = value.round();
      return v >= 0 && v <= 255 ? v : null;
    }
    return null;
  }

  static int _to255(int percent) => (percent * 255 / 100).round();
}
