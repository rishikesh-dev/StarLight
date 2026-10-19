// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../../core/ble/ble_constants.dart';
import '../../core/ble/ble_permission_gateway.dart';
import '../../core/ble/ble_platform.dart';
import '../../core/ble/device_name.dart';
import '../../core/ble/flutter_ble_platform.dart';
import '../../core/ble/protocol_decoder.dart';
import '../../core/errors/exceptions.dart';
import '../../core/utils/app_logger.dart';
import '../../core/utils/hex_utils.dart';
import '../../core/utils/uuid_utils.dart';
import '../models/ble_device_model.dart';
import '../../domain/entities/device_state_update.dart';

/// BLE data source using [FlutterBluePlus].
///
/// GATT structure from the decompiled APK (MyApplication.java lines 202-231):
/// - Service FFF0: 0000FFF0-0000-1000-8000-00805f9b34fb
/// - Write Char FFF3: 0000FFF3-0000-1000-8000-00805f9b34fb (WRITE | WRITE_WITHOUT_RESPONSE)
/// - Notify Char FFF4: 0000FFF4-0000-1000-8000-00805f9b34fb (NOTIFY)
class BleDataSource {
  final BlePlatform _platform;

  /// Narrow seam used only to create the platform device handle; defaults to
  /// the real [BluetoothDevice.fromId]. Tests inject a fake to exercise the
  /// transport logic without hardware. The transport itself is unchanged.
  final BluetoothDevice Function(String deviceId) _deviceFactory;

  /// Narrow seam over the runtime-permission flow; defaults to the real
  /// `permission_handler`-backed gateway. Tests inject a fake to assert how
  /// permissions are requested without triggering system dialogs.
  final BlePermissionGateway _permissions;

  BleDataSource({
    BlePlatform? platform,
    BluetoothDevice Function(String)? deviceFactory,
    BlePermissionGateway? permissions,
  }) : _platform = platform ?? const FlutterBlePlatform(),
       _deviceFactory = deviceFactory ?? BluetoothDevice.fromId,
       _permissions =
           permissions ?? const PermissionHandlerBlePermissionGateway();

  BluetoothDevice? _connectedDevice;

  BluetoothService? _service;
  BluetoothCharacteristic? _writeCharacteristic;
  BluetoothCharacteristic? _notifyCharacteristic;

  /// Every service discovered on the current connection, in the order the
  /// platform reported them. Used by custom device profiles to resolve their
  /// own service/characteristic UUIDs through this single transport owner.
  List<BluetoothService> _discoveredServices = const [];

  StreamController<List<BleDeviceModel>>? _scanController;

  // Connection and notification streams live for the whole application session
  // so subscribers (BleBloc, LightBloc, DeviceRepository) can register before
  // any connect happens and keep their subscription across reconnects.
  final StreamController<BluetoothConnectionState> _connectionStateController =
      StreamController<BluetoothConnectionState>.broadcast();
  final StreamController<Uint8List> _notificationController =
      StreamController<Uint8List>.broadcast();

  StreamSubscription<BluetoothConnectionState>? _deviceStateSub;
  StreamSubscription<List<int>>? _notificationSub;
  int _scanSessionId = 0;

  /// True once notifications are confirmed enabled for the current session.
  /// When false but connected, the session is command-only: writes are
  /// expected to work but device state is not synchronized back to the app.
  bool _notificationsReady = false;

  // State update stream for decoded notifications
  final StreamController<DeviceStateUpdate> _stateUpdateController =
      StreamController<DeviceStateUpdate>.broadcast();

  bool _isConnecting = false;

  // --- Permissions ---

  /// Requests the BLE permissions required to scan and connect.
  ///
  /// Delegates to a single, platform-agnostic gateway call: the request is
  /// issued as one batched platform invocation, never as concurrent requests.
  /// Returns whether the required permissions are granted afterwards.
  Future<bool> requestPermissions() {
    AppLog.info('requestPermissions: requesting Bluetooth access');
    return _permissions.requestRequiredPermissions();
  }

  Future<bool> hasPermissions() async {
    final granted = await _permissions.hasRequiredPermissions();
    AppLog.debug('hasPermissions: $granted');
    return granted;
  }

  /// Whether any required permission is permanently denied (the system will no
  /// longer show a request dialog; the user must change it in app settings).
  Future<bool> isPermanentlyDenied() async {
    final denied = await _permissions.isPermanentlyDenied();
    AppLog.debug('isPermanentlyDenied: $denied');
    return denied;
  }

