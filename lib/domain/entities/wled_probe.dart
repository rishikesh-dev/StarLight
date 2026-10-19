// SPDX-License-Identifier: Apache-2.0

import 'package:equatable/equatable.dart';

import 'network_device.dart';

/// Outcome of probing a (not necessarily saved) WLED device.
///
/// Failures carry a machine-readable [error] code (`invalid_configuration`,
/// `timeout`, `dns_failure`, `connection_refused`, `network_error`,
/// `http_error`, `malformed_json`) plus a human-readable [message] that is
/// safe to show in the UI.
class WledProbe extends Equatable {
  final bool ok;
  final String? error;
  final String? message;

  /// Populated on success: the device's reported identity, capabilities and
  /// confirmed state, ready to be registered.
  final NetworkDevice? device;

  const WledProbe.success(this.device)
    : ok = true,
      error = null,
      message = null;

  const WledProbe.failure(this.error, [this.message])
    : ok = false,
      device = null;

  @override
  List<Object?> get props => [ok, error, message, device];
}
