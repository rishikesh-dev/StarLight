// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:starlight/data/datasources/ble_datasource.dart';
import 'package:starlight/data/datasources/device_datasource.dart';
import 'package:starlight/data/models/device_model.dart';
import 'package:starlight/domain/adapters/device_adapter.dart';
import 'package:starlight/domain/entities/connection_state.dart';
import 'package:starlight/domain/entities/device.dart';
import 'package:starlight/domain/entities/device_event.dart';
import 'package:starlight/domain/entities/device_state.dart';
import 'package:starlight/domain/entities/device_type.dart';
import 'package:starlight/domain/repositories/device_repository.dart';

/// Implementation of [DeviceRepository] using device adapters.
///
/// One authoritative registry for every configured device, persisted to
/// SharedPreferences via [DeviceDataSource]. Adapters must share a single
/// transport owner per physical connection — pass the same [BleDataSource]
/// used by `BleRepositoryImpl` when constructing the BLE adapter.
class DeviceRepositoryImpl implements DeviceRepository {
  final List<DeviceAdapter> _adapters;
  final DeviceDataSource? _deviceDataSource;

  final Map<String, Device> _devices = {};
  final Map<String, StreamController<DeviceConnectionState>>
  _connectionControllers = {};
  final StreamController<DeviceEvent> _eventsController =
      StreamController<DeviceEvent>.broadcast();

  DeviceRepositoryImpl({required this._adapters, this._deviceDataSource});

  DeviceAdapter? _getAdapter(Device device) {
    for (final adapter in _adapters) {
      if (adapter.canHandle(device)) {
        return adapter;
      }
    }
    return null;
  }

  @override
  Stream<DeviceEvent> get events => _eventsController.stream;

  // --- Persistence ---

  /// Restores previously persisted devices into the in-memory registry.
  /// Restored devices are marked [DeviceConnectionState.disconnected].
  Future<void> loadPersistedDevices() async {
    final dataSource = _deviceDataSource;
    if (dataSource == null) return;
    final models = await dataSource.loadDevices();
    for (final model in models) {
      final device = model.toEntity();
      _devices[device.id] = device;
    }
  }

  /// Persists the current in-memory device registry.
  Future<void> persistDevices() async {
    final dataSource = _deviceDataSource;
    if (dataSource == null) return;
    final models = _devices.values
        .map((d) => DeviceModel.fromEntity(d))
        .toList();
    await dataSource.saveDevices(models);
  }

  // --- Device registry operations ---

  /// Registers a new device or updates an existing one.
  /// Automatically persists the change when a data source is available.
  Future<void> addDevice(Device device) async {
    _devices[device.id] = device;
    await persistDevices();
  }

  @override
  Future<void> updateDevice(Device device) async {
    _devices[device.id] = device;
    await persistDevices();
  }

  @override
  Future<void> removeDevice(String deviceId) async {
    await disconnectDevice(deviceId);
    _devices.remove(deviceId);
    final dataSource = _deviceDataSource;
    if (dataSource != null) {
      await dataSource.removeDevice(deviceId);
    }
  }

  // --- Lookup / filtering ---

  @override
  Future<List<Device>> getDevices() async {
    return _devices.values.toList();
  }

  @override
  Future<Device?> getDevice(String deviceId) async {
    return _devices[deviceId];
  }

  @override
  Future<List<Device>> getDevicesByType(DeviceType type) async {
    return _devices.values.where((d) => d.type == type).toList();
  }

  @override
  Future<List<Device>> getDevicesByRoom(String roomId) async {
    return _devices.values.where((d) => d.roomId == roomId).toList();
  }

  @override
  Future<List<Device>> getConnectedDevices() async {
    return _devices.values
        .where((d) => d.connectionState == DeviceConnectionState.connected)
        .toList();
  }

  @override
  Future<List<Device>> getFavoriteDevices() async {
    return _devices.values.where((d) => d.favorite).toList();
  }

  // --- Transport / permissions ---

  @override
  Future<bool> isTransportAvailable() async {
    for (final adapter in _adapters) {
      if (adapter.transport == 'ble') {
        try {
          final state = await FlutterBluePlus.adapterState.first;
          if (state == BluetoothAdapterState.on) return true;
        } catch (_) {}
      }
    }
    return false;
  }

  @override
  Future<bool> hasPermissions() async {
    // TODO: Implement per-adapter permission checking.
    return true;
  }

  @override
  Future<bool> requestPermissions() async {
    // TODO: Implement per-adapter permission requesting.
    return true;
  }

