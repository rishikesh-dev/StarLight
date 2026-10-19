// SPDX-License-Identifier: Apache-2.0

import 'package:starlight/core/ble/ble_constants.dart';
import 'package:starlight/core/utils/hex_utils.dart';
import 'package:starlight/domain/entities/device_state_update.dart';

/// Decodes MR Star BLE notify packets into structured data.
///
/// Deliberately thin, matching the Python [core/app/protocol/decoder.py]:
/// structural validation only (start/end bytes, length) -- no CRC, no
/// semantic claims beyond what the packet layout guarantees.
class ProtocolDecoder {
  ProtocolDecoder._();

  /// Decodes a notify packet into a [DecodedPacket].
  ///
  /// Returns null if the packet is malformed (too short, bad markers).
  static DecodedPacket? decode(List<int> bytes) {
    if (bytes.length < 5) return null;

    final start = bytes[0];
    final end = bytes[bytes.length - 1];

    if (start != BleConstants.startByte) {
      return null;
    }
    if (end != BleConstants.endByte) {
      return null;
    }

    final opcode = bytes[1];
    final length = bytes[2];
    final data = bytes.sublist(3, 3 + length);

    return DecodedPacket(
      opcode: opcode,
      length: length,
      data: data,
      rawBytes: bytes,
    );
  }

  /// Parses a decoded packet into a structured [DeviceStateUpdate].
  static DeviceStateUpdate? parseState(DecodedPacket packet) {
    switch (packet.opcode) {
      case 0x02: // Line order response
        return null;
      case 0x04: // Color response
        if (packet.data.length >= 6) {
          final r = packet.data[2];
          final g = packet.data[3];
          final b = packet.data[4];
          return DeviceStateUpdate(
            type: StateUpdateType.color,
            value: {'red': r, 'green': g, 'blue': b},
          );
        }
        break;
      case 0x05: // Brightness response
        if (packet.data.length >= 2) {
          final brightness = (packet.data[0] << 8) | packet.data[1];
          return DeviceStateUpdate(
            type: StateUpdateType.brightness,
            value: brightness,
          );
        }
        break;
      case 0x01: // Power state response
        if (packet.data.isNotEmpty) {
          final isOn = packet.data[0] != 0;
          return DeviceStateUpdate(type: StateUpdateType.power, value: isOn);
        }
        break;
      case 0x0F: // MIC toggle response
        if (packet.data.isNotEmpty) {
          return DeviceStateUpdate(
            type: StateUpdateType.mic,
            value: packet.data[0] != 0,
          );
        }
        break;
      default:
        return null;
    }
    return null;
  }
}

/// Result of decoding a notify packet.
class DecodedPacket {
  final int opcode;
  final int length;
  final List<int> data;
  final List<int> rawBytes;

  const DecodedPacket({
    required this.opcode,
    required this.length,
    required this.data,
    required this.rawBytes,
  });

  @override
  String toString() =>
      'DecodedPacket(opcode: ${HexUtils.toHexString([opcode])}, '
      'length: $length, data: ${HexUtils.toHexString(data)})';
}