  /// Opens the system app settings so the user can grant a permanently denied
  /// permission manually.
  Future<void> openSystemSettings() async {
    AppLog.info('openSystemSettings: opening system app settings');
    await _permissions.openSystemSettings();
  }

  // --- Bluetooth state ---

  Stream<BluetoothAdapterState> get adapterState => _platform.adapterState;

  /// Synchronous snapshot of the current adapter state.
  BluetoothAdapterState get adapterStateNow => _platform.adapterStateNow;

  // Fast synchronous check using the cached adapter state. On Linux this avoids
  // the initialization race where the first stream emission may be stale.
  bool get isAdapterOn => _platform.adapterStateNow == BluetoothAdapterState.on;

  Future<bool> isBluetoothEnabled() async {
    final state = await _platform.adapterState.first;
    AppLog.debug('isBluetoothEnabled: adapterState=$state');
    return state == BluetoothAdapterState.on;
  }

  /// Waits for the adapter to reach [BluetoothAdapterState.on], handling the
  /// Linux/BlueZ initialization race where the adapter may briefly report a
  /// non-`on` state before settling. Returns `false` if the adapter turns off
  /// or does not become `on` within [timeout].
  Future<bool> waitForAdapterOn({
    Duration timeout = const Duration(seconds: 15),
  }) async {
    if (isAdapterOn) {
      AppLog.debug('waitForAdapterOn: adapter already on');
      return true;
    }
    AppLog.info(
      'waitForAdapterOn: waiting for adapter (timeout=${timeout.inSeconds}s)',
    );
    try {
      await _platform.adapterState
          .where((s) => s == BluetoothAdapterState.on)
          .first
          .timeout(timeout);
      AppLog.info('waitForAdapterOn: adapter is now on');
      return true;
    } on TimeoutException {
      final state = _platform.adapterStateNow;
      AppLog.warn('waitForAdapterOn: timed out, adapter state=$state');
      return false;
    } catch (e) {
      AppLog.warn('waitForAdapterOn: error waiting for adapter: $e');
      return false;
    }
  }

  /// Whether the platform/hardware supports Bluetooth.
  Future<bool> isSupported() async {
    try {
      final supported = await _platform.isSupported;
      AppLog.info('isSupported: $supported');
      return supported;
    } catch (e) {
      AppLog.warn('isSupported: check failed: $e');
      return true;
    }
  }

  /// Whether an enable request is already in flight, to avoid opening the
  /// Android system dialogs more than once.
  bool _enableRequestInFlight = false;

  /// Result of an explicit adapter-enable request.
  ///
  /// Returns `true` when the adapter is confirmed `on`. Returns `false` when
  /// the user declined, the platform does not support turning Bluetooth on, or
  /// the adapter did not reach `on`. Never claims success without the
  /// confirmed adapter state.
  Future<bool> enableBluetooth() async {
    if (_enableRequestInFlight) {
      AppLog.info('enableBluetooth: request already in flight, ignoring');
      return isAdapterOn;
    }
    if (isAdapterOn) {
      AppLog.info('enableBluetooth: adapter already on');
      return true;
    }
    _enableRequestInFlight = true;
    try {
      AppLog.info('enableBluetooth: requesting adapter on');
      await _platform.turnOn();
      // turnOn() only returns once the adapter is on, but confirm explicitly.
      final on = await waitForAdapterOn(timeout: const Duration(seconds: 10));
      AppLog.info('enableBluetooth: adapter on=$on');
      return on;
    } catch (e) {
      // User declined, or the platform cannot turn Bluetooth on (e.g. Linux).
      AppLog.warn('enableBluetooth: request failed or declined: $e');
      return false;
    } finally {
      _enableRequestInFlight = false;
    }
  }

  // --- Scanning ---

  final Map<String, BleDeviceModel> _knownDevices = {};

  Stream<List<BleDeviceModel>> scanDevices() {
    _scanSessionId++;
    AppLog.info('scanDevices: starting scan session [scan#$_scanSessionId]');
    _knownDevices.clear();

    // Cancel any in-progress scan before starting a new one (idempotent).
    _currentScanSubscription?.cancel();
    _currentScanSubscription = null;
    if (_scanController == null || _scanController!.isClosed) {
      _scanController = StreamController<List<BleDeviceModel>>.broadcast();
    } else {
      _scanController!.add([]);
    }

    _watchScanResults(_scanSessionId);

    // Start the actual scan for this session only.
    _startBleScan(_scanSessionId);

    return _scanController!.stream;
  }

