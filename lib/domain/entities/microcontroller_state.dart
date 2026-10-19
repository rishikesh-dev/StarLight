// SPDX-License-Identifier: Apache-2.0

import 'device_capability.dart';
import 'device_state.dart';
import 'device_type.dart';

/// State for a microcontroller device (ESP32, ESP8266, etc.).
class MicrocontrollerState extends DeviceState {
  @override
  final bool isOn;
  @override
  final bool isConnected;
  final Map<int, bool> gpioStates; // pin -> state
  final Map<int, int> pwmValues; // pin -> 0-255
  final Map<String, dynamic> sensorReadings; // sensor name -> value
  final String? firmwareVersion;
  final Map<String, dynamic> config;

  const MicrocontrollerState({
    required this.isOn,
    required this.isConnected,
    this.gpioStates = const {},
    this.pwmValues = const {},
    this.sensorReadings = const {},
    this.firmwareVersion,
    this.config = const {},
  });

  @override
  DeviceType get deviceType => DeviceType.microcontroller;

  @override
  List<DeviceCapability> get supportedCapabilities => [
    DeviceCapability.power,
    DeviceCapability.gpio,
    DeviceCapability.pwm,
    DeviceCapability.sensorReading,
    DeviceCapability.firmware,
    DeviceCapability.config,
    DeviceCapability.custom,
  ];

  MicrocontrollerState copyWith({
    bool? isOn,
    bool? isConnected,
    Map<int, bool>? gpioStates,
    Map<int, int>? pwmValues,
    Map<String, dynamic>? sensorReadings,
    String? firmwareVersion,
    Map<String, dynamic>? config,
  }) {
    return MicrocontrollerState(
      isOn: isOn ?? this.isOn,
      isConnected: isConnected ?? this.isConnected,
      gpioStates: gpioStates ?? this.gpioStates,
      pwmValues: pwmValues ?? this.pwmValues,
      sensorReadings: sensorReadings ?? this.sensorReadings,
      firmwareVersion: firmwareVersion ?? this.firmwareVersion,
      config: config ?? this.config,
    );
  }

  @override
  List<Object?> get props => [
    deviceType,
    supportedCapabilities,
    isOn,
    isConnected,
    gpioStates,
    pwmValues,
    sensorReadings,
    firmwareVersion,
    config,
  ];
}