  // --- Scanning ---

  @override
  Stream<List<Device>> scanDevices() {
    final controller = StreamController<List<Device>>.broadcast();
    // For now, return cached devices.
    controller.add(_devices.values.toList());
    return controller.stream;
  }

  @override
  Future<void> stopScan() async {
    // TODO: Implement scan stopping per adapter.
  }

  // --- Connection ---

  @override
  Stream<DeviceConnectionState> connectDevice(String deviceId) {
    final device = _devices[deviceId];
    if (device == null) {
      return Stream.error(Exception('Device not found: $deviceId'));
    }

    final adapter = _getAdapter(device);
    if (adapter == null) {
      return Stream.error(Exception('No adapter for device: $deviceId'));
    }

    final controller = StreamController<DeviceConnectionState>.broadcast();
    _connectionControllers[deviceId] = controller;

    adapter
        .connect(device)
        .listen(
          (state) {
            if (!controller.isClosed) controller.add(state);
            final previous = _devices[deviceId]?.connectionState;
            _devices[deviceId] = device.copyWith(connectionState: state);
            if (previous != state) {
              _eventsController.add(
                DeviceEvent.connectionChanged(
                  deviceId: deviceId,
                  connected: state == DeviceConnectionState.connected,
                ),
              );
            }
          },
          onError: (e) {
            controller.addError(e);
          },
          onDone: () {
            controller.close();
            _connectionControllers.remove(deviceId);
          },
        );

    return controller.stream;
  }

  @override
  Future<void> disconnectDevice(String deviceId) async {
    final device = _devices[deviceId];
    if (device == null) return;

    final adapter = _getAdapter(device);
    if (adapter != null) {
      await adapter.disconnect(device);
    }
    // The adapter's connection stream usually reports the disconnect during
    // the await above (and the registry listener emits the event). Only emit
    // here when the adapter stayed silent — never twice for one disconnect.
    if (_devices[deviceId]?.connectionState !=
        DeviceConnectionState.disconnected) {
      _eventsController.add(
        DeviceEvent.connectionChanged(deviceId: deviceId, connected: false),
      );
    }
    _devices[deviceId] = device.copyWith(
      connectionState: DeviceConnectionState.disconnected,
    );

    await _connectionControllers[deviceId]?.close();
    _connectionControllers.remove(deviceId);
  }

  // --- Commands ---

  @override
  Future<CommandResult> sendCommand(
    String deviceId,
    DeviceCommand command,
  ) async {
    final device = _devices[deviceId];
    if (device == null) {
      return CommandResult.failure(
        'device_not_found',
        'Device not found: $deviceId',
      );
    }

    final adapter = _getAdapter(device);
    if (adapter == null) {
      return CommandResult.failure(
        'no_adapter',
        'No adapter for device: $deviceId',
      );
    }

    if (device.connectionState != DeviceConnectionState.connected) {
      return CommandResult.failure(
        'not_connected',
        'Device not connected: $deviceId',
      );
    }

    final result = await adapter.sendCommand(device, command);
    if (!result.success) {
      _eventsController.add(
        DeviceEvent(
          deviceId: deviceId,
          kind: DeviceEventKind.error,
          timestamp: DateTime.now(),
          data: {
            'command': command.type,
            'error': result.error,
            'message': result.message,
          },
        ),
      );
    }
    return result;
  }

  @override
  Future<DeviceState> readState(String deviceId) async {
    final device = _devices[deviceId];
    if (device == null) {
      throw Exception('Device not found: $deviceId');
    }

    final adapter = _getAdapter(device);
    if (adapter == null) {
      throw Exception('No adapter for device: $deviceId');
    }

    return adapter.readState(device);
  }

  @override
  Stream<DeviceConnectionState> connectionState(String deviceId) {
    final controller = _connectionControllers[deviceId];
    if (controller != null) {
      return controller.stream;
    }
    final device = _devices[deviceId];
    return Stream.value(
      device?.connectionState ?? DeviceConnectionState.disconnected,
    );
  }

  /// Adds a discovered device to the in-memory registry (does not persist).
  void addDiscoveredDevice(Device device) {
    _devices[device.id] = device;
  }

  /// Gets the adapter for a specific device type.
  DeviceAdapter? getAdapterForType(String deviceTypeId) {
    for (final adapter in _adapters) {
      if (adapter.deviceTypeId == deviceTypeId) {
        return adapter;
      }
    }
    return null;
  }
}
