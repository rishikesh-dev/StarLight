// SPDX-License-Identifier: Apache-2.0

import 'package:starlight/domain/entities/device_capability.dart';
import 'package:starlight/domain/entities/device_profile.dart';
import 'package:starlight/domain/entities/notification_format.dart';
import 'package:starlight/domain/entities/profile_command.dart';

/// Thrown when a stored profile document is malformed or uses a schema this
/// build cannot understand. The datasource skips such entries instead of
/// turning them into a valid-looking profile.
class ProfileFormatException implements Exception {
  final String message;

  ProfileFormatException(this.message);

  @override
  String toString() => 'ProfileFormatException: $message';
}

/// JSON (de)serialisation for [DeviceProfile].
///
/// The document carries an explicit `schema` version. A document from a newer
/// schema is rejected rather than partially understood; a document from an
/// older schema is migrated when a migration exists, otherwise rejected.
class DeviceProfileModel {
  static const int schemaVersion = kProfileSchemaVersion;

  // --- encode -------------------------------------------------------------

  static Map<String, dynamic> toJson(DeviceProfile profile) {
    final commands = profile.commands;
    return {
      'schema': schemaVersion,
      'id': profile.id,
      'name': profile.name,
      'protocol': profile.protocol.id,
      'serviceUuid': profile.serviceUuid,
      'writeCharacteristicUuid': profile.writeCharacteristicUuid,
      'notifyCharacteristicUuid': profile.notifyCharacteristicUuid,
      'writeMode': profile.writeMode.id,
      'capabilities': profile.capabilities.map((c) => c.name).toList()..sort(),
      'commands': {
        'powerOn': commands.powerOn?.toText(),
        'powerOff': commands.powerOff?.toText(),
        'brightness': commands.brightness?.toText(),
        'color': commands.color?.toText(),
        'brightnessMin': commands.brightnessMin,
        'brightnessMax': commands.brightnessMax,
      },
      'notifications': profile.notifications == null
          ? null
          : {
              'rules': [
                for (final rule in profile.notifications!.rules)
                  {
                    'target': rule.target.id,
                    'byteOffset': rule.byteOffset,
                    'width': rule.width.id,
                    'scale': rule.scale,
                    'offset': rule.offset,
                    'onThreshold': rule.onThreshold,
                  },
              ],
            },
    };
  }

  // --- decode -------------------------------------------------------------

  /// Parses [json] into a [DeviceProfile].
  ///
  /// Throws [ProfileFormatException] for anything malformed or unsupported.
  static DeviceProfile fromJson(Map<String, dynamic> json) {
    final schema = json['schema'];
    if (schema is! int) {
      throw ProfileFormatException('missing schema version');
    }
    if (schema > schemaVersion) {
      throw ProfileFormatException(
        'schema $schema is newer than supported ($schemaVersion)',
      );
    }
    if (schema < schemaVersion) {
      throw ProfileFormatException('schema $schema has no migration');
    }

    final id = _string(json, 'id');
    final name = _string(json, 'name');

    final protocolId = _string(json, 'protocol');
    final protocol = ProfileProtocol.fromId(protocolId);
    if (protocol == null) {
      throw ProfileFormatException('unknown protocol "$protocolId"');
    }

    final serviceUuid = _string(json, 'serviceUuid');
    final writeChar = _string(json, 'writeCharacteristicUuid');
    final notifyRaw = json['notifyCharacteristicUuid'];
    final notifyChar = notifyRaw is String && notifyRaw.trim().isNotEmpty
        ? notifyRaw
        : null;

    final capabilitiesRaw = json['capabilities'];
    if (capabilitiesRaw is! List) {
      throw ProfileFormatException('capabilities must be a list');
    }
    final capabilities = <DeviceCapability>{};
    for (final c in capabilitiesRaw) {
      if (c is! String) {
        throw ProfileFormatException('invalid capability entry');
      }
      final match = DeviceCapability.values.where((v) => v.name == c);
      if (match.isEmpty) {
        throw ProfileFormatException('unknown capability "$c"');
      }
      capabilities.add(match.first);
    }

    final commands = _commandsFromJson(json['commands']);

    final notifications = _notificationsFromJson(json['notifications']);

    return DeviceProfile(
      id: id,
      name: name,
      protocol: protocol,
      serviceUuid: serviceUuid,
      writeCharacteristicUuid: writeChar,
      notifyCharacteristicUuid: notifyChar,
      writeMode: GattWriteMode.fromId(
        json['writeMode'] is String ? json['writeMode'] as String : null,
      ),
      commands: commands,
      notifications: notifications,
      capabilities: capabilities,
      schemaVersion: schema,
    );
  }

  static GattCommandSet _commandsFromJson(dynamic raw) {
    if (raw == null) return const GattCommandSet();
    if (raw is! Map) {
      throw ProfileFormatException('commands must be an object');
    }
    CommandTemplate? parseOrThrow(
      dynamic value,
      String label,
      Set<ProfileValue> allowed,
    ) {
      if (value == null) return null;
      if (value is! String || value.trim().isEmpty) {
        throw ProfileFormatException('$label must be a non-empty string');
      }
      final result = CommandTemplate.parse(value, allowed: allowed);
      final template = result.template;
      if (template == null) {
        throw ProfileFormatException('$label: ${result.error}');
      }
      return template;
    }

    return GattCommandSet(
      powerOn: parseOrThrow(raw['powerOn'], 'powerOn', const {
        ProfileValue.checksum,
      }),
      powerOff: parseOrThrow(raw['powerOff'], 'powerOff', const {
        ProfileValue.checksum,
      }),
      brightness: parseOrThrow(raw['brightness'], 'brightness', const {
        ProfileValue.brightness,
        ProfileValue.checksum,
      }),
      color: parseOrThrow(raw['color'], 'color', const {
        ProfileValue.red,
        ProfileValue.green,
        ProfileValue.blue,
        ProfileValue.checksum,
      }),
      brightnessMin: _int(raw['brightnessMin'], fallback: 0),
      brightnessMax: _int(raw['brightnessMax'], fallback: 255),
    );
  }

  static NotificationFormat? _notificationsFromJson(dynamic raw) {
    if (raw == null) return null;
    if (raw is! Map || raw['rules'] is! List) {
      throw ProfileFormatException('notifications must contain a rules list');
    }
    final rules = <NotificationRule>[];
    for (final r in raw['rules'] as List) {
      if (r is! Map) {
        throw ProfileFormatException('invalid notification rule');
      }
      final targetId = _string(r, 'target');
      final target = NotificationTarget.fromId(targetId);
      if (target == null) {
        throw ProfileFormatException('unknown notification target "$targetId"');
      }
      rules.add(
        NotificationRule(
          target: target,
          byteOffset: _int(r['byteOffset'], fallback: 0),
          width: NumericWidth.fromId(
            r['width'] is String ? r['width'] as String : null,
          ),
          scale: _double(r['scale'], fallback: 1),
          offset: _double(r['offset'], fallback: 0),
          onThreshold: _int(r['onThreshold'], fallback: 1),
        ),
      );
    }
    return NotificationFormat(rules);
  }

  static String _string(Map<dynamic, dynamic> map, String key) {
    final value = map[key];
    if (value is! String || value.trim().isEmpty) {
      throw ProfileFormatException('"$key" must be a non-empty string');
    }
    return value;
  }

  static int _int(dynamic value, {required int fallback}) =>
      value is int ? value : (value is num ? value.toInt() : fallback);

  static double _double(dynamic value, {required double fallback}) =>
      value is num ? value.toDouble() : fallback;
}
