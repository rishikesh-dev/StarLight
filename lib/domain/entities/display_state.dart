// SPDX-License-Identifier: Apache-2.0

import 'device_capability.dart';
import 'device_state.dart';
import 'device_type.dart';

/// State for a display device (ESP32 displays, LED matrices).
class DisplayState extends DeviceState {
  @override
  final bool isOn;
  @override
  final bool isConnected;
  final String? text;
  final List<String> lines;
  final Map<String, dynamic> animationConfig;

  const DisplayState({
    required this.isOn,
    required this.isConnected,
    this.text,
    this.lines = const [],
    this.animationConfig = const {},
  });

  @override
  DeviceType get deviceType => DeviceType.display;

  @override
  List<DeviceCapability> get supportedCapabilities => [
    DeviceCapability.power,
    DeviceCapability.display,
    DeviceCapability.text,
    DeviceCapability.graphics,
    DeviceCapability.animation,
  ];

  DisplayState copyWith({
    bool? isOn,
    bool? isConnected,
    String? text,
    List<String>? lines,
    Map<String, dynamic>? animationConfig,
  }) {
    return DisplayState(
      isOn: isOn ?? this.isOn,
      isConnected: isConnected ?? this.isConnected,
      text: text ?? this.text,
      lines: lines ?? this.lines,
      animationConfig: animationConfig ?? this.animationConfig,
    );
  }

  @override
  List<Object?> get props => [
    deviceType,
    supportedCapabilities,
    isOn,
    isConnected,
    text,
    lines,
    animationConfig,
  ];
}
