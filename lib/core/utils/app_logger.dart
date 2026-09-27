import 'package:flutter/foundation.dart';

/// Minimal structured logger for the StarLight app.
///
/// Timestamps and log levels are printed to the platform console via
/// [debugPrint]. Toggle [AppLog.enabled] to silence all output.
///
/// Usage:
/// ```dart
/// AppLog.info('Scan started');
/// AppLog.error('Connection failed', e, stackTrace);
/// ```
class AppLog {
  AppLog._();

  /// Set to `false` to disable all logging.
  static bool enabled = true;

  /// Debug-level message, e.g. protocol bytes or fine-grained tracing.
  static void debug(String message) => _log('DEBUG', message);

  /// Informational message, e.g. lifecycle events and user actions.
  static void info(String message) => _log('INFO', message);

  /// Warning message, e.g. recoverable or unexpected conditions.
  static void warn(String message) => _log('WARN', message);

  /// Error message with optional [error] and [stackTrace].
  static void error(
    String message, [
    Object? error,
    StackTrace? stackTrace,
  ]) {
    _log('ERROR', message, error: error, stackTrace: stackTrace);
  }

  static void _log(
    String level,
    String message, {
    Object? error,
    StackTrace? stackTrace,
  }) {
    if (!enabled) return;
    final now = DateTime.now();
    final stamp = '${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}:'
        '${now.second.toString().padLeft(2, '0')}.'
        '${now.millisecond.toString().padLeft(3, '0')}';
    var line = '[$stamp] [$level] $message';
    if (error != null) {
      line += '\n  └─ $error';
    }
    if (stackTrace != null) {
      line += '\n$stackTrace';
    }
    debugPrint(line);
  }
}