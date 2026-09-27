import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:starlight/core/ble/ble_constants.dart';
import 'package:starlight/core/ble/protocol_encoder.dart';
import 'package:starlight/core/utils/app_logger.dart';
import 'package:starlight/core/utils/hex_utils.dart';
import 'package:starlight/core/utils/uuid_utils.dart';
import 'package:starlight/domain/adapters/device_adapter.dart';
import 'package:starlight/domain/entities/connection_state.dart';
import 'package:starlight/domain/entities/device.dart';
import 'package:starlight/domain/entities/device_capability.dart';
import 'package:starlight/domain/entities/device_state.dart';
import 'package:starlight/domain/entities/device_type.dart';
import 'package:starlight/domain/repositories/device_repository.dart';

/// BLE adapter for StarLight RGB LED controllers (MR Star GATT--DEMO).
/// Implements the DeviceAdapter interface for the universal architecture.
class StarLightBleAdapter implements DeviceAdapter {
  @override
  String get deviceTypeId => 'starlight';

  @override
  String get transport => 'ble';

  // BLE state
  BluetoothDevice? _connectedDevice;
  BluetoothService? _service;
  BluetoothCharacteristic? _writeCharacteristic;
  BluetoothCharacteristic? _notifyCharacteristic;

  StreamController<DeviceConnectionState>? _connectionStateController;
  StreamController<Uint8List>? _notificationController;

  StreamSubscription<BluetoothConnectionState>? _deviceStateSub;
  StreamSubscription<List<int>>? _notificationSub;

  bool _isConnecting = false;

  // Command queue for serialized writes
  final List<Future<void> Function()> _commandQueue = [];
  bool _isWriting = false;

  @override
  Device createDevice({
    required String id,
    required String name,
    required String address,
    Map<String, dynamic> metadata = const {},
  }) {
    return Device(
      id: id,
      name: name,
      type: DeviceType.light,
      manufacturer: 'MR Star',
      model: 'GATT--DEMO',
      transport: 'ble',
      address: address,
      roomId: metadata['roomId'] as String?,
      capabilities: [
        DeviceCapability.power,
        DeviceCapability.brightness,
        DeviceCapability.color,
        DeviceCapability.effect,
        DeviceCapability.speed,
      ],
      connectionState: DeviceConnectionState.disconnected,
      state: LightState(isOn: false, isConnected: false),
      favorite: metadata['favorite'] as bool? ?? false,
      metadata: metadata,
    );
  }

  @override
  Stream<DeviceConnectionState> connect(Device device) {
    AppLog.info('StarLightBleAdapter: connecting to ${device.id}');
    if (_isConnecting) {
      AppLog.warn('StarLightBleAdapter: already connecting, returning existing stream');
      return _connectionStateController?.stream ??
          Stream.value(DeviceConnectionState.disconnected);
    }
    _isConnecting = true;
    _connectionStateController =
        StreamController<DeviceConnectionState>.broadcast();

    _connectToAddress(device.address).then((_) {
      _isConnecting = false;
    }).catchError((e) {
      _isConnecting = false;
      _handleError(e);
    });

    return _connectionStateController!.stream;
  }

  Future<void> _connectToAddress(String address) async {
    AppLog.info('StarLightBleAdapter: _connectToAddress $address');
    try {
      _connectedDevice = BluetoothDevice.fromId(address);

      await _connectedDevice!.connect(
        autoConnect: false,
        timeout: const Duration(seconds: 15),
      );
      AppLog.info('StarLightBleAdapter: connect() returned for $address');

      _setupDeviceStateListener();

      await _waitForConnectedOrTimeout();

      await _discoverServices();

      _connectionStateController?.add(DeviceConnectionState.connected);
    } on Exception catch (e) {
      AppLog.error('StarLightBleAdapter: connection flow failed', e);
      _handleError(e);
    }
  }

  void _setupDeviceStateListener() {
    AppLog.debug('StarLightBleAdapter: listening to connection state');
    _deviceStateSub?.cancel();
    _deviceStateSub = _connectedDevice!.connectionState.listen((state) {
      AppLog.debug('StarLightBleAdapter: connection state changed: $state');
      if (_connectionStateController != null &&
          !_connectionStateController!.isClosed) {
        _mapAndEmit(state);
      }

      if (state == BluetoothConnectionState.disconnected) {
        _handleDisconnect();
      }
    });
  }

  void _mapAndEmit(BluetoothConnectionState rawState) {
    switch (rawState) {
      case BluetoothConnectionState.connected:
        _connectionStateController?.add(DeviceConnectionState.connected);
        break;
      case BluetoothConnectionState.disconnected:
        _connectionStateController?.add(DeviceConnectionState.disconnected);
        break;
      case BluetoothConnectionState.connecting:
        _connectionStateController?.add(DeviceConnectionState.connecting);
        break;
      case BluetoothConnectionState.disconnecting:
        _connectionStateController?.add(DeviceConnectionState.disconnecting);
        break;
    }
  }

