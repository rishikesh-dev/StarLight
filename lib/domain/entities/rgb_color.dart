// SPDX-License-Identifier: Apache-2.0

import 'package:equatable/equatable.dart';

/// Represents an RGB color (0-255 per channel).
class RGBColor extends Equatable {
  final int red;
  final int green;
  final int blue;

  const RGBColor(this.red, this.green, this.blue);

  /// Creates an [RGBColor] from a hex integer (e.g., 0xFF5733).
  factory RGBColor.fromHex(int hex) {
    return RGBColor((hex >> 16) & 0xFF, (hex >> 8) & 0xFF, hex & 0xFF);
  }

  /// Creates an [RGBColor] from a hex string (e.g., "FF5733" or "#FF5733").
  factory RGBColor.fromHexStr(String hex) {
    var h = hex.replaceAll('#', '');
    if (h.length == 6) {
      return RGBColor(
        int.parse(h.substring(0, 2), radix: 16),
        int.parse(h.substring(2, 4), radix: 16),
        int.parse(h.substring(4, 6), radix: 16),
      );
    }
    if (h.length == 3) {
      return RGBColor(
        int.parse(h[0] * 2, radix: 16),
        int.parse(h[1] * 2, radix: 16),
        int.parse(h[2] * 2, radix: 16),
      );
    }
    return const RGBColor(0, 0, 0);
  }

  /// Converts to a hex integer (e.g., 0xFF5733).
  int toHexInt() {
    return ((red & 0xFF) << 16) | ((green & 0xFF) << 8) | (blue & 0xFF);
  }

  /// Converts to a hex string "#RRGGBB".
  String toHexStr() {
    return '#${red.toRadixString(16).padLeft(2, '0').toUpperCase()}'
        '${green.toRadixString(16).padLeft(2, '0').toUpperCase()}'
        '${blue.toRadixString(16).padLeft(2, '0').toUpperCase()}';
  }

  @override
  List<Object?> get props => [red, green, blue];
}
