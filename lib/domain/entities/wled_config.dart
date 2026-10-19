// SPDX-License-Identifier: Apache-2.0

import 'package:equatable/equatable.dart';

/// Configuration for reaching a WLED device over its JSON HTTP API.
///
/// WLED serves the JSON API on port 80 by default. TLS builds (or a reverse
/// proxy) use 443 with [useHttps].
class WledConfig extends Equatable {
  final String host;
  final int port;
  final bool useHttps;
  final int timeoutSeconds;

  const WledConfig({
    required this.host,
    this.port = 80,
    this.useHttps = false,
    this.timeoutSeconds = 5,
  });

  // --- validation ---------------------------------------------------------

  /// Returns an error message, or null when [host] is a usable address.
  ///
  /// Accepts IPv4 literals, RFC 1123 hostnames (including single-label LAN
  /// names like `wled`) and IPv6 literals (with or without square brackets).
  /// Rejects empty input, whitespace, and anything URL-shaped so a pasted
  /// full URL is caught before it reaches the network.
  static String? validateHost(String rawHost) {
    final host = rawHost.trim().toLowerCase();
    if (host.isEmpty) return 'Host is required';
    if (host.contains(' ') ||
        host.contains('/') ||
        host.contains('?') ||
        host.contains('#')) {
      return 'Host must not contain spaces, "/" or "?" — enter a plain '
          'IP address or hostname';
    }

    // IPv6 literal (possibly bracketed).
    if (host.contains(':')) {
      final literal = host.startsWith('[')
          ? (host.endsWith(']')
                ? host.substring(1, host.length - 1)
                : host.substring(1))
          : host;
      if (literal.length < 2 || literal.length > 45 || !literal.contains(':')) {
        return 'Not a valid IPv6 address';
      }
      return null;
    }

    // IPv4 literal.
    if (RegExp(r'^\d{1,3}(\.\d{1,3}){3}$').hasMatch(host)) {
      for (final octet in host.split('.')) {
        if (int.parse(octet) > 255) return 'Not a valid IP address';
      }
      return null;
    }

    // Hostname (RFC 1123).
    if (host.length > 253) return 'Host is too long';
    for (final label in host.split('.')) {
      if (label.isEmpty ||
          label.length > 63 ||
          !RegExp(r'^[a-z0-9]([a-z0-9-]*[a-z0-9])?$').hasMatch(label)) {
        return 'Host contains invalid characters';
      }
    }
    return null;
  }

  /// Validates every field; returns an error message or null.
  static String? validate({
    required String host,
    required int port,
    required int timeoutSeconds,
  }) {
    final hostError = validateHost(host);
    if (hostError != null) return hostError;
    if (port < 1 || port > 65535) return 'Port must be between 1 and 65535';
    if (timeoutSeconds < 1 || timeoutSeconds > 60) {
      return 'Timeout must be between 1 and 60 seconds';
    }
    return null;
  }

  // --- persistence --------------------------------------------------------

  factory WledConfig.fromMap(Map<String, dynamic> map) {
    return WledConfig(
      host: map['host'] as String? ?? '',
      port: (map['port'] as int?) ?? 80,
      useHttps: map['useHttps'] as bool? ?? false,
      timeoutSeconds: (map['timeoutSeconds'] as int?) ?? 5,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'host': host,
      'port': port,
      'useHttps': useHttps,
      'timeoutSeconds': timeoutSeconds,
    };
  }

  WledConfig copyWith({
    String? host,
    int? port,
    bool? useHttps,
    int? timeoutSeconds,
  }) {
    return WledConfig(
      host: host ?? this.host,
      port: port ?? this.port,
      useHttps: useHttps ?? this.useHttps,
      timeoutSeconds: timeoutSeconds ?? this.timeoutSeconds,
    );
  }

  @override
  List<Object?> get props => [host, port, useHttps, timeoutSeconds];
}
