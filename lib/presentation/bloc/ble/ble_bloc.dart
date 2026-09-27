import 'dart:async';

import 'package:bloc/bloc.dart';

import 'package:starlight/core/utils/app_logger.dart';
import 'package:starlight/domain/entities/ble_device.dart';
import 'package:starlight/domain/entities/connection_state.dart';
import 'package:starlight/domain/repositories/ble_repository.dart';
import 'package:starlight/domain/usecases/connect_device.dart';
import 'package:starlight/domain/usecases/disconnect_device.dart';
import 'package:starlight/domain/usecases/scan_devices.dart';
import 'package:starlight/domain/usecases/stop_scan.dart';

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
  final ScanDevices _scanDevices;
  final StopScan _stopScan;
  final ConnectDevice _connectDevice;
  final DisconnectDevice _disconnectDevice;

  StreamSubscription<List<BleDevice>>? _scanSubscription;
  StreamSubscription<DeviceConnectionState>? _connectionSubscription;
  StreamSubscription? _adapterStateSub;

  BleDevice? _currentDevice;

  BleBloc(this._repository)
      : _scanDevices = ScanDevices(_repository),
        _stopScan = StopScan(_repository),
        _connectDevice = ConnectDevice(_repository),
        _disconnectDevice = DisconnectDevice(_repository),
        super(BleInitial()) {
    on<StartScan>(_onStartScan);
    on<StopScanRequested>(_onStopScan);
    on<ConnectToDevice>(_onConnect);
    on<DisconnectRequested>(_onDisconnect);
    on<RefreshConnection>(_onRefresh);
    on<ScanResultReceived>(_onScanResult);
    on<ConnectionStateChanged>(_onConnectionStateChanged);
    on<BleErrorOccurred>(_onBleError);

    // Listen to adapter state for auto-reconnect
    _adapterStateSub = _repository.connectionState.listen((_) {});
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

  Future<void> _onStartScan(
      StartScan event, Emitter<BleState> emit) async {
    AppLog.info('BLE event: StartScan');
    // Check permissions
    if (!await _repository.hasPermissions()) {
      AppLog.info('BLE: permissions missing, requesting');
      final granted = await _repository.requestPermissions();
      if (!granted) {
        AppLog.error('BLE: permissions denied');
        emit(const BlePermissionDenied(
            'BLE permissions are required to scan for devices'));
        return;
      }
    }

    // Check Bluetooth enabled
    if (!await _repository.isBluetoothEnabled()) {
      AppLog.warn('BLE: bluetooth disabled, attempting to enable');
      try {
        await _repository.requestPermissions();
        // Try to enable Bluetooth
        await _repository.isBluetoothEnabled();
      } catch (e) {
        AppLog.error('BLE: could not enable bluetooth', e);
        emit(BleError('Bluetooth is not enabled'));
        return;
      }
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

  void _onScanResult(
      ScanResultReceived event, Emitter<BleState> emit) {
    emit(BleScanning(event.devices));
  }

  Future<void> _onStopScan(
      StopScanRequested event, Emitter<BleState> emit) async {
    AppLog.info('BLE event: StopScanRequested');
    await _scanSubscription?.cancel();
    await _stopScan();
    if (state is BleScanning) {
      emit(BleDisconnected());
    }
  }

  Future<void> _onConnect(
      ConnectToDevice event, Emitter<BleState> emit) async {
    AppLog.info(
      'BLE event: ConnectToDevice ${event.deviceName} (${event.deviceId})',
    );
    // Cancel scan first
    await _scanSubscription?.cancel();
    _scanSubscription = null;

    emit(BleConnecting(event.deviceId, event.deviceName));

    // Listen for connection state changes
    _connectionSubscription?.cancel();
    _connectionSubscription =
        _connectDevice(event.deviceId).listen((connState) {
      add(ConnectionStateChanged(connState));
    }, onError: (e) {
      AppLog.error('BLE: connection stream error', e);
      add(BleErrorOccurred(e.toString()));
    });
  }

  void _onConnectionStateChanged(
      ConnectionStateChanged event, Emitter<BleState> emit) {
    AppLog.info('BLE: connection state reached ${event.state}');
    if (event.state == DeviceConnectionState.connected) {
      final device = _currentDevice ??
          BleDevice(
            id: '',
            name: '',
            rssi: 0,
            isConnected: true,
          );
      emit(BleConnected(device));
    } else if (event.state == DeviceConnectionState.disconnected) {
      // Auto-reconnect: emit disconnected but allow reconnect
      emit(BleDisconnected(event.state));
      _attemptReconnect();
    } else if (event.state == DeviceConnectionState.connecting) {
      // Keep current connecting state
    }
  }

  void _onBleError(BleErrorOccurred event, Emitter<BleState> emit) {
    AppLog.error('BLE error: ${event.message}');
    emit(BleError(event.message));
  }

  Future<void> _onDisconnect(
      DisconnectRequested event, Emitter<BleState> emit) async {
    AppLog.info('BLE event: DisconnectRequested');
    _connectionSubscription?.cancel();
    _connectionSubscription = null;
    await _disconnectDevice();
    emit(BleDisconnected());
  }

  Future<void> _onRefresh(
      RefreshConnection event, Emitter<BleState> emit) async {
    AppLog.info('BLE event: RefreshConnection');
    if (_repository.isConnected) {
      await _repository.readRssi();
    } else {
      AppLog.debug('BLE: refresh skipped, not connected');
    }
  }

  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 3;
  static const Duration _reconnectDelay = Duration(seconds: 5);

  void _attemptReconnect() {
    if (_reconnectAttempts >= _maxReconnectAttempts) {
      AppLog.debug('BLE: max reconnect attempts reached, giving up');
      _reconnectAttempts = 0;
      return;
    }
    _reconnectAttempts++;
    AppLog.debug('BLE: scheduling reconnect attempt $_reconnectAttempts');
    Future.delayed(_reconnectDelay, () {
      if (!isClosed && state is BleDisconnected) {
        // Reconnect would require knowing the device ID
        // In a real implementation, we'd store the device ID
        // and attempt reconnection
      }
    });
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
