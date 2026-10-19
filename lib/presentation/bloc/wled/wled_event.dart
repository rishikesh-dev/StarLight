// SPDX-License-Identifier: Apache-2.0

import 'package:equatable/equatable.dart';

import 'package:starlight/domain/entities/rgb_color.dart';

/// Events for the WLED Bloc.
abstract class WledEvent extends Equatable {
  const WledEvent();

  @override
  List<Object?> get props => [];
}

/// Loads the persisted WLED devices (on app start).
class WledDevicesLoad extends WledEvent {}

/// Runs a connectivity test for the Add Device flow.
class WledConnectionTest extends WledEvent {
  final String host;
  final int port;
  final bool https;
  final String? name;

  const WledConnectionTest({
    required this.host,
    required this.port,
    required this.https,
    this.name,
  });

  @override
  List<Object?> get props => [host, port, https, name];
}

/// Registers a device after a successful test.
class WledDeviceAdd extends WledEvent {
  final String host;
  final int port;
  final bool https;
  final String? name;

  const WledDeviceAdd({
    required this.host,
    required this.port,
    required this.https,
    this.name,
  });

  @override
  List<Object?> get props => [host, port, https, name];
}

/// Removes a saved device and cancels its activity.
class WledDeviceRemove extends WledEvent {
  final String id;

  const WledDeviceRemove(this.id);

  @override
  List<Object?> get props => [id];
}

/// Renames a saved device.
class WledDeviceRename extends WledEvent {
  final String id;
  final String name;

  const WledDeviceRename(this.id, this.name);

  @override
  List<Object?> get props => [id, name];
}

/// Reads the current state from the device (manual refresh).
class WledDeviceRefresh extends WledEvent {
  final String id;

  const WledDeviceRefresh(this.id);

  @override
  List<Object?> get props => [id];
}

/// Power on/off.
class WledPower extends WledEvent {
  final String id;
  final bool on;

  const WledPower(this.id, this.on);

  @override
  List<Object?> get props => [id, on];
}

/// Brightness on the 0-100 (percent) UI scale.
class WledBrightness extends WledEvent {
  final String id;
  final int value100;

  const WledBrightness(this.id, this.value100);

  @override
  List<Object?> get props => [id, value100];
}

/// RGB color.
class WledColor extends WledEvent {
  final String id;
  final RGBColor color;

  const WledColor(this.id, this.color);

  @override
  List<Object?> get props => [id, color];
}

/// Select a device-reported effect by its firmware id.
class WledEffectSelect extends WledEvent {
  final String id;
  final int effectId;

  const WledEffectSelect(this.id, this.effectId);

  @override
  List<Object?> get props => [id, effectId];
}

/// Select a device-reported palette by its id.
class WledPaletteSelect extends WledEvent {
  final String id;
  final int paletteId;

  const WledPaletteSelect(this.id, this.paletteId);

  @override
  List<Object?> get props => [id, paletteId];
}

/// Internal: the repository observed a reachability transition for a
/// device outside of a bloc-driven call (e.g. a stale command failing).
class WledConnectionSync extends WledEvent {
  final String deviceId;
  final bool reachable;

  const WledConnectionSync(this.deviceId, this.reachable);

  @override
  List<Object?> get props => [deviceId, reachable];
}
