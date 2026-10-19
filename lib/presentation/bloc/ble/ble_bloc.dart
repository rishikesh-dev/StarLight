// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'package:starlight/core/utils/app_logger.dart';
import 'package:starlight/domain/entities/ble_device.dart';
import 'package:starlight/domain/entities/connection_state.dart';
import 'package:starlight/domain/entities/device.dart';
import 'package:starlight/domain/entities/device_capability.dart';
import 'package:starlight/domain/entities/device_state.dart';
import 'package:starlight/domain/entities/saved_device.dart';
import 'package:starlight/domain/repositories/ble_repository.dart';
import 'package:starlight/domain/usecases/connect_device.dart';
import 'package:starlight/domain/usecases/disconnect_device.dart';
import 'package:starlight/domain/usecases/scan_devices.dart';
import 'package:starlight/domain/usecases/stop_scan.dart';
import 'package:starlight/domain/repositories/device_repository.dart';
import 'package:starlight/domain/repositories/saved_device_repository.dart';

import 'ble_event.dart';
import 'ble_state.dart';

/// BLoC for managing BLE scanning and connection.
///
/// Handles the full BLE flow:
/// 1. Permission checking
/// 2. Device scanning
/// 3. Connection management
/// 4. Disconnect/reconnect
class BleBloc extends Bloc<BleEvent, BleState> {
  final BleRepository _repository;
  final SavedDeviceRepository _savedRepo;
  final ScanDevices _scanDevices;
  final StopScan _stopScan;
  final ConnectDevice _connectDevice;
  final DisconnectDevice _disconnectDevice;

  StreamSubscription<List<BleDevice>>? _scanSubscription;
  StreamSubscription<DeviceConnectionState>? _connectionSubscription;
  StreamSubscription<BluetoothAdapterState>? _adapterStateSub;

  BleDevice? _currentDevice;
  final DeviceRepository? _deviceRepository;

  BleBloc(this._repository, this._savedRepo, {this._deviceRepository})
    : _scanDevices = ScanDevices(_repository),
      _stopScan = StopScan(_repository),
      _connectDevice = ConnectDevice(_repository),
      _disconnectDevice = DisconnectDevice(_repository),
      super(BleInitial()) {
    // Scan sessions must be serialized. Bloc's default transformer is
    // concurrent, so rapid StartScan events interleave at await points:
    // released together, both handlers evaluate `_scanSubscription?.cancel()`
    // before either assigns its own subscription, and the second assignment
    // orphans the first — a duplicate listener that survives StopScan and
    // close(), delivering scan results into a closed bloc. asyncExpand runs
    // one StartScan to completion before pulling the next event.
    on<EnsureBluetoothReady>(
      _onEnsureBluetoothReady,
      transformer: (events, mapper) => events.asyncExpand(mapper),
    );
    on<RetryBluetooth>(_onRetryBluetooth);
    on<BluetoothStateRecheck>(_onBluetoothStateRecheck);
    on<OpenAppSettingsRequested>(_onOpenAppSettings);
    on<StartScan>(
      _onStartScan,
      transformer: (events, mapper) => events.asyncExpand(mapper),
    );
    on<StopScanRequested>(_onStopScan);
    on<ConnectToDevice>(_onConnect);
    on<DisconnectRequested>(_onDisconnect);
    on<LoadPairedDevice>(_onLoadPairedDevice);
    on<ReconnectRequested>(_onReconnectRequested);
    on<RenameDevice>(_onRenameDevice);
    on<ForgetDevice>(_onForgetDevice);
    on<RefreshConnection>(_onRefresh);
    on<ScanResultReceived>(_onScanResult);
    on<ConnectionStateChanged>(_onConnectionStateChanged);
    on<BleErrorOccurred>(_onBleError);

    // Listen to adapter state transitions. When the adapter turns off while we
    // are scanning or connecting, tear down gracefully; when it comes back on,
    // emit a state so the UI can offer retry. We do NOT auto-retry scanning
    // while the adapter is off — the user must explicitly retry.
    _adapterStateSub = _repository.adapterState.listen(_onAdapterStateChanged);
    AppLog.info('BleBloc initialized');
  }

  @override
  void onTransition(Transition<BleEvent, BleState> transition) {
    AppLog.debug(
      'BLE transition: ${transition.event.runtimeType} '
      '(${_stateSummary(transition.event)})\n'
      '      ${transition.currentState.runtimeType} '
      '→ ${transition.nextState.runtimeType}',
    );
    super.onTransition(transition);
  }

