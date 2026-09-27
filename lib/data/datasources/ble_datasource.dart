import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/ble/ble_constants.dart';
import '../../core/errors/exceptions.dart';
import '../../core/utils/app_logger.dart';
import '../../core/utils/hex_utils.dart';
import '../../core/utils/uuid_utils.dart';
import '../models/ble_device_model.dart';

/// BLE data source using [FlutterBluePlus].
///
/// GATT structure from the decompiled APK (MyApplication.java lines 202-231):
/// - Service FFF0: 0000FFF0-0000-1000-8000-00805f9b34fb
/// - Write Char FFF3: 0000FFF3-0000-1000-8000-00805f9b34fb (WRITE | WRITE_WITHOUT_RESPONSE)
/// - Notify Char FFF4: 0000FFF4-0000-1000-8000-00805f9b34fb (NOTIFY)
class BleDataSource {
  BluetoothDevice? _connectedDevice;
  BluetoothService? _service;
  BluetoothCharacteristic? _writeCharacteristic;
  BluetoothCharacteristic? _notifyCharacteristic;

  StreamController<List<BleDeviceModel>>? _scanController;
  StreamController<BluetoothConnectionState>? _connectionStateController;
  StreamController<Uint8List>? _notificationController;
  StreamSubscription<BluetoothConnectionState>? _deviceStateSub;
  StreamSubscription<List<int>>? _notificationSub;

  bool _isConnecting = false;

  // --- Permissions ---

  /// Requests BLE permissions for Android 12+.
  /// For Android < 12, requests location permission.
  Future<bool> requestPermissions() async {
    if (!Platform.isAndroid) {
      AppLog.debug('requestPermissions: not Android, granting by default');
      return true;
    }

    AppLog.info('requestPermissions: requesting Bluetooth/location access');
    final statuses = await Future.wait([
      Permission.bluetoothScan.request(),
      Permission.bluetoothConnect.request(),
      Permission.locationWhenInUse.request(),
    ]);
    for (final status in statuses) {
      if (status == PermissionStatus.permanentlyDenied) {
        AppLog.error('requestPermissions: permanently denied ($status)');
        return false;
      }
    }
    AppLog.info('requestPermissions: granted ($statuses)');
    return true;
  }

  Future<bool> hasPermissions() async {
    if (!Platform.isAndroid) {
      AppLog.debug('hasPermissions: not Android, returning true');
      return true;
    }
    final granted = await Permission.bluetoothScan.isGranted ||
        await Permission.bluetoothConnect.isGranted ||
        await Permission.locationWhenInUse.isGranted;
    AppLog.debug('hasPermissions: $granted');
    return granted;
  }

  // --- Bluetooth state ---

  Future<bool> isBluetoothEnabled() async {
    final state = await FlutterBluePlus.adapterState.first;
    AppLog.debug('isBluetoothEnabled: adapterState=$state');
    return state == BluetoothAdapterState.on;
  }

  Future<void> enableBluetooth() async {
    AppLog.info('enableBluetooth: turning adapter on');
    await FlutterBluePlus.turnOn();
  }

  // --- Scanning ---

  final Map<String, BleDeviceModel> _knownDevices = {};

  Stream<List<BleDeviceModel>> scanDevices() {
    AppLog.info('scanDevices: starting scan session');
    if (_scanController == null || _scanController!.isClosed) {
      _scanController = StreamController<List<BleDeviceModel>>.broadcast();
    }

    _watchScanResults();

    // Start the actual scan
    _startBleScan();

    return _scanController!.stream;
  }

  StreamSubscription? _currentScanSubscription;

  void _watchScanResults() {
    _currentScanSubscription?.cancel();
    AppLog.debug('_watchScanResults: subscribing to FlutterBluePlus.scanResults');

    _currentScanSubscription = FlutterBluePlus.scanResults.listen((results) {
      if (_scanController == null || _scanController!.isClosed) return;
      for (final result in results) {
        final model = BleDeviceModel(
          id: result.device.remoteId.str,
          name: result.device.platformName.isNotEmpty
              ? result.device.platformName
              : (result.advertisementData.serviceData.isNotEmpty
                  ? result.advertisementData.serviceData.values.first.toString()
                  : 'GATT--DEMO'),
          rssi: result.rssi,
          isDemoDevice: BleDeviceModel.isMrStarDevice(
            result.device.platformName,
          ),
        );
        AppLog.debug(
          'scan result: ${model.name} (${model.id}) rssi=${model.rssi} dBm '
          'demo=${model.isDemoDevice}',
        );
        if (model.id != '' && model.id != '00:00:00:00:00:00') {
          _knownDevices[model.id] = model;
        }
      }
      _scanController?.add(_knownDevices.values.toList());
    }, onError: (e) {
      AppLog.error('scanResults stream error', e);
      if (_scanController != null && !_scanController!.isClosed) {
        _scanController!.addError(e);
      }
    });

    // Devices that are already known to the OS (e.g. connected via the system
    // Bluetooth) never fire the discovery event, so merge them in explicitly.
    // Otherwise an already-connected device would never appear in the list.
    _loadSystemDevices();
  }