  StreamSubscription? _currentScanSubscription;

  void _watchScanResults(int sessionId) {
    _currentScanSubscription?.cancel();
    AppLog.debug(
      '_watchScanResults: subscribing to FlutterBluePlus.scanResults '
      '[scan#$sessionId]',
    );

    _currentScanSubscription = _platform.scanResults.listen(
      (results) {
        if (!_isScanSessionCurrent(sessionId)) return;
        if (_scanController == null || _scanController!.isClosed) return;
        for (final result in results) {
          final model = BleDeviceModel(
            id: result.device.remoteId.str,
            name: resolveDeviceDisplayName(
              platformName: result.device.platformName,
              advName: result.advertisementData.advName,
              serviceData: result.advertisementData.serviceData.values.isEmpty
                  ? null
                  : result.advertisementData.serviceData.values.first,
            ),
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
      },
      onError: (e) {
        AppLog.error('scanResults stream error', e);
        _emitScanError(e, sessionId);
      },
    );

    // Devices that are already known to the OS (e.g. connected via the system
    // Bluetooth) never fire the discovery event, so merge them in explicitly.
    // Otherwise an already-connected device would never appear in the list.
    _loadSystemDevices(sessionId);
  }

  Future<void> _loadSystemDevices(int sessionId) async {
    AppLog.debug('_loadSystemDevices: fetching OS-known devices');
    try {
      final systemDevices = await FlutterBluePlus.systemDevices(const []);
      AppLog.info(
        '_loadSystemDevices: found ${systemDevices.length} known device(s)',
      );
      if (!_isScanSessionCurrent(sessionId)) return;
      for (final device in systemDevices) {
        final id = device.remoteId.str;
        if (id == '' || id == '00:00:00:00:00:00') continue;
        AppLog.debug('_loadSystemDevices: ${device.platformName} ($id)');
        _knownDevices[id] ??= BleDeviceModel(
          id: id,
          name: resolveDeviceDisplayName(platformName: device.platformName),
          rssi: 0,
          isConnected: _connectedDevice?.remoteId.str == id,
        );
      }
    } catch (e) {
      // Some platforms restrict listing system devices; ignore.
      AppLog.warn('_loadSystemDevices: could not list system devices: $e');
    }
    if (!_isScanSessionCurrent(sessionId)) return;
    if (_scanController != null && !_scanController!.isClosed) {
      _scanController!.add(_knownDevices.values.toList());
    }
  }

  Future<void> _startBleScan(int sessionId) async {
    AppLog.info(
      '_startBleScan: starting BLE scan (timeout=10s) [scan#$sessionId]',
    );

    // Wait for a confirmed adapter-on state before scanning. This handles
    // the Linux/BlueZ initialization race where the adapter may briefly
    // report a non-'on' state even though BlueZ is powered.
    final isOn = await waitForAdapterOn();
    if (!_isScanSessionCurrent(sessionId)) {
      AppLog.info(
        '_startBleScan: scan session #$sessionId superseded before start',
      );
      return;
    }
    if (!isOn) {
      final error = Exception('Bluetooth adapter is not enabled');
      AppLog.error('_startBleScan: adapter not on, cannot scan', error);
      _emitScanError(error, sessionId);
      return;
    }

    try {
      await _platform.startScan(
        timeout: const Duration(seconds: 10),
        androidScanMode: AndroidScanMode.lowPower,
        continuousUpdates: true,
      );
      AppLog.info('_startBleScan: scan started [scan#$sessionId]');
    } catch (e) {
      // On Linux/BlueZ, startScan can throw org.bluez.Error.NotReady when the
      // adapter transitions to on but is not yet fully ready for discovery.
      // Wait once more for the adapter and retry. If it still fails, the
      // error propagates so the caller can stop retrying while the adapter
      // is genuinely off.
      if (_isAdapterNotReadyError(e)) {
        AppLog.warn(
          '_startBleScan: NotReady error, retrying after adapter wait',
        );
        final retryReady = await waitForAdapterOn();
        if (!_isScanSessionCurrent(sessionId)) {
          AppLog.info(
            '_startBleScan: scan session #$sessionId superseded before retry',
          );
          return;
        }
        if (retryReady) {
          try {
            await _platform.startScan(
              timeout: const Duration(seconds: 10),
              androidScanMode: AndroidScanMode.lowPower,
              continuousUpdates: true,
            );
            AppLog.info(
              '_startBleScan: scan started (retry) [scan#$sessionId]',
            );
            return;
          } catch (e2) {
            AppLog.error('_startBleScan: retry failed', e2);
            _emitScanError(e2, sessionId);
            return;
          }
        }
        AppLog.error('_startBleScan: adapter not ready after retry', e);
        _emitScanError(e, sessionId);
        return;
      }
      AppLog.error('_startBleScan: failed to start scan', e);
      _emitScanError(e, sessionId);
    }
  }

  /// True when [sessionId] still identifies the active scan session.
  /// A superseded (stale) session must not start another platform scan or
  /// publish errors into the current session's stream.
  bool _isScanSessionCurrent(int sessionId) => sessionId == _scanSessionId;

  bool _isAdapterNotReadyError(Object e) {
    final msg = e.toString().toLowerCase();
    return msg.contains('notready') ||
        msg.contains('not ready') ||
        msg.contains('adapterisoff') ||
        msg.contains('bluetooth adapter is off');
  }

  void _emitScanError(Object e, int sessionId) {
    if (!_isScanSessionCurrent(sessionId)) {
      AppLog.warn('_emitScanError: dropping stale scan#$sessionId error: $e');
      return;
    }
    if (_scanController != null && !_scanController!.isClosed) {
      _scanController!.addError(e);
    }
  }

  Future<void> stopScan() async {
    AppLog.info(
      'stopScan: stopping BLE scan [scan#$_scanSessionId, '
      '${_knownDevices.length} result(s)]',
    );
    // Invalidate the session so any in-flight start/retry for it becomes a
    // no-op and cannot start another platform scan.
    _scanSessionId++;
    _currentScanSubscription?.cancel();
    _currentScanSubscription = null;
    _knownDevices.clear();
    try {
      await _platform.stopScan();
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
      AppLog.warn(
        'connectToDevice: already connecting, returning existing stream',
      );
      return _connectionStateController.stream;
    }
    if (isConnected && _connectedDevice?.remoteId.str == deviceId) {
      AppLog.info('connectToDevice: already connected to this device');
      return _connectionStateController.stream;
    }
    _isConnecting = true;

    _connectToAddress(deviceId);

    return _connectionStateController.stream;
  }

  Future<void> _connectToAddress(String deviceId) async {
    final started = DateTime.now();
    AppLog.info(
      '_connectToAddress: requested connect to $deviceId '
      '(autoConnect=false, timeout=15s)',
    );
    try {
      // Always stop any active scan and tear down a previous session before
      // installing the new one, so a superseded connection cannot mutate the
      // current session.
      await stopScan();
      if (_connectedDevice != null || _deviceStateSub != null) {
        AppLog.info(
          '_connectToAddress: switching devices, tearing down previous session',
        );
        await _teardownDeviceSession();
      }

      _connectedDevice = _deviceFactory(deviceId);

      await _connectedDevice!.connect(
        autoConnect: false,
        timeout: const Duration(seconds: 15),
      );
      final linkMs = DateTime.now().difference(started).inMilliseconds;
      AppLog.info('_connectToAddress: link-up for $deviceId (${linkMs}ms)');

      _setupDeviceStateListener();

      await _waitForConnectedOrTimeout();

      await _discoverServices();

      final readyMs = DateTime.now().difference(started).inMilliseconds;
      if (_notificationsReady) {
        AppLog.info(
          '_connectToAddress: ready (services discovered, notifications '
          'enabled) for $deviceId (${readyMs}ms)',
        );
      } else {
        AppLog.info(
          '_connectToAddress: ready (command-only, notifications '
          'unavailable) for $deviceId (${readyMs}ms)',
        );
      }
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
      if (!_connectionStateController.isClosed) {
        _connectionStateController.add(state);
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
    AppLog.warn(
      '_handleDisconnect: device disconnected '
      '(pending=${_pendingCompleters.length}, queued=${_commandQueue.length})',
    );
    _completePendingWithError(DisconnectedException());
    _connectedDevice = null;
    _service = null;
    _writeCharacteristic = null;
    _notifyCharacteristic = null;
    _discoveredServices = const [];
    _notificationSub?.cancel();
    _notificationSub = null;
    _notificationsReady = false;
    _commandQueue.clear();
    _pendingCompleters.clear();
    _isWriting = false;
    _queueGen++;
  }

  /// Cancels the current device session (subscriptions, characteristics and
  /// command queue) without emitting a disconnected state or touching the scan
  /// controller. Used when switching devices so the previous session cannot
  /// mutate the new one.
  Future<void> _teardownDeviceSession({bool disconnectLink = true}) async {
    final device = _connectedDevice;
    _completePendingWithError(DisconnectedException());
    _commandQueue.clear();
    _pendingCompleters.clear();
    _isWriting = false;
    _queueGen++;

    await _deviceStateSub?.cancel();
    _deviceStateSub = null;
    await _notificationSub?.cancel();
    _notificationSub = null;

    _service = null;
    _writeCharacteristic = null;
    _notifyCharacteristic = null;
    _connectedDevice = null;
    _notificationsReady = false;
    _discoveredServices = const [];

    if (device != null && disconnectLink) {
      try {
        await device.disconnect();
      } catch (e) {
        AppLog.warn('_teardownDeviceSession: device.disconnect() threw: $e');
      }
    }
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
    AppLog.debug('_discoverServices: found ${services.length} service(s)');
    _discoveredServices = services;

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
      // A device that does not expose the built-in MR Star service can still be
      // driven by a custom GATT profile, which resolves its own service UUID.
      // Do not fail the connection: leave the built-in characteristics unset
      // and let the profile path (or the user) decide what to do.
      AppLog.warn(
        '_discoverServices: service ${BleConstants.serviceUuid} not found; '
        'continuing without built-in MR Star support',
      );
      _service = null;
      _writeCharacteristic = null;
      _notifyCharacteristic = null;
      return;
    }
    AppLog.info('_discoverServices: found service ${targetService.uuid}');

    _service = targetService;

    for (final c in targetService.characteristics) {
      AppLog.debug(
        '_discoverServices: characteristic ${c.uuid} (${c.uuid.str128})',
      );
      if (UuidUtils.matches(c.uuid.str128, BleConstants.writeCharUuid)) {
        _writeCharacteristic = c;
        AppLog.info('_discoverServices: write characteristic ${c.uuid} found');
      } else if (UuidUtils.matches(
        c.uuid.str128,
        BleConstants.notifyCharUuid,
      )) {
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

    AppLog.info(
      '_discoverServices: services discovered '
      '(service=${BleConstants.serviceUuid}, write=${BleConstants.writeCharUuid}, '
      'notify=${_notifyCharacteristic == null ? 'absent' : BleConstants.notifyCharUuid})',
    );

    await _subscribeToNotifications();
  }

  // --- Notifications ---

  Future<void> _subscribeToNotifications() async {
    final notifyChar = _notifyCharacteristic;
    if (notifyChar == null) {
      AppLog.warn(
        '_subscribeToNotifications: no notify characteristic, skipping',
      );
      return;
    }
    AppLog.info(
      '_subscribeToNotifications: enabling notifications on $notifyChar',
    );

    try {
      await notifyChar.setNotifyValue(true);
      _notificationsReady = true;
      AppLog.info(
        '_subscribeToNotifications: notifications enabled '
        '(state-synchronized ready)',
      );
    } catch (e) {
      // Notification subscription is not required for command writes on MR
      // Star, so continue in command-only mode rather than failing the whole
      // connection. Readiness is reported as command-only, never as fully
      // state-synchronized.
      _notificationsReady = false;
      AppLog.error(
        '_subscribeToNotifications: failed to enable notifications '
        '(continuing command-only; device state will not sync)',
        e,
      );
      return;
    }

    // Also write CCC descriptor for completeness (as the APK does)
    for (final descriptor in notifyChar.descriptors) {
      AppLog.debug(
        '_subscribeToNotifications: descriptor ${descriptor.descriptorUuid}',
      );
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
      AppLog.debug('notification received: ${HexUtils.toHexString(data)}');
      if (!_notificationController.isClosed) {
        _notificationController.add(Uint8List.fromList(data));
      }

      // Decode notification and emit structured state update
      final decoded = ProtocolDecoder.decode(data);
      if (decoded != null) {
        final stateUpdate = ProtocolDecoder.parseState(decoded);
        if (stateUpdate != null) {
          AppLog.debug(
            'Decoded state update: ${stateUpdate.type} = ${stateUpdate.value}',
          );
          if (!_stateUpdateController.isClosed) {
            _stateUpdateController.add(stateUpdate);
          }
        }
      }
    });
    AppLog.info('_subscribeToNotifications: notifications active');
  }

  Stream<Uint8List> get notificationStream => _notificationController.stream;

  Stream<DeviceStateUpdate> get stateUpdateStream =>
      _stateUpdateController.stream;

  // --- Writing ---

  /// Serializes BLE writes to avoid concurrent writeWithoutResponse calls.
  /// The original APK serializes writes via its internal BLE library.
  final List<Future<void> Function()> _commandQueue = [];
  final List<Completer<void>> _pendingCompleters = [];
  bool _isWriting = false;
  int _queueGen = 0;

  /// Writes an MR Star command to the built-in FFF3 write characteristic.
  Future<void> writeCommand(Uint8List bytes) => writeBytes(bytes);

  /// Writes [bytes] to [characteristic] (or the built-in write characteristic
  /// when omitted), serialized through the shared command queue so a custom
  /// profile write and the built-in MR Star write can never overlap.
  Future<void> writeBytes(
    Uint8List bytes, {
    BluetoothCharacteristic? characteristic,
    bool withoutResponse = true,
  }) async {
    final hex = HexUtils.toHexString(bytes);
    final writeChar = characteristic ?? _writeCharacteristic;
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
    _pendingCompleters.add(completer);

    final queuedAt = DateTime.now();
    AppLog.info(
      'writeCommand: queued $hex (queue depth=${_commandQueue.length + 1})',
    );
    _commandQueue.add(() async {
      try {
        await writeChar.write(bytes, withoutResponse: withoutResponse);
        final elapsed = DateTime.now().difference(queuedAt).inMilliseconds;
        // writeWithoutResponse: this confirms the stack accepted the write,
        // not that the device applied it.
        AppLog.info(
          'writeCommand: issued $hex (waited ${elapsed}ms, '
          'without-response, no device confirmation)',
        );
        if (!completer.isCompleted) {
          completer.complete();
        }
      } catch (e) {
        AppLog.error('writeCommand: write failed $hex', e);
        if (!completer.isCompleted) {
          completer.completeError(e);
        }
      } finally {
        _pendingCompleters.remove(completer);
      }
    });

    _processQueue();

    // Fail-safe: a write must settle. Disconnection completes pending
    // completers explicitly (see _completePendingWithError); the timeout covers
    // a platform write that never returns.
    return completer.future.timeout(
      const Duration(seconds: 30),
      onTimeout: () {
        _pendingCompleters.remove(completer);
        AppLog.warn('writeCommand: timed out after 30s: $hex');
        throw TimeoutException(
          'BLE write timed out',
          const Duration(seconds: 30),
        );
      },
    );
  }

  void _processQueue() {
    if (_isWriting || _commandQueue.isEmpty) return;
    _isWriting = true;
    _runNext(_queueGen);
  }

  void _runNext(int gen) async {
    AppLog.debug(
      '_runNext: processing command queue (${_commandQueue.length} pending)',
    );
    while (gen == _queueGen && _commandQueue.isNotEmpty) {
      final task = _commandQueue.removeAt(0);
      try {
        await task();
      } catch (e) {
        AppLog.debug('_runNext: task failed (handled upstream): $e');
      }
      await Future.delayed(const Duration(milliseconds: 5));
    }
    if (gen == _queueGen) {
      _isWriting = false;
    }
  }

  // --- Generic GATT (custom device profiles) ---

  /// Every service discovered on the current connection.
  List<BluetoothService> get discoveredServices =>
      List.unmodifiable(_discoveredServices);

  /// Ensures services are discovered, re-running discovery when the cache is
  /// empty (for example when a profile is assigned after the connection was
  /// already established).
  Future<List<BluetoothService>> ensureServicesDiscovered() async {
    if (_discoveredServices.isNotEmpty) return _discoveredServices;
    final device = _connectedDevice;
    if (device == null) throw DisconnectedException();
    final services = await device.discoverServices();
    _discoveredServices = services;
    return services;
  }

  /// Resolves and validates the profile's configured GATT targets against the
  /// live discovered table.
  ///
  /// Throws [DisconnectedException], [ServiceNotFoundException],
  /// [CharacteristicNotFoundException] or [CharacteristicWriteException] when
  /// the device does not actually provide what the profile declares.
  Future<ResolvedGattTarget> resolveGattTarget({
    required String serviceUuid,
    required String writeCharacteristicUuid,
    String? notifyCharacteristicUuid,
  }) async {
    if (_connectedDevice == null) throw DisconnectedException();
    final services = await ensureServicesDiscovered();

    BluetoothService? service;
    for (final s in services) {
      if (UuidUtils.matches(s.uuid.str128, serviceUuid)) {
        service = s;
        break;
      }
    }
    if (service == null) throw ServiceNotFoundException(serviceUuid);

    final write = _findCharacteristic(service, writeCharacteristicUuid);
    if (write == null) {
      throw CharacteristicNotFoundException(writeCharacteristicUuid);
    }
    final props = write.properties;
    if (!props.write && !props.writeWithoutResponse) {
      throw CharacteristicWriteException(
        'Characteristic $writeCharacteristicUuid is not writable.',
      );
    }

    BluetoothCharacteristic? notify;
    final notifyId = notifyCharacteristicUuid?.trim() ?? '';
    if (notifyId.isNotEmpty) {
      notify = _findCharacteristic(service, notifyId);
      if (notify == null) {
        throw CharacteristicNotFoundException(notifyId);
      }
      if (!notify.properties.notify && !notify.properties.indicate) {
        throw CharacteristicWriteException(
          'Characteristic $notifyId cannot send notifications.',
        );
      }
    }

    return ResolvedGattTarget(
      writeCharacteristic: write,
      notifyCharacteristic: notify,
    );
  }

  BluetoothCharacteristic? _findCharacteristic(
    BluetoothService service,
    String uuid,
  ) {
    for (final c in service.characteristics) {
      if (UuidUtils.matches(c.uuid.str128, uuid)) return c;
    }
    return null;
  }

  /// Enables notifications on a resolved characteristic.
  Future<void> subscribeNotifications(BluetoothCharacteristic c) =>
      c.setNotifyValue(true);

  /// Best-effort disable of notifications (platform errors are ignored).
  Future<void> unsubscribeNotifications(BluetoothCharacteristic c) async {
    try {
      await c.setNotifyValue(false);
    } catch (e) {
      AppLog.warn('unsubscribeNotifications: ignored error: $e');
    }
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
    await stopScan();
    await _teardownDeviceSession();

    // Emit an explicit disconnected state on the app-lifetime controller so
    // every subscriber observes the teardown. The connection and notification
    // controllers stay open for the rest of the session; only the per-scan
    // controller is closed.
    if (!_connectionStateController.isClosed) {
      _connectionStateController.add(BluetoothConnectionState.disconnected);
    }
    await _scanController?.close();
    _scanController = null;
    AppLog.info('disconnect: session torn down');
  }

  void _completePendingWithError(Exception e) {
    for (final c in List<Completer<void>>.from(_pendingCompleters)) {
      if (!c.isCompleted) {
        c.completeError(e);
      }
    }
  }

  void _handleError(Exception e) {
    AppLog.error('BLE error: $e');
    _completePendingWithError(e);
    if (!_connectionStateController.isClosed) {
      _connectionStateController.addError(e);
    }
  }

  // --- Getters ---

  BluetoothDevice? get device => _connectedDevice;
  BluetoothService? get service => _service;
  BluetoothCharacteristic? get writeCharacteristic => _writeCharacteristic;
  BluetoothCharacteristic? get notifyCharacteristic => _notifyCharacteristic;

  bool get isConnected => _connectedDevice?.isConnected ?? false;

  /// Whether notifications are confirmed enabled for the current session.
  ///
  /// When false while connected, the session is command-only: writes are
  /// expected to work but device state is not synchronized back to the app.
  bool get notificationsReady => _notificationsReady;

  Stream<BluetoothConnectionState> get connectionState =>
      _connectionStateController.stream;
}

/// A profile's configured GATT targets resolved against a live device.
class ResolvedGattTarget {
  final BluetoothCharacteristic writeCharacteristic;
  final BluetoothCharacteristic? notifyCharacteristic;

  const ResolvedGattTarget({
    required this.writeCharacteristic,
    this.notifyCharacteristic,
  });

  bool get supportsWriteWithResponse => writeCharacteristic.properties.write;

  bool get supportsWriteWithoutResponse =>
      writeCharacteristic.properties.writeWithoutResponse;

  bool get supportsNotify {
    final n = notifyCharacteristic;
    if (n == null) return false;
    return n.properties.notify || n.properties.indicate;
  }
}
