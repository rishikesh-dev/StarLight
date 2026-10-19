// SPDX-License-Identifier: Apache-2.0

import 'package:equatable/equatable.dart';

/// The kind of event a device can emit through the shared event contract.
enum DeviceEventKind {
  /// The device connected.
  connected,

  /// The device disconnected (expected or not).
  disconnected,

  /// The device reported new state.
  stateUpdated,

  /// A command or transport operation failed.
  error,
}

/// A transport-agnostic event emitted by the device layer.
///
/// This is the single event contract shared by scenes, automations and the
/// JARVIS/API surface. Adapters never expose protocol-specific packets here —
/// only device identity, event kind and optional structured data.
class DeviceEvent extends Equatable {
  final String deviceId;
  final DeviceEventKind kind;
  final DateTime timestamp;
  final Map<String, dynamic> data;

  const DeviceEvent({
    required this.deviceId,
    required this.kind,
    required this.timestamp,
    this.data = const {},
  });

  /// Convenience constructor for a connection-state event.
  factory DeviceEvent.connectionChanged({
    required String deviceId,
    required bool connected,
    DateTime? timestamp,
  }) {
    return DeviceEvent(
      deviceId: deviceId,
      kind: connected
          ? DeviceEventKind.connected
          : DeviceEventKind.disconnected,
      timestamp: timestamp ?? DateTime.now(),
    );
  }

  @override
  List<Object?> get props => [deviceId, kind, timestamp, data];
}