  static String _stateSummary(BleEvent event) {
    if (event is ConnectToDevice) {
      return '${event.deviceName} (${event.deviceId})';
    }
    if (event is ScanResultReceived) {
      return '${event.devices.length} device(s)';
    }
    if (event is BleErrorOccurred) {
      return event.message;
    }
    return '';
  }

  /// Guards against repeated startup initialisation.
  bool _bluetoothChecked = false;

  Future<void> _onEnsureBluetoothReady(
    EnsureBluetoothReady event,
    Emitter<BleState> emit,
  ) async {
    AppLog.info('BLE event: EnsureBluetoothReady');
    await _ensureBluetoothReady(emit, requestEnable: true);
  }

  Future<void> _onRetryBluetooth(
    RetryBluetooth event,
    Emitter<BleState> emit,
  ) async {
    AppLog.info('BLE event: RetryBluetooth');
    // A retry is an explicit user action, so requesting the system dialog again
    // is allowed.
    _bluetoothChecked = false;
    await _ensureBluetoothReady(emit, requestEnable: true);
  }

  void _onBluetoothStateRecheck(
    BluetoothStateRecheck event,
    Emitter<BleState> emit,
  ) {
    AppLog.debug('BLE event: BluetoothStateRecheck');
    // Never request the enable dialog here: this runs on adapter transitions
    // (including returning from system settings) and must not reopen dialogs.
    _emitAdapterReadiness(emit, event.state);
  }

  Future<void> _onOpenAppSettings(
    OpenAppSettingsRequested event,
    Emitter<BleState> emit,
  ) async {
    AppLog.info('BLE event: OpenAppSettingsRequested');
    try {
      await _repository.openSystemSettings();
    } catch (e) {
      AppLog.warn('OpenAppSettingsRequested: failed: $e');
    }
  }

  /// Shared readiness logic. [requestEnable] is true only for startup and
  /// explicit user retries; it is false for passive adapter-state rechecks.
  ///
  /// The whole check is guarded: any platform error (e.g. a permission request
  /// that fails or is rejected) must surface as an actionable state instead of
  /// aborting the handler and leaving the UI stuck on the initial state.
  Future<void> _ensureBluetoothReady(
    Emitter<BleState> emit, {
    required bool requestEnable,
  }) async {
    // Skip if already connected/connecting: do not disturb an active session.
    if (state is BleConnected || state is BleConnecting) {
      AppLog.debug('EnsureBluetoothReady: session active, skipping');
      return;
    }
    if (_bluetoothChecked && !requestEnable) {
      AppLog.debug('EnsureBluetoothReady: already checked, skipping');
      return;
    }
    _bluetoothChecked = true;

    try {
      final supported = await _repository.isSupported();
      if (!supported) {
        AppLog.warn('EnsureBluetoothReady: Bluetooth not supported');
        emit(
          const BleBluetoothUnavailable(
            'This device does not support Bluetooth',
          ),
        );
        return;
      }

      // Permissions first: without them the adapter cannot be used.
      if (!await _repository.hasPermissions()) {
        AppLog.info('EnsureBluetoothReady: requesting permissions');
        final granted = await _repository.requestPermissions();
        if (!granted) {
          final permanent = await _repository.isPermanentlyDenied();
          AppLog.warn(
            'EnsureBluetoothReady: permissions denied (permanent=$permanent)',
          );
          emit(
            BlePermissionDenied(
              permanent
                  ? 'Bluetooth permission was permanently denied. Enable it in '
                        'system settings to find and connect to lights.'
                  : 'Bluetooth permissions are required to find and connect to '
                        'lights',
              permanentlyDenied: permanent,
            ),
          );
          return;
        }
      }

      if (_repository.adapterStateNow == BluetoothAdapterState.on) {
        AppLog.info('EnsureBluetoothReady: adapter already on');
        _emitReady(emit);
        return;
      }

      if (!requestEnable) {
        _emitAdapterReadiness(emit);
        return;
      }

      // Adapter is off: request the system enable flow exactly once.
      AppLog.info('EnsureBluetoothReady: adapter off, requesting enable');
      emit(const BleBluetoothEnabling());
      final enabled = await _repository.enableBluetooth();
      if (enabled) {
        AppLog.info('EnsureBluetoothReady: adapter enabled');
        _emitReady(emit);
      } else {
        // Declined or unavailable. Do not retry automatically.
        AppLog.warn('EnsureBluetoothReady: adapter not enabled (declined)');
        emit(
          const BleBluetoothOff(
            'Bluetooth is off. Turn it on to find and connect to lights.',
          ),
        );
      }
    } catch (e, stackTrace) {
      // Do not let a platform failure escape the event handler: report it and
      // allow a later retry to run the check again.
      _bluetoothChecked = false;
      AppLog.error(
        'EnsureBluetoothReady: readiness check failed',
        e,
        stackTrace,
      );
      emit(
        const BleError('Could not read the Bluetooth state. Please try again.'),
      );
    }
  }

