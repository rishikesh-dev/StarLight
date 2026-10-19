// SPDX-License-Identifier: Apache-2.0

import 'package:starlight/domain/entities/device_command.dart';
import 'package:starlight/domain/entities/mqtt_config.dart';
import 'package:starlight/domain/entities/rgb_color.dart';

/// Adapter for MQTT-based devices (WLED, etc.).
///
/// WLED MQTT interface specification:
/// https://kno.wled.ge/interfaces/mqtt/
class MqttAdapter {
  final MqttConfig config;

  MqttAdapter({required this.config});

  /// Parses a topic payload into a command.
  ///
  /// WLED MQTT topics:
  /// - [clientID]/api : Send an API call (using the HTTP API or JSON API syntax)
  /// - [clientID]/col : Send color as HEX (#WWRRGGBB or #RRGGBB) or 32bit DEC
  /// - [clientID]/g  : Send brightness as ASCII number 0-255 or the strings "ON", "OFF", "T" (toggle)
  DeviceCommand? parsePayload(String topic, String payload) {
    final parts = topic.split('/');
    if (parts.length < 2) return null;
    final suffix = parts[1];

    switch (suffix) {
      case 'g': // Brightness/power/toggle
        if (payload.toUpperCase() == 'ON') {
          return DeviceCommand.power(true);
        } else if (payload.toUpperCase() == 'OFF') {
          return DeviceCommand.power(false);
        } else if (payload.toUpperCase() == 'T') {
          return DeviceCommand.power(
            false,
          ); // Toggle - we don't know current state
        } else {
          try {
            final brightness = int.parse(payload);
            if (brightness >= 0 && brightness <= 255) {
              return DeviceCommand.brightness(brightness);
            }
          } catch (_) {}
        }
        return null;

      case 'col': // Color
        String hex = payload;
        if (hex.startsWith('#')) {
          hex = hex.substring(1);
        }
        if (hex.startsWith('H') || hex.startsWith('h')) {
          hex = hex.substring(1);
        }
        if (hex.length == 8) {
          // #WWRRGGBB format
          final r = int.parse(hex.substring(2, 4), radix: 16);
          final g = int.parse(hex.substring(4, 6), radix: 16);
          final b = int.parse(hex.substring(6, 8), radix: 16);
          return DeviceCommand.color(r, g, b);
        } else if (hex.length == 6) {
          // #RRGGBB format
          final r = int.parse(hex.substring(0, 2), radix: 16);
          final g = int.parse(hex.substring(2, 4), radix: 16);
          final b = int.parse(hex.substring(4, 6), radix: 16);
          return DeviceCommand.color(r, g, b);
        } else if (hex.length == 1) {
          // Single digit color (e.g., white)
          return DeviceCommand.color(
            int.parse(hex) * 0x11,
            int.parse(hex) * 0x11,
            int.parse(hex) * 0x11,
          );
        }
        return null;

      case 'api': // API call - for now treat as custom command
        // Parse FX=73, BR=128, etc. formats
        if (payload.startsWith('FX=')) {
          try {
            final effectId = int.parse(payload.substring(3));
            return DeviceCommand.effect('Unknown', params: {'id': effectId});
          } catch (_) {}
        } else if (payload.startsWith('BR=')) {
          try {
            final brightness = int.parse(payload.substring(3));
            return DeviceCommand.brightness(brightness);
          } catch (_) {}
        }
        return null;

      default:
        return null;
    }
  }

  /// Generates a state topic for publishing device state.
  ///
  /// WLED publishes to:
  /// - [clientID]/g : Contains current brightness as ASCII number 0-255
  /// - [clientID]/c : Contains current color as HEX (#RRGGBB if white is 0, else #WWRRGGBB)
  /// - [clientID]/v : Contains XML API response (same as HTTP API)
  static String getStateTopic(String clientId, String suffix) {
    return '$clientId/$suffix';
  }

  /// Converts a NetworkDevice state to an MQTT color payload.
  String colorToMqttPayload(RGBColor color) {
    // WLED expects #RRGGBB format
    final hex = color.toHexStr();
    return hex;
  }

  /// Converts a NetworkDevice brightness to an MQTT payload.
  String brightnessToMqttPayload(int brightness) {
    return brightness.toString();
  }

  /// Converts a command to a WLED MQTT color payload.
  String commandColorToMqttPayload(DeviceCommand command) {
    if (command.type == 'color') {
      final red = command.parameters['red'] as int;
      final green = command.parameters['green'] as int;
      final blue = command.parameters['blue'] as int;
      return RGBColor(red, green, blue).toHexStr();
    }
    return '';
  }

  /// Converts a command to a WLED MQTT brightness payload.
  String commandBrightnessToMqttPayload(DeviceCommand command) {
    if (command.type == 'brightness') {
      return command.parameters['value'].toString();
    }
    return '';
  }
}
