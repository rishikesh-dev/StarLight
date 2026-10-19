// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Raw result of one WLED HTTP request.
class WledHttpResponse {
  final int statusCode;
  final String body;

  const WledHttpResponse({required this.statusCode, required this.body});
}

/// Transport seam for WLED HTTP calls.
///
/// Exists so [WledHttpAdapter] can be exercised with a scripted fake in unit
/// tests without dart:io. [IoWledTransport] is the production implementation.
/// A single shared instance may serve many devices: dart:io pools
/// connections per host, so one client is cheaper than one-per-device.
abstract class WledTransport {
  /// Performs one HTTP request and waits for the full response body.
  ///
  /// Fails with [TimeoutException] when the whole exchange (connect through
  /// body read) exceeds [timeout]; with [SocketException] for network-level
  /// failures (DNS, refused connection, unreachable host).
  Future<WledHttpResponse> request({
    required String method,
    required Uri url,
    String? body,
    required Duration timeout,
  });

  /// Releases the underlying client. Must be safe to call once; later
  /// [request] calls fail with [WledException] code `disposed`.
  void dispose();
}

/// Typed failure for a WLED transport or API operation.
///
/// [code] is a machine-readable identifier from a small fixed set:
/// `timeout`, `dns_failure`, `connection_refused`, `network_error`,
/// `http_error`, `malformed_json`, `disposed`.
class WledException implements Exception {
  final String code;
  final String message;
  final int? statusCode;

  const WledException(this.code, this.message, {this.statusCode});

  /// Maps a dart:io [SocketException] to the most specific WLED error code.
  static WledException fromSocket(SocketException e, String host) {
    final detail = e.osError?.message ?? e.message;
    final lower = detail.toLowerCase();
    if (lower.contains('refused')) {
      return WledException(
        'connection_refused',
        'Connection to $host was refused — is WLED running?',
      );
    }
    if (lower.contains('resolve') ||
        lower.contains('no address') ||
        lower.contains('name or service')) {
      return WledException(
        'dns_failure',
        'Could not resolve $host — check the hostname',
      );
    }
    if (lower.contains('timed out') || lower.contains('timeout')) {
      return WledException('timeout', 'Connection to $host timed out');
    }
    return WledException('network_error', 'Could not reach $host: $detail');
  }

  @override
  String toString() => 'WledException($code): $message';
}

/// Production [WledTransport] backed by dart:io.
///
/// Not available on web; StarLight targets Android/Linux.
class IoWledTransport implements WledTransport {
  final HttpClient _client;
  bool _disposed = false;

  IoWledTransport({HttpClient? client})
    : _client = client ?? HttpClient()
        ..connectionTimeout = const Duration(seconds: 5);

  @override
  Future<WledHttpResponse> request({
    required String method,
    required Uri url,
    String? body,
    required Duration timeout,
  }) async {
    if (_disposed) {
      throw const WledException('disposed', 'WLED transport is disposed');
    }
    final HttpClientRequest request;
    if (method.toUpperCase() == 'GET') {
      request = await _client.getUrl(url).timeout(timeout);
    } else {
      request = await _client
          .openUrl(method.toUpperCase(), url)
          .timeout(timeout);
    }
    if (body != null) {
      request.headers.contentType = ContentType.json;
      request.write(body);
    }
    final HttpClientResponse response = await request.close().timeout(timeout);
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in response) {
      bytes.add(chunk);
    }
    return WledHttpResponse(
      statusCode: response.statusCode,
      body: utf8.decode(bytes.takeBytes(), allowMalformed: true),
    );
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _client.close(force: true);
  }
}