  /// Emits a passive readiness state based on the current adapter state.
  /// [observed] is the state from the transition that triggered this check, or
  /// null to read the cached adapter state.
  void _emitAdapterReadiness(
    Emitter<BleState> emit, [
    BluetoothAdapterState? observed,
  ]) {
    if (state is BleConnected || state is BleConnecting) return;
    switch (observed ?? _repository.adapterStateNow) {
      case BluetoothAdapterState.on:
        _emitReady(emit);
      case BluetoothAdapterState.unavailable:
      case BluetoothAdapterState.unauthorized:
        emit(
          const BleBluetoothUnavailable(
            'Bluetooth is unavailable on this device',
          ),
        );
      default:
        emit(
          const BleBluetoothOff(
            'Bluetooth is off. Turn it on to find and connect to lights.',
          ),
        );
    }
  }

  /// The adapter is usable: reflect the (disconnected) ready state without
  /// clobbering an active scan or connection. The last-known paired device (if
  /// any) is carried along so the UI can offer a reconnect.
  void _emitReady(Emitter<BleState> emit) {
    if (state is BleScanning ||
        state is BleConnected ||
        state is BleConnecting) {
      return;
    }
    emit(BleDisconnected(DeviceConnectionState.disconnected, _currentDevice));
  }

  Future<void> _onStartScan(StartScan event, Emitter<BleState> emit) async {
    AppLog.info('BLE event: StartScan');
    // Check permissions
    if (!await _repository.hasPermissions()) {
      AppLog.info('BLE: permissions missing, requesting');
      final granted = await _repository.requestPermissions();
      if (!granted) {
        final permanent = await _repository.isPermanentlyDenied();
        AppLog.error('BLE: permissions denied (permanent=$permanent)');
        emit(
          BlePermissionDenied(
            permanent
                ? 'Bluetooth permission was permanently denied. Enable it in '
                      'system settings to find and connect to lights.'
                : 'BLE permissions are required to scan for devices',
            permanentlyDenied: permanent,
          ),
        );
        return;
      }
    }

    // Check Bluetooth enabled — wait for a confirmed adapter-on state.
    // This handles the Linux/BlueZ initialization race where adapterState
    // may briefly report off/unknown before the adapter settles to on.
    final isOn = await _repository.waitForAdapterOn();
    if (!isOn) {
      AppLog.warn('BLE: bluetooth adapter is not on');
      // Reflect a clear, actionable off state rather than a dead-end error.
      _bluetoothChecked = false;
      await _ensureBluetoothReady(emit, requestEnable: true);
      return;
    }

    emit(BleScanning([]));

    // Cancel existing subscription
    await _scanSubscription?.cancel();

    // Start scan
    _scanSubscription = _scanDevices().listen(
      (devices) {
        add(ScanResultReceived(devices));
      },
      onError: (e) {
        AppLog.error('BLE: scan stream error', e);
        add(BleErrorOccurred(e.toString()));
      },
    );
  }

  void _onAdapterStateChanged(BluetoothAdapterState state) {
    AppLog.info('BLE: adapter state changed to $state');
    // When the adapter turns off while we are scanning, notify the user. Do
    // not auto-retry while Bluetooth is off — the user must explicitly retry.
    if (state == BluetoothAdapterState.off && this.state is BleScanning) {
      add(BleErrorOccurred('Bluetooth adapter turned off'));
    }
    // Re-evaluate readiness on every adapter transition (on or off) so the UI
    // reflects the real adapter state.
    if (state == BluetoothAdapterState.on ||
        state == BluetoothAdapterState.off ||
        state == BluetoothAdapterState.unavailable ||
        state == BluetoothAdapterState.unauthorized) {
      add(BluetoothStateRecheck(state));
    }
  }