  Future<void> _loadSystemDevices() async {
    AppLog.debug('_loadSystemDevices: fetching OS-known devices');
    try {
      final systemDevices = await FlutterBluePlus.systemDevices(const []);
      AppLog.info('_loadSystemDevices: found ${systemDevices.length} known device(s)');
      for (final device in systemDevices) {
        final id = device.remoteId.str;
        if (id == '' || id == '00:00:00:00:00:00') continue;
        AppLog.debug('_loadSystemDevices: ${device.platformName} ($id)');
        _knownDevices[id] ??= BleDeviceModel(
          id: id,
          name: device.platformName.isNotEmpty
              ? device.platformName
              : 'Unknown device',
          rssi: 0,
          isConnected: _connectedDevice?.remoteId.str == id,
        );
      }
    } catch (e) {
      // Some platforms restrict listing system devices; ignore.
      AppLog.warn('_loadSystemDevices: could not list system devices: $e');
    }
    if (_scanController != null && !_scanController!.isClosed) {
      _scanController!.add(_knownDevices.values.toList());
    }
  }

  Future<void> _startBleScan() async {
    AppLog.info('_startBleScan: starting BLE scan (timeout=10s)');
    try {
      // The original APK scans for all BLE devices without name/UUID filters.
      // We mark GATT--DEMO devices in the UI.
      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 10),
        androidScanMode: AndroidScanMode.lowPower,
        continuousUpdates: true,
      );
      AppLog.info('_startBleScan: scan started');
    } catch (e) {
      AppLog.error('_startBleScan: failed to start scan', e);
      if (_scanController != null && !_scanController!.isClosed) {
        _scanController!.addError(e);
      }
    }
  }

  Future<void> stopScan() async {
    AppLog.info('stopScan: stopping BLE scan');
    _currentScanSubscription?.cancel();
    _currentScanSubscription = null;
    try {
      await FlutterBluePlus.stopScan();
    } catch (e) {
      AppLog.warn('stopScan: stopScan threw (ignored): $e');
    }
    if (_scanController != null && !_scanController!.isClosed) {
      _scanController!.add([]);
    }
  }

  // --- Connection ---

  Stream<BluetoothConnectionState> connectToDevice(String deviceId) {
    AppLog.info('connectToDevice: connecting to $deviceId');
    if (_isConnecting) {
      AppLog.warn('connectToDevice: already connecting, returning existing stream');
      return _connectionStateController?.stream ??
          Stream.value(BluetoothConnectionState.disconnected);
    }
    _isConnecting = true;
    _connectionStateController =
        StreamController<BluetoothConnectionState>.broadcast();

    _connectToAddress(deviceId);

    return _connectionStateController!.stream;
  }

  Future<void> _connectToAddress(String deviceId) async {
    AppLog.info('_connectToAddress: $deviceId (autoConnect=false, timeout=15s)');
    try {
      _connectedDevice = BluetoothDevice.fromId(deviceId);

      await _connectedDevice!.connect(
        autoConnect: false,
        timeout: const Duration(seconds: 15),
      );
      AppLog.info('_connectToAddress: connect() returned for $deviceId');

      _setupDeviceStateListener();

      await _waitForConnectedOrTimeout();

      await _discoverServices();
    } on Exception catch (e) {
      AppLog.error('_connectToAddress: connection flow failed', e);
      _handleError(e);
      _isConnecting = false;
    }
  }

  void _setupDeviceStateListener() {
    AppLog.debug('_setupDeviceStateListener: listening to connection state');
    _deviceStateSub?.cancel();
    _deviceStateSub = _connectedDevice!.connectionState.listen((state) {
      AppLog.debug('connection state changed: $state');
      if (_connectionStateController != null &&
          !_connectionStateController!.isClosed) {
        _connectionStateController!.add(state);
      }

      if (state == BluetoothConnectionState.disconnected) {
        _handleDisconnect();
      }
    });
  }

  Future<void> _waitForConnectedOrTimeout() async {
    if (_connectedDevice == null) {
      AppLog.error('_waitForConnectedOrTimeout: no connected device');
      throw DisconnectedException();
    }
    try {
      await _connectedDevice!.connectionState
          .firstWhere(
            (s) => s == BluetoothConnectionState.connected,
            orElse: () => throw DisconnectedException(),
          )
          .timeout(const Duration(seconds: 15));
      AppLog.info('_waitForConnectedOrTimeout: device is connected');
    } on TimeoutException {
      AppLog.error(
        '_waitForConnectedOrTimeout: timed out waiting for connection',
      );
      throw ConnectionTimeoutException();
    }
    _isConnecting = false;
  }

  void _handleDisconnect() {
    AppLog.warn('_handleDisconnect: device disconnected');
    _connectedDevice = null;
    _service = null;
    _writeCharacteristic = null;
    _notifyCharacteristic = null;
    _notificationSub?.cancel();
    _notificationSub = null;
    _commandQueue.clear();
    _isWriting = false;
  }

  // --- Service Discovery ---

  Future<void> _discoverServices() async {
    AppLog.info('_discoverServices: discovering GATT services');
    final device = _connectedDevice;
    if (device == null) {
      AppLog.error('_discoverServices: no connected device');
      throw DisconnectedException();
    }

    final services = await device.discoverServices();
    AppLog.debug(
      '_discoverServices: found ${services.length} service(s)',
    );

    BluetoothService? targetService;
    for (final s in services) {
      // flutter_blue_plus reports 16-bit Bluetooth UUIDs in their short form
      // ("fff0"), so compare the expanded 128-bit representations.
      AppLog.debug('_discoverServices: service ${s.uuid} (${s.uuid.str128})');
      if (UuidUtils.matches(s.uuid.str128, BleConstants.serviceUuid)) {
        targetService = s;
        break;
      }
    }

    if (targetService == null) {
      AppLog.error(
        '_discoverServices: service ${BleConstants.serviceUuid} not found',
      );
      throw ServiceNotFoundException(BleConstants.serviceUuid);
    }
    AppLog.info('_discoverServices: found service ${targetService.uuid}');

    _service = targetService;

    for (final c in targetService.characteristics) {
      AppLog.debug('_discoverServices: characteristic ${c.uuid} (${c.uuid.str128})');
      if (UuidUtils.matches(c.uuid.str128, BleConstants.writeCharUuid)) {
        _writeCharacteristic = c;
        AppLog.info('_discoverServices: write characteristic ${c.uuid} found');
      } else if (UuidUtils.matches(c.uuid.str128, BleConstants.notifyCharUuid)) {
        _notifyCharacteristic = c;
        AppLog.info('_discoverServices: notify characteristic ${c.uuid} found');
      }
    }

    if (_writeCharacteristic == null) {
      AppLog.error(
        '_discoverServices: write characteristic '
        '${BleConstants.writeCharUuid} not found',
      );
      throw CharacteristicNotFoundException(BleConstants.writeCharUuid);
    }

    await _subscribeToNotifications();
  }

  // --- Notifications ---

  Future<void> _subscribeToNotifications() async {
    final notifyChar = _notifyCharacteristic;
    if (notifyChar == null) {
      AppLog.warn('_subscribeToNotifications: no notify characteristic, skipping');
      return;
    }
    AppLog.info('_subscribeToNotifications: enabling notifications on $notifyChar');

    await notifyChar.setNotifyValue(true);

    // Also write CCC descriptor for completeness (as the APK does)
    for (final descriptor in notifyChar.descriptors) {
      AppLog.debug('_subscribeToNotifications: descriptor ${descriptor.descriptorUuid}');
      if (UuidUtils.matches(
        descriptor.descriptorUuid.str128,
        BleConstants.cccDescriptorUuid,
      )) {
        try {
          await descriptor.write(Uint8List.fromList([0x01, 0x00]));
          AppLog.debug('_subscribeToNotifications: CCC descriptor written');
        } catch (e) {
          // Some devices handle this automatically via setNotifyValue
          AppLog.warn('_subscribeToNotifications: CCC write failed: $e');
        }
      }
    }

    _notificationSub?.cancel();
    _notificationSub = notifyChar.onValueReceived.listen((data) {
      AppLog.debug(
        'notification received: ${HexUtils.toHexString(data)}',
      );
      if (_notificationController != null &&
          !_notificationController!.isClosed) {
        _notificationController!.add(Uint8List.fromList(data));
      }
    });
    AppLog.info('_subscribeToNotifications: notifications active');
  }

  Stream<Uint8List> get notificationStream {
    AppLog.debug('notificationStream: creating notification stream');
    _notificationController ??= StreamController<Uint8List>.broadcast();
    return _notificationController!.stream;
  }

  // --- Writing ---

  /// Serializes BLE writes to avoid concurrent writeWithoutResponse calls.
  /// The original APK serializes writes via its internal BLE library.
  final List<Future<void> Function()> _commandQueue = [];
  bool _isWriting = false;

  /// Writes a command to the FFF3 write characteristic.
  /// Commands are serialized to prevent concurrent writes.
  Future<void> writeCommand(Uint8List bytes) async {
    AppLog.debug(
      'writeCommand: ${HexUtils.toHexString(bytes)}',
    );
    final writeChar = _writeCharacteristic;
    final device = _connectedDevice;
    if (writeChar == null) {
      AppLog.error('writeCommand: write characteristic not initialized');
      throw CharacteristicNotFoundException(BleConstants.writeCharUuid);
    }
    if (device == null) {
      AppLog.error('writeCommand: no connected device');
      throw DisconnectedException();
    }

    final completer = Completer<void>();

    _commandQueue.add(() async {
      try {
        await writeChar.write(bytes, withoutResponse: true);
        AppLog.debug(
          'writeCommand: written ${HexUtils.toHexString(bytes)}',
        );
        if (!completer.isCompleted) {
          completer.complete();
        }
      } catch (e) {
        AppLog.error('writeCommand: write failed', e);
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
    AppLog.debug('_runNext: processing command queue (${_commandQueue.length} pending)');
    while (_commandQueue.isNotEmpty) {
      final task = _commandQueue.removeAt(0);
      try {
        await task();
      } catch (e) {
        // Error is already handled by the completer inside the task
        AppLog.debug('_runNext: task failed (handled upstream): $e');
      }
      // Small delay between writes to avoid overwhelming BLE stack
      await Future.delayed(const Duration(milliseconds: 5));
    }
    _isWriting = false;
  }

  // --- RSSI ---

  Future<int?> readRssi() async {
    final device = _connectedDevice;
    if (device == null) {
      AppLog.debug('readRssi: no connected device');
      return null;
    }
    try {
      final rssi = await device.readRssi();
      AppLog.debug('readRssi: $rssi dBm');
      return rssi;
    } catch (e) {
      AppLog.warn('readRssi: failed: $e');
      return null;
    }
  }

  // --- Disconnect ---

  Future<void> disconnect() async {
    AppLog.info('disconnect: tearing down BLE session');
    _isConnecting = false;
    _isWriting = false;
    _commandQueue.clear();

    await _deviceStateSub?.cancel();
    _deviceStateSub = null;
    await _notificationSub?.cancel();
    _notificationSub = null;
    await _currentScanSubscription?.cancel();
    _currentScanSubscription = null;
    _knownDevices.clear();

    final device = _connectedDevice;
    if (device != null) {
      try {
        await device.disconnect();
        AppLog.info('disconnect: device disconnected');
      } catch (e) {
        // ignore
        AppLog.warn('disconnect: device.disconnect() threw (ignored): $e');
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
    _scanController = null;
    AppLog.info('disconnect: session torn down');
  }

  void _handleError(Exception e) {
    AppLog.error('BLE error: $e');
    if (_connectionStateController != null &&
        !_connectionStateController!.isClosed) {
      _connectionStateController!.addError(e);
    }
  }

  // --- Getters ---

  BluetoothDevice? get device => _connectedDevice;
  BluetoothService? get service => _service;
  BluetoothCharacteristic? get writeCharacteristic => _writeCharacteristic;
  BluetoothCharacteristic? get notifyCharacteristic => _notifyCharacteristic;

  bool get isConnected => _connectedDevice?.isConnected ?? false;

  Stream<BluetoothConnectionState>? get connectionState =>
      _connectionStateController?.stream;
}
