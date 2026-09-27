import 'package:equatable/equatable.dart';

/// A debug state tracking the last sent command and most recent notification.
class DebugState extends Equatable {
  final String? connectedDeviceId;
  final String? connectedDeviceName;
  final int? rssi;
  final String? serviceUuid;
  final String? writeCharUuid;
  final String? notifyCharUuid;
  final String? lastCommandHex;
  final String? lastNotificationHex;
  final String? connectionState;

  const DebugState({
    this.connectedDeviceId,
    this.connectedDeviceName,
    this.rssi,
    this.serviceUuid,
    this.writeCharUuid,
    this.notifyCharUuid,
    this.lastCommandHex,
    this.lastNotificationHex,
    this.connectionState,
  });

  DebugState copyWith({
    String? connectedDeviceId,
    String? connectedDeviceName,
    int? rssi,
    String? serviceUuid,
    String? writeCharUuid,
    String? notifyCharUuid,
    String? lastCommandHex,
    String? lastNotificationHex,
    String? connectionState,
  }) {
    return DebugState(
      connectedDeviceId: connectedDeviceId ?? this.connectedDeviceId,
      connectedDeviceName: connectedDeviceName ?? this.connectedDeviceName,
      rssi: rssi ?? this.rssi,
      serviceUuid: serviceUuid ?? this.serviceUuid,
      writeCharUuid: writeCharUuid ?? this.writeCharUuid,
      notifyCharUuid: notifyCharUuid ?? this.notifyCharUuid,
      lastCommandHex: lastCommandHex ?? this.lastCommandHex,
      lastNotificationHex: lastNotificationHex ?? this.lastNotificationHex,
      connectionState: connectionState ?? this.connectionState,
    );
  }

  @override
  List<Object?> get props => [
        connectedDeviceId,
        connectedDeviceName,
        rssi,
        serviceUuid,
        writeCharUuid,
        notifyCharUuid,
        lastCommandHex,
        lastNotificationHex,
        connectionState,
      ];
}