  void _onScanResult(ScanResultReceived event, Emitter<BleState> emit) {
    // Sort devices: MR Star devices (GATT--DEMO prefix) first
    final sortedDevices = List<BleDevice>.from(event.devices)
      ..sort((a, b) {
        final aIsMrStar = a.name.startsWith('GATT--DEMO');
        final bIsMrStar = b.name.startsWith('GATT--DEMO');
        if (aIsMrStar && !bIsMrStar) return -1;
        if (!aIsMrStar && bIsMrStar) return 1;
        return 0;
      });
    emit(BleScanning(sortedDevices));
  }

  Future<void> _onStopScan(
    StopScanRequested event,
    Emitter<BleState> emit,
  ) async {
    AppLog.info('BLE event: StopScanRequested');
    await _scanSubscription?.cancel();
    await _stopScan();
    if (state is BleScanning) {
      emit(BleDisconnected(DeviceConnectionState.disconnected, _currentDevice));
    }
  }

  Future<void> _onConnect(ConnectToDevice event, Emitter<BleState> emit) async {
    AppLog.info(
      'BLE event: ConnectToDevice ${event.deviceName} (${event.deviceId})',
    );
    // Track the device identity so BleConnected can show a real name.
    _currentDevice = BleDevice(
      id: event.deviceId,
      name: event.deviceName,
      rssi: 0,
      isConnected: false,
    );

    // Stop and await any active scan before connecting: connecting while BlueZ
    // discovery is still running degrades connection reliability.
    await _scanSubscription?.cancel();
    _scanSubscription = null;
    await _stopScan();

    emit(BleConnecting(event.deviceId, event.deviceName));

    // Listen for connection state changes
    _connectionSubscription?.cancel();
    _connectionSubscription = _connectDevice(event.deviceId).listen(
      (connState) {
        add(ConnectionStateChanged(connState));
      },
      onError: (e) {
        AppLog.error('BLE: connection stream error', e);
        add(BleErrorOccurred(e.toString()));
      },
    );
  }

  void _onConnectionStateChanged(
    ConnectionStateChanged event,
    Emitter<BleState> emit,
  ) {
    AppLog.info('BLE: connection state reached ${event.state}');
    if (event.state == DeviceConnectionState.connected) {
      final device =
          _currentDevice ??
          BleDevice(id: '', name: '', rssi: 0, isConnected: true);
      _currentDevice = device.copyWith(isConnected: true);
      emit(BleConnected(_currentDevice!));
      _onConnected(device);
    } else if (event.state == DeviceConnectionState.disconnected) {
      _currentDevice = _currentDevice?.copyWith(isConnected: false);
      _onDisconnected();
      // Auto-reconnect: emit disconnected but allow reconnect
      emit(BleDisconnected(event.state, _currentDevice));
      _attemptReconnect();
    } else if (event.state == DeviceConnectionState.connecting) {
      // Keep current connecting state
    }
  }

  /// Persist the paired device (so auto-reconnect works after a restart) and
  /// register it in the universal device registry with its capabilities.
  Future<void> _onConnected(BleDevice device) async {
    if (device.id.isEmpty) return;
    try {
      await _savedRepo.save(SavedDevice(id: device.id, name: device.name));
    } catch (e) {
      AppLog.error('BLE: failed to persist paired device', e);
    }

    final repository = _deviceRepository;
    if (repository == null) return;
    try {
      final registered = Device.fromBleDevice(
        id: device.id,
        name: device.name,
        address: device.id,
        capabilities: const [
          DeviceCapability.power,
          DeviceCapability.brightness,
          DeviceCapability.color,
          DeviceCapability.effect,
          DeviceCapability.speed,
        ],
        connectionState: DeviceConnectionState.connected,
        state: const LightState(isOn: false, isConnected: true),
        metadata: const {'isMrStar': true},
      );
      await repository.updateDevice(registered);
      AppLog.info('BLE: device registered in device registry: ${device.id}');
    } catch (e) {
      AppLog.error('BLE: failed to register device in registry', e);
    }
  }

  /// Keep the registry's connection state in sync with the transport.
  Future<void> _onDisconnected() async {
    final repository = _deviceRepository;
    final id = _currentDevice?.id;
    if (repository == null || id == null || id.isEmpty) return;
    try {
      final device = await repository.getDevice(id);
      if (device != null) {
        await repository.updateDevice(
          device.copyWith(connectionState: DeviceConnectionState.disconnected),
        );
      }
    } catch (e) {
      AppLog.error('BLE: failed to update registry connection state', e);
    }
  }

