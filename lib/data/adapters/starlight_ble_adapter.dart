// SPDX-License-Identifier: Apache-2.0

import 'dart:typed_data';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:starlight/core/ble/protocol_encoder.dart';
import 'package:starlight/core/utils/app_logger.dart';
import 'package:starlight/core/utils/hex_utils.dart';
import 'package:starlight/data/datasources/ble_datasource.dart';
import 'package:starlight/domain/adapters/device_adapter.dart';
import 'package:starlight/domain/entities/connection_state.dart';
import 'package:starlight/domain/entities/device.dart';
import 'package:starlight/domain/entities/device_capability.dart';
import 'package:starlight/domain/entities/device_state.dart';
import 'package:starlight/domain/entities/effect.dart';
import 'package:starlight/domain/entities/device_type.dart';
import 'package:starlight/domain/repositories/device_repository.dart';

/// BLE adapter for StarLight RGB LED controllers (MR Star GATT--DEMO).
///
/// This adapter is a *translation* layer only: it converts universal
/// [DeviceCommand]s into MR Star protocol packets. The physical BLE session
/// (connect, GATT discovery, write queue, notifications) is owned exclusively
/// by the shared [BleDataSource] instance passed in at construction, so there
/// is exactly one connection owner per peripheral in the application.
class StarLightBleAdapter implements DeviceAdapter {
  final BleDataSource _dataSource;

  /// [dataSource] must be the same instance used by `BleRepositoryImpl` so
  /// both the legacy light-control path and the universal device registry
  /// share one BLE session.
  StarLightBleAdapter(this._dataSource);

  @override
  String get deviceTypeId => 'starlight';

  @override
  String get transport => 'ble';

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
    // Only connected/disconnected are meaningful here; the deprecated
    // connecting/disconnecting raw states collapse into `disconnected`.
    return _dataSource.connectToDevice(device.address).map((state) {
      return state == BluetoothConnectionState.connected
          ? DeviceConnectionState.connected
          : DeviceConnectionState.disconnected;
    });
  }

  @override
  Future<void> disconnect(Device device) async {
    AppLog.info('StarLightBleAdapter: disconnecting from ${device.id}');
    await _dataSource.disconnect();
  }

  @override
  Future<CommandResult> sendCommand(
    Device device,
    DeviceCommand command,
  ) async {
    final Uint8List? packet;
    try {
      packet = _encode(command);
    } on ArgumentError catch (e) {
      return CommandResult.failure(
        'invalid_parameter',
        e.message?.toString() ?? 'Invalid command parameter.',
      );
    }
    if (packet == null) {
      return CommandResult.failure(
        'unsupported_command',
        'Command type ${command.type} not supported by StarLight',
      );
    }

    AppLog.debug(
      'StarLightBleAdapter: ${command.type} → ${HexUtils.toHexString(packet)}',
    );
    try {
      await _dataSource.writeCommand(packet);
      return CommandResult.ok();
    } on Exception catch (e) {
      AppLog.error('StarLightBleAdapter: command failed', e);
      return CommandResult.failure(_errorCode(e), e.toString());
    }
  }

  /// Maps a transport exception onto the shared error contract.
  String _errorCode(Object e) {
    final name = e.runtimeType.toString();
    return switch (name) {
      'DisconnectedException' => 'not_connected',
      'CharacteristicNotFoundException' => 'characteristic_not_found',
      'ServiceNotFoundException' => 'service_not_found',
      'ConnectionTimeoutException' => 'connection_timeout',
      _ => 'transport_error',
    };
  }

  Uint8List? _encode(DeviceCommand command) {
    switch (command.type) {
      case 'power':
        final on = command.parameters['on'] as bool;
        return on ? ProtocolEncoder.powerOn() : ProtocolEncoder.powerOff();
      case 'brightness':
        final value = command.parameters['value'] as int;
        return ProtocolEncoder.brightness(value);
      case 'color':
        final red = command.parameters['red'] as int;
        final green = command.parameters['green'] as int;
        final blue = command.parameters['blue'] as int;
        return ProtocolEncoder.colorFromRGB(red, green, blue);
      case 'speed':
        final value = command.parameters['value'] as int;
        return ProtocolEncoder.setSpeed(value);
      case 'effect':
        // Resolve through the canonical catalogue (single authoritative
        // mapping). The old local name→id table here disagreed with the
        // encoder's (e.g. 'solid' → 1 vs 0) and used names that were not real
        // controller modes; it has been removed.
        final name = command.parameters['name'];
        if (name is! String || name.isEmpty) return null;
        final effect = effectByCommandName(name);
        final modeId = effect?.protocolModeId;
        return modeId == null ? null : ProtocolEncoder.setMode(modeId);
      default:
        return null;
    }
  }

  @override
  Future<DeviceState> readState(Device device) async {
    // MR Star strips do not report state via notifications; the last known
    // state is the authoritative value.
    return device.state;
  }

  @override
  bool canHandle(Device device) {
    return device.type == DeviceType.light &&
        device.transport == 'ble' &&
        (device.manufacturer == 'MR Star' ||
            device.metadata['isMrStar'] == true);
  }
}
