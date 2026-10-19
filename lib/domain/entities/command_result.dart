// SPDX-License-Identifier: Apache-2.0

import 'package:equatable/equatable.dart';

/// Explicit outcome of sending a command to a device.
///
/// Part of the common command contract: a failed or refused command always
/// reports [success: false] with a machine-readable [error] code and a
/// human-readable [message]. Callers (BLoCs, scenes, automations, JARVIS)
/// must surface this outcome instead of assuming success.
///
/// Never throw for expected device conditions (offline, unknown device,
/// unsupported command). Those are reported through this object.
class CommandResult extends Equatable {
  final bool success;
  final String? error;
  final String? message;
  final String? correlationId;

  const CommandResult({
    required this.success,
    this.error,
    this.message,
    this.correlationId,
  });

  const CommandResult.ok({this.correlationId})
    : success = true,
      error = null,
      message = null;

  const CommandResult.failure(String code, [this.message])
    : success = false,
      error = code,
      correlationId = null;

  @override
  List<Object?> get props => [success, error, message, correlationId];

  @override
  String toString() =>
      'CommandResult(success=$success, error=$error, message=$message)';
}