  void _onBleError(BleErrorOccurred event, Emitter<BleState> emit) {
    AppLog.error('BLE error: ${event.message}');
    emit(BleError(event.message));
  }

  Future<void> _onDisconnect(
    DisconnectRequested event,
    Emitter<BleState> emit,
  ) async {
    AppLog.info('BLE event: DisconnectRequested');
    _cancelReconnect();
    _connectionSubscription?.cancel();
    _connectionSubscription = null;
    await _disconnectDevice();
    // Keep the paired device so the UI can offer a reconnect; only the live
    // connection is torn down.
    emit(BleDisconnected(DeviceConnectionState.disconnected, _currentDevice));
  }

  /// Loads the persisted pairing (if any) into [_currentDevice] for display.
  /// It deliberately does NOT connect — reconnecting is an explicit user action.
  Future<void> _onLoadPairedDevice(
    LoadPairedDevice event,
    Emitter<BleState> emit,
  ) async {
    if (_currentDevice != null) return;
    AppLog.debug('BLE event: LoadPairedDevice');
    SavedDevice? saved;
    try {
      saved = await _savedRepo.load();
    } catch (e) {
      AppLog.warn('BLE: failed to load paired device: $e');
      return;
    }
    if (saved == null || saved.id.isEmpty) return;
    _currentDevice = BleDevice(
      id: saved.id,
      name: saved.name,
      rssi: 0,
      isConnected: false,
    );
    // Reflect the paired identity if we are sitting in a neutral ready state.
    final current = state;
    if (current is BleInitial || current is BleDisconnected) {
      emit(BleDisconnected(DeviceConnectionState.disconnected, _currentDevice));
    }
  }

  /// Reconnects to the paired device (or the last-known device) on demand.
  Future<void> _onReconnectRequested(
    ReconnectRequested event,
    Emitter<BleState> emit,
  ) async {
    AppLog.info('BLE event: ReconnectRequested');
    if (state is BleConnected ||
        state is BleConnecting ||
        state is BleScanning) {
      AppLog.debug('BLE: reconnect skipped, transport busy');
      return;
    }
    var target = _currentDevice;
    if (target == null) {
      try {
        final saved = await _savedRepo.load();
        if (saved != null && saved.id.isNotEmpty) {
          target = BleDevice(
            id: saved.id,
            name: saved.name,
            rssi: 0,
            isConnected: false,
          );
          _currentDevice = target;
        }
      } catch (e) {
        AppLog.warn('BLE: reconnect could not load paired device: $e');
      }
    }
    if (target == null) {
      AppLog.warn('BLE: ReconnectRequested with no paired device');
      return;
    }
    add(ConnectToDevice(target.id, target.name));
  }

  /// Renames the paired device: updates the in-memory identity, the persisted
  /// pairing and (when available) the device registry, then re-emits the current
  /// state so the UI reflects the new name immediately.
  Future<void> _onRenameDevice(
    RenameDevice event,
    Emitter<BleState> emit,
  ) async {
    final name = event.name.trim();
    final current = _currentDevice;
    if (current == null || name.isEmpty) return;
    AppLog.info('BLE event: RenameDevice "$name"');
    final updated = current.copyWith(name: name);
    _currentDevice = updated;

    try {
      await _savedRepo.save(SavedDevice(id: updated.id, name: name));
    } catch (e) {
      AppLog.error('BLE: failed to persist renamed device', e);
    }

    final repository = _deviceRepository;
    if (repository != null) {
      try {
        final existing = await repository.getDevice(updated.id);
        if (existing != null) {
          await repository.updateDevice(existing.copyWith(name: name));
        }
      } catch (e) {
        AppLog.error('BLE: failed to rename device in registry', e);
      }
    }

    final currentState = state;
    if (currentState is BleConnected) {
      emit(BleConnected(updated));
    } else if (currentState is BleDisconnected) {
      emit(BleDisconnected(currentState.connectionState, updated));
    }
  }

  /// Forgets the paired device: tears down the connection, clears the persisted
  /// pairing and removes it from the device registry.
  Future<void> _onForgetDevice(
    ForgetDevice event,
    Emitter<BleState> emit,
  ) async {
    AppLog.info('BLE event: ForgetDevice');
    final id = _currentDevice?.id;
    _cancelReconnect();
    _connectionSubscription?.cancel();
    _connectionSubscription = null;
    await _disconnectDevice();

    try {
      await _savedRepo.remove();
    } catch (e) {
      AppLog.error('BLE: failed to forget paired device', e);
    }

    if (id != null && id.isNotEmpty) {
      try {
        await _deviceRepository?.removeDevice(id);
      } catch (e) {
        AppLog.error('BLE: failed to remove device from registry', e);
      }
    }

    _currentDevice = null;
    emit(const BleDisconnected());
  }

