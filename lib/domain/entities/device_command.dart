// SPDX-License-Identifier: Apache-2.0

import 'dart:typed_data';

import 'package:equatable/equatable.dart';

/// A command to send to a device.
/// The interpretation is device-type-specific.
class DeviceCommand extends Equatable {
  final String type; // 'power', 'brightness', 'color', 'effect', etc.
  final Map<String, dynamic> parameters;

  const DeviceCommand({required this.type, required this.parameters});

  factory DeviceCommand.power(bool on) =>
      DeviceCommand(type: 'power', parameters: {'on': on});

  factory DeviceCommand.brightness(int value) =>
      DeviceCommand(type: 'brightness', parameters: {'value': value});

  factory DeviceCommand.color(int red, int green, int blue) => DeviceCommand(
    type: 'color',
    parameters: {'red': red, 'green': green, 'blue': blue},
  );

  factory DeviceCommand.colorTemperature(int kelvin) =>
      DeviceCommand(type: 'colorTemperature', parameters: {'kelvin': kelvin});

  factory DeviceCommand.effect(
    String name, {
    int? id,
    Map<String, dynamic>? params,
  }) => DeviceCommand(
    type: 'effect',
    parameters: {
      'name': name,
      // ignore: use_null_aware_elements — not supported by the pinned SDK.
      if (id != null) 'id': id,
      'params': params ?? {},
    },
  );

  factory DeviceCommand.speed(int value) =>
      DeviceCommand(type: 'speed', parameters: {'value': value});

  factory DeviceCommand.palette(int id) =>
      DeviceCommand(type: 'palette', parameters: {'id': id});

  factory DeviceCommand.custom(String type, Map<String, dynamic> parameters) =>
      DeviceCommand(type: type, parameters: parameters);

  factory DeviceCommand.raw(Uint8List bytes) =>
      DeviceCommand(type: 'raw', parameters: {'bytes': bytes});

  @override
  List<Object?> get props => [type, parameters];
}
