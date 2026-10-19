// SPDX-License-Identifier: Apache-2.0

import 'package:starlight/domain/entities/device_capability.dart';
import 'package:starlight/domain/entities/rgb_color.dart';

/// Parsed WLED "state" object.
///
/// Supports both the modern segment-based layout (WLED 0.14+) and the legacy
/// flat layout (older firmware). Only the fields StarLight controls are
/// extracted; everything else is deliberately ignored so a firmware can
/// add fields without breaking the app.
class WledLightState {
  final bool on;

  /// 0-255 as reported by the device. When the light is off, WLED reports
  /// the last used brightness, not 0.
  final int brightness;
  final RGBColor? color;

  /// Effect id (index into the device-reported effect list) or null.
  final int? effectId;

  /// Effect speed 0-255 or null.
  final int? speed;

  /// Palette id (index into the device-reported palette list) or null.
  /// Only present on segment-based firmware.
  final int? paletteId;

  /// Color temperature when the device reports one (relative 0-255 or
  /// Kelvin 1000-16000); null when absent.
  final int? colorTemperature;

  /// True when the device uses the 0.14+ segment object layout.
  final bool segmentBased;

  const WledLightState({
    required this.on,
    required this.brightness,
    this.color,
    this.effectId,
    this.speed,
    this.paletteId,
    this.colorTemperature,
    required this.segmentBased,
  });

  factory WledLightState.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic>? seg = _firstSegment(json['seg']);
    final bool segmentBased = seg != null;

    RGBColor? color;
    int? effectId;
    int? speed;
    int? paletteId;
    int? colorTemperature;

    if (segmentBased) {
      final segment = seg;
      color = _colorFromEntry(segment['col']);
      effectId = _asInt(segment['fx']);
      speed = _asInt(segment['sx']);
      paletteId = _asInt(segment['pal']);
      colorTemperature = _asInt(segment['cct']);
    } else {
      color = _colorFromEntry(json['c']);
      effectId = _asInt(json['fx']);
      speed = _asInt(json['sx']);
    }

    return WledLightState(
      on: _asBool(json['on']) ?? false,
      brightness: _asInt(json['bri']) ?? 0,
      color: color,
      effectId: effectId,
      speed: speed,
      paletteId: paletteId,
      colorTemperature: colorTemperature,
      segmentBased: segmentBased,
    );
  }

  /// Accepts `seg` as a single segment object or an array of segments and
  /// returns the first one (segment id 0 / the segment WLED reports).
  static Map<String, dynamic>? _firstSegment(Object? seg) {
    if (seg is Map<String, dynamic>) return seg;
    if (seg is Map) return Map<String, dynamic>.from(seg);
    if (seg is List && seg.isNotEmpty) {
      final first = seg.first;
      if (first is Map<String, dynamic>) return first;
      if (first is Map) return Map<String, dynamic>.from(first);
    }
    return null;
  }

  /// A color entry is a list of 3 or 4 integers (RGB or RGBW); extra
  /// channels (white) are dropped — StarLight exposes RGB only.
  /// Accepts either a single color array [r, g, b, w?] or an array of
  /// color arrays [[r, g, b, w?], ...] and uses the first entry.
  static RGBColor? _colorFromEntry(Object? entry) {
    if (entry is! List || entry.isEmpty) return null;

    // If first element is also a list, it's an array of colors; use the first.
    final firstColor = entry[0] is List ? entry[0] as List : entry;
    final r = _asInt(firstColor[0]);
    final g = _asInt(firstColor.length > 1 ? firstColor[1] : null);
    final b = _asInt(firstColor.length > 2 ? firstColor[2] : null);
    if (r == null || g == null || b == null) return null;
    return RGBColor(r, g, b);
  }

  static int? _asInt(Object? value) {
    if (value is int) return value;
    if (value is double) return value.round();
    if (value is String) return int.tryParse(value);
    return null;
  }

  static bool? _asBool(Object? value) {
    if (value is bool) return value;
    if (value is String) return value == 'true' || value == 't';
    if (value is num) return value != 0;
    return null;
  }
}