  Future<void> _onRefresh(
    RefreshConnection event,
    Emitter<BleState> emit,
  ) async {
    AppLog.info('BLE event: RefreshConnection');
    if (_repository.isConnected) {
      await _repository.readRssi();
    } else {
      AppLog.debug('BLE: refresh skipped, not connected');
    }
  }

  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 5;
  Duration _reconnectDelay = Duration(milliseconds: 2000);
  static const Duration _maxReconnectDelay = Duration(seconds: 30);
  Timer? _reconnectTimer;
  bool _reconnectCancelled = false;

  /// Attempt to reconnect with bounded exponential back-off.
  /// - Delay starts at 2s, doubles each failure, capped at 30s.
  /// - Cancelled when: user disconnects, selects another device, or removes the saved device.
  void _attemptReconnect() {
    // Reset if we've exhausted attempts
    if (_reconnectAttempts >= _maxReconnectAttempts) {
      AppLog.debug('BLE: max reconnect attempts reached, giving up');
      _reconnectAttempts = 0;
      _reconnectCancelled = false;
      _reconnectTimer?.cancel();
      _reconnectTimer = null;
      return;
    }

    // If a reconnect is already in progress, skip (will be re-triggered on next disconnect)
    if (_reconnectTimer?.isActive ?? false) {
      AppLog.debug('BLE: reconnect already in progress, skipping');
      return;
    }

    _reconnectAttempts++;
    final delay = _reconnectDelay;
    AppLog.info(
      'BLE: reconnect attempt $_reconnectAttempts in ${delay.inSeconds}s',
    );

    _reconnectTimer = Timer(delay, _onReconnectTimerTick);
    _reconnectDelay = _reconnectDelay * 2 > _maxReconnectDelay
        ? _maxReconnectDelay
        : _reconnectDelay * 2;
  }

  void _onReconnectTimerTick() {
    _reconnectTimer = null;
    // Mark as cancelled if the state changed before we got to try
    if (_reconnectCancelled) {
      AppLog.debug('BLE: reconnect cancelled before execution');
      _reconnectCancelled = false;
      // If still disconnected and under max attempts, try again
      if (_reconnectAttempts < _maxReconnectAttempts &&
          state is BleDisconnected) {
        _attemptReconnect();
      }
      return;
    }
    AppLog.debug('BLE: executing reconnect attempt $_reconnectAttempts');
    _doReconnect();
  }

  // Track whether a reconnect was vetoed by a user action since the timer fired
  set reconnectCancelled(bool value) {
    _reconnectCancelled = value;
  }

  // The actual reconnection logic: re-emit ConnectToDevice for the saved device
  Future<void> _doReconnect() async {
    AppLog.debug('BLE: _doReconnect called, attempts=$_reconnectAttempts');

    // If not in disconnected state, just return
    if (state is! BleDisconnected) {
      AppLog.debug('BLE: not disconnected, aborting reconnect');
      return;
    }

    // Load the saved device and attempt connection
    final saved = await _savedRepo.load();
    if (saved == null) {
      AppLog.debug('BLE: no saved device for reconnect');
      return;
    }

    AppLog.info('BLE: auto-reconnecting to ${saved.id} (${saved.name})');

    // Cancel any existing connection subscription before reconnecting
    _connectionSubscription?.cancel();
    _connectionSubscription = null;

    // Emit ConnectToDevice event — the existing _onConnect flow will handle
    // the stream using the device id persisted in storage.
    add(ConnectToDevice(saved.id, saved.name));
  }

  /// Called when the user initiates a disconnect or changes device — cancels any pending reconnect.
  void _cancelReconnect() {
    _reconnectCancelled = true;
    _reconnectAttempts = 0;
    _reconnectDelay = Duration(milliseconds: 2000);
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    AppLog.debug('BLE: reconnect cancelled by user action');
  }

  @override
  Future<void> close() async {
    AppLog.info('BleBloc closing');
    _reconnectAttempts = _maxReconnectAttempts;
    await _scanSubscription?.cancel();
    await _connectionSubscription?.cancel();
    await _adapterStateSub?.cancel();
    await _disconnectDevice();
    return super.close();
  }
}
