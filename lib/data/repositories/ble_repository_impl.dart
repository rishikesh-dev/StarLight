import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../../core/ble/ble_constants.dart';
import '../../core/errors/exceptions.dart';
import '../../core/errors/failures.dart';
import '../../core/utils/app_logger.dart';
import '../../domain/entities/ble_device.dart';
import '../../domain/entities/connection_state.dart';
import '../../domain/entities/debug_state.dart';
import '../../domain/entities/light_command.dart';
import '../../domain/repositories/ble_repository.dart';
import '../datasources/ble_datasource.dart';

/// Implementation of [BleRepository] using [BleDataSource].
///
/// GATT structure from the decompiled APK (MyApplication.java lines 202-231):
/// - Service FFF0, Write Char FFF3, Notify Char FFF4, Descriptor 2902
class BleRepositoryImpl implements BleRepository {
  final BleDataSource dataSource;

  BleRepositoryImpl(this.dataSource) {
    _listenForDebugUpdates();
  }

  DeviceConnectionState _currentState = DeviceConnectionState.disconnected;
  final DebugState _debugState = DebugState(
    serviceUuid: BleConstants.serviceUuid,
    writeCharUuid: BleConstants.writeCharUuid,
    notifyCharUuid: BleConstants.notifyCharUuid,
  );

  final StreamController<DebugState> _debugController =
      StreamController<DebugState>.broadcast();

  @override
  Stream<DeviceConnectionState> get connectionState {
    AppLog.debug('connectionState: reading connection state stream');
    final rawStream = dataSource.connectionState;
    if (rawStream == null) {
      AppLog.debug('connectionState: no stream, emitting disconnected');
      return Stream.value(DeviceConnectionState.disconnected);
    }
    return rawStream.map(_mapConnectionState).handleError((e) {
      AppLog.warn('connectionState: stream error: $e');
      _currentState = DeviceConnectionState.disconnected;
    });
  }

  @override
  Stream<DebugState> get debugState => _debugController.stream;

  void _listenForDebugUpdates() {
    AppLog.debug('_listenForDebugUpdates: watching connection + notifications');
    dataSource.connectionState?.listen((state) {
      AppLog.debug('debug connection state: $state');
      _updateDebugConnectionState(state.toString().split('.').last);
    }, onError: (e, st) {
      AppLog.warn('debug connection state error: $e');
      _updateDebugConnectionState('error');
    });

    dataSource.notificationStream.listen((data) {
      _updateDebugNotification(data);
    });
  }

  void _updateDebugConnectionState(String state) {
    _debugController.add(_debugState.copyWith(
      connectionState: state,
      connectedDeviceId: dataSource.device?.remoteId.str,
      connectedDeviceName: dataSource.device?.platformName,
    ));
  }

  void _updateDebugNotification(Uint8List data) {
    _debugController.add(_debugState.copyWith(
      lastNotificationHex: _bytesToHex(data),
      rssi: null,
    ));
  }

  @override
  Stream<List<BleDevice>> scanDevices() {
    final rawStream = dataSource.scanDevices();
    return rawStream.map((models) {
      AppLog.debug(
        'repository: scanDevices emitted ${models.length} device(s)',
      );
      return models
          .map((m) => BleDevice(
                id: m.id,
                name: m.name,
                rssi: m.rssi,
                isConnected: m.isConnected,
              ))
          .toList();
    });
  }

  @override
  Future<void> stopScan() => dataSource.stopScan();

  @override
  Future<bool> isBluetoothEnabled() => dataSource.isBluetoothEnabled();

  @override
  Future<bool> hasPermissions() => dataSource.hasPermissions();

  @override
  Future<bool> requestPermissions() => dataSource.requestPermissions();

  @override
  Stream<DeviceConnectionState> connectDevice(String deviceId) {
    AppLog.info('repository: connecting to $deviceId');
    return dataSource.connectToDevice(deviceId).map(_mapConnectionState);
  }

  @override
  Future<void> disconnectDevice() => dataSource.disconnect();

  @override
  Future<void> sendCommand(LightCommand command) async {
    AppLog.debug(
      'repository: sendCommand ${command.type} → '
      '${_bytesToHex(Uint8List.fromList(command.bytes))}',
    );
    try {
      await dataSource.writeCommand(Uint8List.fromList(command.bytes));
      _debugController.add(_debugState.copyWith(
        lastCommandHex: _bytesToHex(Uint8List.fromList(command.bytes)),
      ));
    } on CharacteristicNotFoundException {
      throw CharacteristicNotFoundFailure(BleConstants.writeCharUuid);
    } on DisconnectedException {
      throw DisconnectedFailure();
    } catch (e) {
      AppLog.error('repository: sendCommand failed', e);
      throw BleFailure(e.toString());
    }
  }

  @override
  Future<int?> readRssi() => dataSource.readRssi();

  @override
  bool get isConnected => dataSource.isConnected;

  DeviceConnectionState _mapConnectionState(BluetoothConnectionState rawState) {
    switch (rawState) {
      case BluetoothConnectionState.connected:
        _currentState = DeviceConnectionState.connected;
        break;
      case BluetoothConnectionState.disconnected:
        _currentState = DeviceConnectionState.disconnected;
        break;
      default:
        break;
    }
    return _currentState;
  }

  static String _bytesToHex(Uint8List bytes) {
    if (bytes.isEmpty) return '';
    return bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
        .join(' ');
  }
}
