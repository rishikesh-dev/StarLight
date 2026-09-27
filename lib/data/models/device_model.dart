import 'dart:convert';

import 'package:starlight/domain/entities/device.dart';
import 'package:starlight/domain/entities/device_capability.dart';
import 'package:starlight/domain/entities/device_state.dart';
import 'package:starlight/domain/entities/device_type.dart';
import 'package:starlight/domain/entities/light_state.dart';
import 'package:starlight/domain/entities/rgb_color.dart';

/// Serializable model for a persisted [Device].
///
/// Stored as JSON in SharedPreferences under [DeviceDataSource.devicesKey].
/// Only the fields required to restore the device on restart are persisted:
/// id, name, type, transport, address, capabilities, roomId, favorite,
/// last-known state, and connection metadata.
class DeviceModel {
  final String id;
  final String name;
  final String type;
  final String? manufacturer;
  final String? model;
  final String transport;
  final String address;
  final String? roomId;
  final List<String> capabilities;
  final bool favorite;
  final String? stateJson;
  final Map<String, dynamic> metadata;

  const DeviceModel({
    required this.id,
    required this.name,
    required this.type,
    this.manufacturer,
    this.model,
    required this.transport,
    required this.address,
    this.roomId,
    required this.capabilities,
    this.favorite = false,
    this.stateJson,
    this.metadata = const {},
  });

  /// Reconstructs a [Device] from this model.
  /// The connection state is always [DeviceConnectionState.disconnected]
  /// after a restart — the device is not assumed connected just because it
  /// was previously configured.
  Device toEntity() {
    final state = _restoreState();
    return Device(
      id: id,
      name: name,
      type: _parseType(type),
      manufacturer: manufacturer,
      model: model,
      transport: transport,
      address: address,
      roomId: roomId,
      capabilities: capabilities.map((c) => _parseCapability(c)).toList(),
      connectionState: DeviceConnectionState.disconnected,
      state: state,
      favorite: favorite,
      lastSeen: null,
      metadata: metadata,
    );
  }

  /// Builds a [DeviceModel] from a [Device].
  factory DeviceModel.fromEntity(Device device) {
    return DeviceModel(
      id: device.id,
      name: device.name,
      type: device.type.id,
      manufacturer: device.manufacturer,
      model: device.model,
      transport: device.transport,
      address: device.address,
      roomId: device.roomId,
      capabilities: device.capabilities.map((c) => c.id).toList(),
      favorite: device.favorite,
      stateJson: _stateToJson(device.state),
      metadata: device.metadata,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'type': type,
        'manufacturer': manufacturer,
        'model': model,
        'transport': transport,
        'address': address,
        'roomId': roomId,
        'capabilities': capabilities,
        'favorite': favorite,
        'stateJson': stateJson,
        'metadata': metadata,
      };

  factory DeviceModel.fromMap(Map<String, dynamic> map) {
    return DeviceModel(
      id: map['id'] as String,
      name: map['name'] as String,
      type: map['type'] as String,
      manufacturer: map['manufacturer'] as String?,
      model: map['model'] as String?,
      transport: map['transport'] as String,
      address: map['address'] as String,
      roomId: map['roomId'] as String?,
      capabilities: (map['capabilities'] as List<dynamic>)
          .map((e) => e as String)
          .toList(),
      favorite: (map['favorite'] as bool?) ?? false,
      stateJson: map['stateJson'] as String?,
      metadata: Map<String, dynamic>.from(map['metadata'] as Map? ?? {}),
    );
  }

  // --- Helpers ---

  static DeviceType _parseType(String id) {
    for (final t in DeviceType.values) {
      if (t.id == id) return t;
    }
    return DeviceType.other;
  }

  static DeviceCapability _parseCapability(String id) {
    for (final c in DeviceCapability.values) {
      if (c.id == id) return c;
    }
    // Unknown capability — fall back to power so the device remains usable.
    return DeviceCapability.power;
  }

  /// Restores the last-known device state from the persisted JSON.
  /// On restart the device is treated as disconnected; only the
  /// desired-state attributes (isOn, color, brightness, etc.) are kept.
  DeviceState _restoreState() {
    if (stateJson == null || stateJson!.isEmpty) {
      return LightState(isOn: false, isConnected: false);
    }
    try {
      final map = jsonDecode(stateJson!) as Map<String, dynamic>;
      final type = map['_type'] as String?;
      if (type == 'light') {
        return LightState(
          color: map['red'] != null || map['green'] != null || map['blue'] != null
              ? RGBColor(
                  (map['red'] as int?) ?? 0,
                  (map['green'] as int?) ?? 0,
                  (map['blue'] as int?) ?? 0,
                )
              : null,
          brightness: map['brightness'] as int?,
          colorTemperature: map['colorTemperature'] as int?,
          effect: map['effect'] as String?,
          speed: map['speed'] as int?,
          isOn: (map['isOn'] as bool?) ?? false,
          isConnected: false,
        );
      }
    } catch (_) {
      // Fall through to default.
    }
    return LightState(isOn: false, isConnected: false);
  }

  static String? _stateToJson(DeviceState state) {
    if (state is LightState) {
      final map = <String, dynamic>{
        '_type': 'light',
        'isOn': state.isOn,
        'brightness': state.brightness,
        'colorTemperature': state.colorTemperature,
        'effect': state.effect,
        'speed': state.speed,
      };
      final color = state.color;
      if (color != null) {
        map['red'] = color.red;
        map['green'] = color.green;
        map['blue'] = color.blue;
      }
      return jsonEncode(map);
    }
    return null;
  }
}