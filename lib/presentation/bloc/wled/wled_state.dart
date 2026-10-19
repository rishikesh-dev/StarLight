// SPDX-License-Identifier: Apache-2.0

import 'package:equatable/equatable.dart';

import 'package:starlight/domain/entities/device_capability.dart';
import 'package:starlight/domain/entities/rgb_color.dart';

/// Presentation state for the WLED integration.
///
/// [devices] is keyed by device id. Every device value only ever holds
/// *confirmed* state — what the device last reported — never a value that
/// was merely requested. While a command is in flight [WledDeviceInfo.busy]
/// is true and the confirmed values stay put.
class WledState extends Equatable {
  /// True while the initial persisted-device load is running.
  final bool loading;

  final Map<String, WledDeviceInfo> devices;

  /// Result of the most recent connectivity test from the Add Device flow,
  /// or null when none has run yet.
  final WledProbeInfo? probe;

  /// True while a connectivity test is in flight (Add Device flow).
  final bool probeInProgress;

  /// True while a device add (probe + register) is in flight.
  final bool addInProgress;

  /// Global error (persistence failure etc.); per-device errors live on
  /// [WledDeviceInfo.error].
  final String? lastError;

  const WledState({
    this.loading = false,
    this.devices = const {},
    this.probe,
    this.probeInProgress = false,
    this.addInProgress = false,
    this.lastError,
  });

  factory WledState.initial() => const WledState();

  WledDeviceInfo? device(String id) => devices[id];

  WledState copyWith({
    bool? loading,
    Map<String, WledDeviceInfo>? devices,
    WledProbeInfo? probe,
    bool? probeInProgress,
    bool? addInProgress,
    String? lastError,
    bool clearProbe = false,
    bool clearLastError = false,
  }) {
    return WledState(
      loading: loading ?? this.loading,
      devices: devices ?? this.devices,
      probe: clearProbe ? null : (probe ?? this.probe),
      probeInProgress: probeInProgress ?? this.probeInProgress,
      addInProgress: addInProgress ?? this.addInProgress,
      lastError: clearLastError ? null : (lastError ?? this.lastError),
    );
  }

  WledState replaceDevice(WledDeviceInfo device) {
    return copyWith(devices: {...devices, device.id: device});
  }

  WledState removeDevice(String id) {
    final next = Map<String, WledDeviceInfo>.from(devices)..remove(id);
    return copyWith(devices: next);
  }

  @override
  List<Object?> get props => [
    loading,
    devices,
    probe,
    probeInProgress,
    addInProgress,
    lastError,
  ];
}

/// Result of one "Test connection" run on the Add Device screen.
class WledProbeInfo extends Equatable {
  final String host;
  final int port;
  final bool https;
  final String? name;
  final bool success;
  final String? error;
  final String? version;
  final int? ledCount;

  /// The device-reported name, offered as a display-name default.
  final String? reportedName;
  final DateTime at;

  const WledProbeInfo({
    required this.host,
    required this.port,
    required this.https,
    required this.success,
    this.name,
    this.error,
    this.version,
    this.ledCount,
    this.reportedName,
    required this.at,
  });

  /// True when this result describes the given address still.
  bool matches(String host, int port, bool https) =>
      this.host == host && this.port == port && this.https == https;

  @override
  List<Object?> get props => [
    host,
    port,
    https,
    name,
    success,
    error,
    version,
    ledCount,
    reportedName,
    at,
  ];
}

/// One WLED device as the UI sees it.
class WledDeviceInfo extends Equatable {
  final String id;
  final String name;

  /// `host:port` as registered.
  final String address;
  final String host;
  final int port;
  final bool useHttps;

  /// Last HTTP exchange succeeded. Saved/never-probed devices start false.
  final bool reachable;

  /// A refresh or command is in flight for this device.
  final bool busy;

  /// Last failure for this device, human-readable, or null.
  final String? error;

  final String? version;
  final int? ledCount;

  /// Capabilities verified against the device at registration/refresh.
  final List<DeviceCapability> capabilities;

  // --- confirmed (device-reported) state ---------------------------------

  final bool on;

  /// Device-reported brightness, 0-255.
  final int brightness255;
  final RGBColor? color;
  final int? effectId;
  final String? effectName;
  final int? paletteId;
  final String? paletteName;

  /// Full device-reported effect/palette name lists; the list index is the
  /// firmware id. UI hides reserved entries (`RSVD`, `-`) by index.
  final List<String> effects;
  final List<String> palettes;
  final DateTime? lastSeen;

  const WledDeviceInfo({
    required this.id,
    required this.name,
    required this.address,
    required this.host,
    required this.port,
    required this.useHttps,
    required this.reachable,
    required this.busy,
    this.error,
    this.version,
    this.ledCount,
    this.capabilities = const [],
    this.on = false,
    this.brightness255 = 0,
    this.color,
    this.effectId,
    this.effectName,
    this.paletteId,
    this.paletteName,
    this.effects = const [],
    this.palettes = const [],
    this.lastSeen,
  });

  /// Brightness on the 0-100 scale the UI slider uses.
  int get brightness100 => (brightness255 * 100 / 255).round();

  bool supports(DeviceCapability capability) =>
      capabilities.contains(capability);

  WledDeviceInfo copyWith({
    String? name,
    bool? reachable,
    bool? busy,
    String? error,
    bool clearError = false,
    String? version,
    int? ledCount,
    List<DeviceCapability>? capabilities,
    bool? on,
    int? brightness255,
    RGBColor? color,
    int? effectId,
    String? effectName,
    int? paletteId,
    String? paletteName,
    List<String>? effects,
    List<String>? palettes,
    DateTime? lastSeen,
  }) {
    return WledDeviceInfo(
      id: id,
      name: name ?? this.name,
      address: address,
      host: host,
      port: port,
      useHttps: useHttps,
      reachable: reachable ?? this.reachable,
      busy: busy ?? this.busy,
      error: clearError ? null : (error ?? this.error),
      version: version ?? this.version,
      ledCount: ledCount ?? this.ledCount,
      capabilities: capabilities ?? this.capabilities,
      on: on ?? this.on,
      brightness255: brightness255 ?? this.brightness255,
      color: color ?? this.color,
      effectId: effectId ?? this.effectId,
      effectName: effectName ?? this.effectName,
      paletteId: paletteId ?? this.paletteId,
      paletteName: paletteName ?? this.paletteName,
      effects: effects ?? this.effects,
      palettes: palettes ?? this.palettes,
      lastSeen: lastSeen ?? this.lastSeen,
    );
  }

  @override
  List<Object?> get props => [
    id,
    name,
    address,
    host,
    port,
    useHttps,
    reachable,
    busy,
    error,
    version,
    ledCount,
    capabilities,
    on,
    brightness255,
    color,
    effectId,
    effectName,
    paletteId,
    paletteName,
    effects,
    palettes,
    lastSeen,
  ];
}