/// Parsed WLED "info" object (read-only device facts).
class WledInfo {
  final String version;
  final String? name;
  final String? mac;
  final int? ledCount;
  final int? effectCount;
  final int? paletteCount;

  /// `info.leds.lc` bitmask: bit 0 RGB, bit 1 white channel, bit 2 CCT.
  /// Null on legacy firmware (no capability bitmask).
  final int? lightCapabilities;

  const WledInfo({
    required this.version,
    this.name,
    this.mac,
    this.ledCount,
    this.effectCount,
    this.paletteCount,
    this.lightCapabilities,
  });

  factory WledInfo.fromJson(Map<String, dynamic> json) {
    final leds = _map(json['leds']);
    return WledInfo(
      version: (json['ver'] as String?) ?? 'unknown',
      name: json['name'] as String?,
      mac: json['mac'] as String?,
      ledCount: _int(leds?['count']),
      effectCount: _int(json['fxcount']),
      paletteCount: _int(json['palcount']),
      lightCapabilities: _int(leds?['lc']),
    );
  }

  static Map<String, dynamic>? _map(Object? value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return null;
  }

  static int? _int(Object? value) {
    if (value is int) return value;
    if (value is double) return value.round();
    return null;
  }
}

/// A full parsed `/json` response: state + info + effect/palette names.
///
/// [effects] and [palettes] are the complete device-reported lists; the
/// list index IS the firmware id. Reserved slots (name `RSVD` or `-`) are
/// kept in the list so indexes stay correct and hidden in the UI instead.
class WledSnapshot {
  final WledLightState state;
  final WledInfo info;
  final List<String> effects;
  final List<String> palettes;

  const WledSnapshot({
    required this.state,
    required this.info,
    required this.effects,
    required this.palettes,
  });

  factory WledSnapshot.fromJson(Map<String, dynamic> json) {
    final stateJson = json['state'] is Map ? _stringMap(json['state']) : json;
    final infoJson = json['info'] is Map
        ? _stringMap(json['info'])
        : <String, dynamic>{};
    return WledSnapshot(
      state: WledLightState.fromJson(stateJson),
      info: WledInfo.fromJson(infoJson),
      effects: _names(json, 'effects', 'eff'),
      palettes: _names(json, 'palettes', 'pal'),
    );
  }

  static Map<String, dynamic> _stringMap(Object value) =>
      value is Map<String, dynamic>
      ? value
      : Map<String, dynamic>.from(value as Map);

  /// Effect/palette names live under `effects`/`palettes` on current
  /// firmware and `eff`/`pal` on older builds.
  static List<String> _names(
    Map<String, dynamic> json,
    String currentKey,
    String legacyKey,
  ) {
    final raw = json[currentKey] ?? json[legacyKey];
    if (raw is! List) return const [];
    return raw.map((e) => e.toString()).toList();
  }
}

/// Capabilities derivable from a live [WledSnapshot].
///
/// Only what the device actually reported becomes a capability; nothing is
/// assumed. `colorTemperature` requires the 0.14+ `leds.lc` capability bit,
/// so legacy firmware never advertises it.
class WledCapabilities {
  WledCapabilities._();

  static List<DeviceCapability> fromSnapshot(WledSnapshot snapshot) {
    final caps = <DeviceCapability>[
      DeviceCapability.power,
      DeviceCapability.brightness,
    ];

    final lc = snapshot.info.lightCapabilities;
    if (snapshot.state.segmentBased && lc != null) {
      // Bit 0: RGB color supported by this setup.
      if ((lc & 1) != 0) caps.add(DeviceCapability.color);
      // Bit 2: color temperature supported by this setup.
      if ((lc & 4) != 0) caps.add(DeviceCapability.colorTemperature);
    } else {
      // Legacy firmware has no capability bitmask: RGB is the core WLED
      // mode, so color is safe to advertise.
      caps.add(DeviceCapability.color);
    }

    if (snapshot.effects.isNotEmpty) {
      caps.add(DeviceCapability.effect);
      caps.add(DeviceCapability.speed);
    }
    if (snapshot.palettes.isNotEmpty) {
      caps.add(DeviceCapability.palette);
    }
    return caps;
  }
}
