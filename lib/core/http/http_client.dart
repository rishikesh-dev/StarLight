// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

/// Factory for creating HTTP clients with consistent configuration.
///
/// Uses the dart:io HttpClient directly so no external dependencies
/// are required for WLED/MQTT network devices.
class HttpClientFactory {
  static final HttpClientFactory _instance = HttpClientFactory._internal();

  factory HttpClientFactory() => _instance;

  HttpClientFactory._internal();

  static HttpClient _httpClient = HttpClient();

  /// Configures the shared HTTP client (connect timeout, etc.).
  static void configure({
    Duration connectTimeout = const Duration(seconds: 5),
    Duration idleTimeout = const Duration(seconds: 30),
  }) {
    _httpClient = HttpClient()
      ..connectionTimeout = connectTimeout
      ..idleTimeout = idleTimeout;
  }

  /// Gets the shared HTTP client instance.
  static HttpClient create() => _httpClient;

  /// Creates a new client per request (useful for tests).
  static HttpClient createPerRequest({
    Duration connectTimeout = const Duration(seconds: 5),
  }) {
    return HttpClient()..connectionTimeout = connectTimeout;
  }
}

class HttpException implements Exception {
  final String message;
  final int? statusCode;

  HttpException(this.message, {this.statusCode});

  @override
  String toString() =>
      'HttpException(statusCode: $statusCode, message: $message)';
}

/// A simple HTTP response wrapper.
class HttpResponse {
  final String body;
  final int statusCode;

  HttpResponse({required this.body, required this.statusCode});
}
