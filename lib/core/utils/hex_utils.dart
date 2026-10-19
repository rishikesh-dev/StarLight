// SPDX-License-Identifier: Apache-2.0

/// Utility for converting byte arrays to hex strings.
class HexUtils {
  /// Converts a list of bytes to a space-separated hex string.
  /// e.g., [0xBC, 0x01, 0x01, 0x00, 0x55] -> "BC 01 01 00 55"
  static String toHexString(List<int> bytes) {
    if (bytes.isEmpty) return '';
    return bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
        .join(' ');
  }
}
