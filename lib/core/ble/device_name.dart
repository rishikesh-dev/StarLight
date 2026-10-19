// SPDX-License-Identifier: Apache-2.0

/// Utilities for deriving a safe, human-readable display name from raw BLE
/// advertisement data.
///
/// Advertisement payloads frequently carry binary data (service data,
/// manufacturer data) rather than a name. Rendering those bytes directly
/// produced unbounded device names and horizontal overflow in the device list,
/// so binary payloads are only used when they decode to a short, printable
/// string. Otherwise a stable fallback is returned.
library;

import 'dart:convert';

/// Stable fallback used when a device advertises no usable name.
const String kUnknownDeviceName = 'Unknown BLE device';

/// Upper bound on a trusted advertised name. Real device names are short;
/// anything longer is almost certainly binary data mistaken for a name.
const int _maxNameLength = 64;

/// Returns the best display name for a discovered device.
///
/// Preference order: [platformName], then [advName], then the first
/// [serviceData] payload when it decodes to a printable string. Falls back to
/// [kUnknownDeviceName] when nothing usable is available.
String resolveDeviceDisplayName({
  String? platformName,
  String? advName,
  List<int>? serviceData,
}) {
  final candidates = <String?>[
    platformName,
    advName,
    if (serviceData != null && serviceData.isNotEmpty)
      _decodePrintable(serviceData),
  ];
  for (final candidate in candidates) {
    final cleaned = _clean(candidate);
    if (cleaned != null) return cleaned;
  }
  return kUnknownDeviceName;
}

/// Trims and validates a candidate name. Returns `null` when it is empty,
/// too long, or contains control characters (i.e. it is really binary data).
String? _clean(String? candidate) {
  if (candidate == null) return null;
  final trimmed = candidate.trim();
  if (trimmed.isEmpty) return null;
  if (trimmed.length > _maxNameLength) return null;
  for (final unit in trimmed.codeUnits) {
    if (unit < 0x20 || unit == 0x7f) return null;
  }
  return trimmed;
}

/// Attempts to decode [bytes] as UTF-8, returning `null` when the payload is
/// malformed or contains no printable content.
String? _decodePrintable(List<int> bytes) {
  try {
    return utf8.decode(bytes);
  } on FormatException {
    return null;
  }
}
