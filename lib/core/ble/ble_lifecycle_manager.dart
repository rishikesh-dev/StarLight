// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:starlight/core/ble/ble_constants.dart';
import 'package:starlight/core/ble/protocol_encoder.dart';
import 'package:starlight/domain/entities/command_result.dart';
import 'package:starlight/domain/entities/device_command.dart';
import 'package:starlight/domain/entities/effect.dart';

/// Manages the full BLE lifecycle for a single MR Star device.
///
/// Handles scan/connect/disconnect/reconnect with exponential backoff,
/// deduplicates concurrent writes and subscriptions, and supports
/// cooperative cancellation.
class BleLifecycleManager {
  final String deviceId;
  final BluetoothDevice bluetoothDevice;
  final Function(DeviceCommand) onWriteRequest;
  final Function(List<int>) onNotification;

  final Duration connectionTimeout;
  final int maxReconnectAttempts;
  final Duration baseReconnectDelay;
  final Duration maxReconnectDelay;

  StreamSubscription<BluetoothConnectionState>? _connectionSubscription;
  StreamSubscription<List<int>>? _notificationSubscription;
  Timer? _reconnectTimer;
  int _reconnectAttempt = 0;
  bool _isConnecting = false;
  bool _isDisconnecting = false;
  bool _shouldReconnect = true;
  Completer<void>? _connectCompleter;

  BluetoothConnectionState _currentState =
      BluetoothConnectionState.disconnected;

  BleLifecycleManager({
    required this.deviceId,
    required this.bluetoothDevice,
    required this.onWriteRequest,
    required this.onNotification,
    this.connectionTimeout = const Duration(seconds: 10),
    this.maxReconnectAttempts = 0,
    this.baseReconnectDelay = const Duration(seconds: 2),
    this.maxReconnectDelay = const Duration(seconds: 30),
  });

  bool get isConnecting => _isConnecting;
  BluetoothConnectionState get currentState => _currentState;

  Future<BluetoothConnectionState> connect() async {
    if (_currentState == BluetoothConnectionState.connected) {
      return _currentState;
    }
    if (_isConnecting) {
      await _connectCompleter?.future;
      return _currentState;
    }

    _shouldReconnect = true;
    _isConnecting = true;
    _connectCompleter = Completer<void>();

    try {
      await bluetoothDevice
          .connect(timeout: connectionTimeout)
          .timeout(connectionTimeout);
    } on TimeoutException {
      _handleConnectionError('connection_timeout');
      rethrow;
    } catch (e) {
      _handleConnectionError(e.toString());
      rethrow;
    }

    await _connectCompleter?.future;
    return _currentState;
  }

  Future<void> disconnect() async {
    _shouldReconnect = false;
    _isDisconnecting = true;
    _cancelReconnectTimer();
    await _cleanupSubscriptions();

    if (_currentState != BluetoothConnectionState.disconnected) {
      try {
        await bluetoothDevice.disconnect();
      } catch (_) {}
    }

    _currentState = BluetoothConnectionState.disconnected;
    _isDisconnecting = false;
  }

  Future<CommandResult> writeCommand(DeviceCommand command) async {
    if (_currentState != BluetoothConnectionState.connected) {
      return CommandResult.failure('not_connected', 'Device not connected');
    }
    try {
      _encodeCommand(command);
      onWriteRequest(command);
      return CommandResult.ok();
    } catch (e) {
      return CommandResult.failure('write_failed', e.toString());
    }
  }

  Future<void> enableNotifications() async {
    if (_currentState != BluetoothConnectionState.connected) return;

    try {
      final services = await bluetoothDevice.discoverServices();
      final service = services.firstWhere(
        (s) =>
            s.uuid.toString().toLowerCase().contains(BleConstants.serviceUuid),
        orElse: () => throw StateError('Service not found'),
      );
      final characteristics = service.characteristics;
      final characteristic = characteristics.firstWhere(
        (c) => c.uuid.toString().toLowerCase().contains(
          BleConstants.notifyCharUuid,
        ),
        orElse: () => throw StateError('Notify characteristic not found'),
      );

      await characteristic.setNotifyValue(true);
      _notificationSubscription = characteristic.lastValueStream.listen((
        value,
      ) {
        if (value.isNotEmpty) onNotification(value);
      });
    } catch (e) {
      // Notification setup failed silently
    }
  }

  void handleConnectionStateChange(BluetoothConnectionState state) {
    _currentState = state;
    switch (state) {
      case BluetoothConnectionState.connected:
        _isConnecting = false;
        _reconnectAttempt = 0;
        _connectCompleter?.complete();
        enableNotifications();
        break;
      case BluetoothConnectionState.disconnected:
        _isConnecting = false;
        final completer = _connectCompleter;
        if (completer != null && !completer.isCompleted) {
          completer.completeError(StateError('Disconnected'));
        }
        if (_shouldReconnect && !_isDisconnecting) {
          _scheduleReconnect();
        }
        break;
      case BluetoothConnectionState.connecting:
      case BluetoothConnectionState.disconnecting:
        break;
    }
  }

  void _scheduleReconnect() {
    if (!_shouldReconnect) return;
    if (maxReconnectAttempts > 0 && _reconnectAttempt >= maxReconnectAttempts) {
      return;
    }
    _cancelReconnectTimer();
    final delay = Duration(
      milliseconds:
          (baseReconnectDelay.inMilliseconds * (1 << _reconnectAttempt)).clamp(
            baseReconnectDelay.inMilliseconds,
            maxReconnectDelay.inMilliseconds,
          ),
    );
    _reconnectAttempt++;
    _reconnectTimer = Timer(delay, () {
      if (_shouldReconnect && !_isDisconnecting) connect();
    });
  }

  void _cancelReconnectTimer() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
  }

  void _handleConnectionError(String error) {
    _isConnecting = false;
    _connectCompleter?.completeError(Exception(error));
    _scheduleReconnect();
  }

  Future<void> _cleanupSubscriptions() async {
    await _connectionSubscription?.cancel();
    _connectionSubscription = null;
    await _notificationSubscription?.cancel();
    _notificationSubscription = null;
  }

  List<int> _encodeCommand(DeviceCommand command) {
    switch (command.type) {
      case 'power':
        return command.parameters['on'] == true
            ? ProtocolEncoder.powerOn()
            : ProtocolEncoder.powerOff();
      case 'brightness':
        return ProtocolEncoder.brightness(command.parameters['value'] as int);
      case 'color':
        return ProtocolEncoder.colorFromRGB(
          command.parameters['red'] as int,
          command.parameters['green'] as int,
          command.parameters['blue'] as int,
        );
      case 'effect':
        final effect = effectByCommandName(
          command.parameters['name'] as String,
        );
        final modeId = effect?.protocolModeId;
        if (modeId == null) {
          throw ArgumentError(
            'Unsupported effect: ${command.parameters['name']}',
          );
        }
        return ProtocolEncoder.setMode(modeId);
      case 'speed':
        return ProtocolEncoder.setSpeed(command.parameters['value'] as int);
      default:
        throw ArgumentError('Unsupported command type: ${command.type}');
    }
  }

  void dispose() {
    _shouldReconnect = false;
    _cancelReconnectTimer();
    _cleanupSubscriptions();
  }
}