  Future<void> _waitForConnectedOrTimeout() async {
    if (_connectedDevice == null) {
      AppLog.error('StarLightBleAdapter: no connected device');
      throw DisconnectedException();
    }
    try {
      await _connectedDevice!.connectionState
          .firstWhere(
            (s) => s == BluetoothConnectionState.connected,
            orElse: () => throw DisconnectedException(),
          )
          .timeout(const Duration(seconds: 15));
      AppLog.info('StarLightBleAdapter: device is connected');
    } on TimeoutException {
      AppLog.error('StarLightBleAdapter: timed out waiting for connection');
      throw ConnectionTimeoutException();
    }
  }

  void _handleDisconnect() {
    AppLog.warn('StarLightBleAdapter: device disconnected');
    _connectedDevice = null;
    _service = null;
    _writeCharacteristic = null;
    _notifyCharacteristic = null;
    _notificationSub?.cancel();
    _notificationSub = null;
    _commandQueue.clear();
    _isWriting = false;
    _connectionStateController?.add(DeviceConnectionState.disconnected);
  }

  Future<void> _discoverServices() async {
    AppLog.info('StarLightBleAdapter: discovering GATT services');
    final device = _connectedDevice;
    if (device == null) {
      AppLog.error('StarLightBleAdapter: no connected device');
      throw DisconnectedException();
    }

    final services = await device.discoverServices();
    AppLog.debug(
      'StarLightBleAdapter: found ${services.length} service(s)',
    );

    BluetoothService? targetService;
    for (final s in services) {
      AppLog.debug('StarLightBleAdapter: service ${s.uuid} (${s.uuid.str128})');
      if (UuidUtils.matches(s.uuid.str128, BleConstants.serviceUuid)) {
        targetService = s;
        break;
      }
    }

    if (targetService == null) {
      AppLog.error(
        'StarLightBleAdapter: service ${BleConstants.serviceUuid} not found',
      );
      throw ServiceNotFoundException(BleConstants.serviceUuid);
    }
    AppLog.info('StarLightBleAdapter: found service ${targetService.uuid}');

    _service = targetService;

    for (final c in targetService.characteristics) {
      AppLog.debug('StarLightBleAdapter: characteristic ${c.uuid} (${c.uuid.str128})');
      if (UuidUtils.matches(c.uuid.str128, BleConstants.writeCharUuid)) {
        _writeCharacteristic = c;
        AppLog.info('StarLightBleAdapter: write characteristic ${c.uuid} found');
      } else if (UuidUtils.matches(c.uuid.str128, BleConstants.notifyCharUuid)) {
        _notifyCharacteristic = c;
        AppLog.info('StarLightBleAdapter: notify characteristic ${c.uuid} found');
      }
    }

    if (_writeCharacteristic == null) {
      AppLog.error(
        'StarLightBleAdapter: write characteristic '
        '${BleConstants.writeCharUuid} not found',
      );
      throw CharacteristicNotFoundException(BleConstants.writeCharUuid);
    }

    await _subscribeToNotifications();
  }

  Future<void> _subscribeToNotifications() async {
    final notifyChar = _notifyCharacteristic;
    if (notifyChar == null) {
      AppLog.warn('StarLightBleAdapter: no notify characteristic, skipping');
      return;
    }
    AppLog.info('StarLightBleAdapter: enabling notifications on $notifyChar');

    await notifyChar.setNotifyValue(true);

    // Also write CCC descriptor for completeness (as the APK does)
    for (final descriptor in notifyChar.descriptors) {
      AppLog.debug('StarLightBleAdapter: descriptor ${descriptor.descriptorUuid}');
      if (UuidUtils.matches(
        descriptor.descriptorUuid.str128,
        BleConstants.cccDescriptorUuid,
      )) {
        try {
          await descriptor.write(Uint8List.fromList([0x01, 0x00]));
          AppLog.debug('StarLightBleAdapter: CCC descriptor written');
        } catch (e) {
          AppLog.warn('StarLightBleAdapter: CCC write failed: $e');
        }
      }
    }

    _notificationSub?.cancel();
    _notificationSub = notifyChar.onValueReceived.listen((data) {
      AppLog.debug(
        'StarLightBleAdapter: notification received: ${HexUtils.toHexString(data)}',
      );
      if (_notificationController != null &&
          !_notificationController!.isClosed) {
        _notificationController!.add(Uint8List.fromList(data));
      }
    });
    AppLog.info('StarLightBleAdapter: notifications active');
  }

