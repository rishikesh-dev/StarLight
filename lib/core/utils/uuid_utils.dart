// SPDX-License-Identifier: Apache-2.0

/// Helpers for comparing BLE UUIDs, which can be written in several
/// equivalent representations:
///
/// - 16-bit:  "fff0"
/// - 32-bit:  "0000fff0"
/// - 128-bit: "0000fff0-0000-1000-8000-00805f9b34fb"
///
/// `flutter_blue_plus`'s `Guid.toString()` returns the *shortest* form
/// (e.g. "fff0" for a service discovered on Linux/Android), while the
/// protocol constants are written out as full 128-bit UUIDs. Comparing
/// those strings directly never matches, so both sides are normalized to
/// the canonical 128-bit form first.
class UuidUtils {
  UuidUtils._();

  /// The suffix shared by every UUID derived from the Bluetooth base UUID:
  /// `xxxxxxxx-0000-1000-8000-00805f9b34fb`.
  static const String _baseSuffix = '00001000800000805f9b34fb';

  /// Normalizes [uuid] to an undashed, lowercase 128-bit hex string.
  ///
  /// Short (16/32-bit) Bluetooth UUIDs are expanded against the Bluetooth
  /// base UUID. Anything else is returned with separators removed and
  /// lowercased, so it is still comparable.
  static String normalize(String uuid) {
    final hex = uuid.replaceAll('-', '').toLowerCase();
    switch (hex.length) {
      case 4:
        // 16-bit: fff0 -> 0000fff0-...
        return '0000$hex$_baseSuffix';
      case 8:
        // 32-bit: 0000fff0 -> 0000fff0-...
        return '$hex$_baseSuffix';
      default:
        return hex;
    }
  }

  /// Returns true when [a] and [b] refer to the same UUID, regardless of the
  /// representation each one uses.
  static bool matches(String a, String b) => normalize(a) == normalize(b);

  /// Whether [uuid] is a well-formed Bluetooth UUID.
  ///
  /// Accepts the three representations a user may type into a profile editor:
  /// 16-bit (`"fff0"`), 32-bit (`"0000fff0"`) and the full 128-bit form
  /// (`"0000fff0-0000-1000-8000-00805f9b34fb"`). Leading/trailing whitespace is
  /// ignored; grouping hyphens are allowed anywhere in the 128-bit form.
  /// Returns false for empty input, non-hex characters or any other length.
  static bool isValid(String uuid) {
    final trimmed = uuid.trim();
    if (trimmed.isEmpty) return false;
    final hex = trimmed.replaceAll('-', '');
    if (!RegExp(r'^[0-9a-fA-F]+$').hasMatch(hex)) return false;
    return hex.length == 4 || hex.length == 8 || hex.length == 32;
  }
}