  @override
  Future<void> disconnect(Device device) async {
    AppLog.info('StarLightBleAdapter: disconnecting from ${device.id}');
    _isConnecting = false;
    _isWriting = false;
    _commandQueue.clear();

    await _deviceStateSub?.cancel();
    _deviceStateSub = null;
    await _notificationSub?.cancel();
    _notificationSub = null;

    final bleDevice = _connectedDevice;
    if (bleDevice != null) {
      try {
        await bleDevice.disconnect();
        AppLog.info('StarLightBleAdapter: device disconnected');
      } catch (e) {
        AppLog.warn('StarLightBleAdapter: device.disconnect() threw (ignored): $e');
      }
    }

    _connectedDevice = null;
    _service = null;
    _writeCharacteristic = null;
    _notifyCharacteristic = null;

    await _connectionStateController?.close();
    _connectionStateController = null;
    await _notificationController?.close();
    _notificationController = null;
  }

  @override
  Future<void> sendCommand(Device device, DeviceCommand command) async {
    Uint8List? packet;

    switch (command.type) {
      case 'power':
        final on = command.parameters['on'] as bool;
        packet = on ? ProtocolEncoder.powerOn() : ProtocolEncoder.powerOff();
        break;
      case 'brightness':
        final value = command.parameters['value'] as int;
        packet = ProtocolEncoder.brightness(value);
        break;
      case 'color':
        final red = command.parameters['red'] as int;
        final green = command.parameters['green'] as int;
        final blue = command.parameters['blue'] as int;
        packet = ProtocolEncoder.colorFromRGB(red, green, blue);
        break;
      case 'speed':
        final value = command.parameters['value'] as int;
        packet = ProtocolEncoder.setSpeed(value);
        break;
      case 'effect':
        final name = command.parameters['name'] as String;
        final modeId = _effectNameToModeId(name);
        if (modeId != null) {
          packet = ProtocolEncoder.setMode(modeId);
        }
        break;
      default:
        throw UnsupportedError('Command type ${command.type} not supported by StarLight');
    }

    if (packet != null) {
      await _writeCommand(packet);
    }
  }

  int? _effectNameToModeId(String name) {
    // Mode mapping from APK strings.xml (cmode1..cmode117)
    // These are NOT verified - only use if explicitly requested for testing
    final Map<String, int> knownEffects = {
      'solid': 1,
      'rainbow': 2,
      'breathing': 3,
      'strobe': 4,
      'wave': 5,
    };
    return knownEffects[name.toLowerCase()];
  }

  @override
  Future<DeviceState> readState(Device device) async {
    // StarLight doesn't support state readback via notifications
    // Return the last known state
    return device.state;
  }

  @override
  bool canHandle(Device device) {
    return device.type == DeviceType.light &&
           device.transport == 'ble' &&
           (device.manufacturer == 'MR Star' || device.metadata['isMrStar'] == true);
  }

  // --- BLE Write Queue ---

  Future<void> _writeCommand(Uint8List bytes) async {
    AppLog.debug('StarLightBleAdapter: writeCommand ${HexUtils.toHexString(bytes)}');
    final writeChar = _writeCharacteristic;
    final device = _connectedDevice;
    if (writeChar == null) {
      AppLog.error('StarLightBleAdapter: write characteristic not initialized');
      throw CharacteristicNotFoundException(BleConstants.writeCharUuid);
    }
    if (device == null) {
      AppLog.error('StarLightBleAdapter: no connected device');
      throw DisconnectedException();
    }

    final completer = Completer<void>();

    _commandQueue.add(() async {
      try {
        await writeChar.write(bytes, withoutResponse: true);
        AppLog.debug('StarLightBleAdapter: written ${HexUtils.toHexString(bytes)}');
        if (!completer.isCompleted) {
          completer.complete();
        }
      } catch (e) {
        AppLog.error('StarLightBleAdapter: write failed', e);
        if (!completer.isCompleted) {
          completer.completeError(e);
        }
      }
    });

    _processQueue();

    return completer.future;
  }

  void _processQueue() {
    if (_isWriting || _commandQueue.isEmpty) return;
    _isWriting = true;
    _runNext();
  }

  void _runNext() async {
    AppLog.debug('StarLightBleAdapter: processing queue (${_commandQueue.length} pending)');
    while (_commandQueue.isNotEmpty) {
      final task = _commandQueue.removeAt(0);
      try {
        await task();
      } catch (e) {
        AppLog.debug('StarLightBleAdapter: task failed (handled upstream): $e');
      }
      await Future.delayed(const Duration(milliseconds: 5));
    }
    _isWriting = false;
  }

  void _handleError(Exception e) {
    AppLog.error('StarLightBleAdapter: BLE error: $e');
    if (_connectionStateController != null &&
        !_connectionStateController!.isClosed) {
      _connectionStateController!.addError(e);
    }
  }
}

// --- Exception classes (moved from ble_datasource.dart for adapter use) ---

class DisconnectedException implements Exception {}
class ConnectionTimeoutException implements Exception {}
class ServiceNotFoundException implements Exception {
  final String serviceUuid;
  ServiceNotFoundException(this.serviceUuid);
}
class CharacteristicNotFoundException implements Exception {
  final String charUuid;
  CharacteristicNotFoundException(this.charUuid);
}