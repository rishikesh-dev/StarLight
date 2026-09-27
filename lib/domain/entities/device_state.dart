import 'package:equatable/equatable.dart';
import 'device_capability.dart';
import 'device_type.dart';
import 'rgb_color.dart';

/// Base class for device state.
/// Subclasses represent specific device type states (LightState, PlugState, etc.)
abstract class DeviceState extends Equatable {
  const DeviceState();

  /// The type of device this state belongs to.
  DeviceType get deviceType;

  /// Capabilities supported by this device.
  List<DeviceCapability> get supportedCapabilities;

  /// Whether the device is currently powered on.
  bool get isOn;

  /// Whether the device is connected/reachable.
  bool get isConnected;

  @override
  List<Object?> get props => [deviceType, supportedCapabilities, isOn, isConnected];
}

/// State for a light device.
class LightState extends DeviceState {
  final RGBColor? color;
  final int? brightness; // 0-100
  final int? colorTemperature; // Kelvin
  final String? effect;
  final int? speed; // 0-100
  final bool isOn;
  final bool isConnected;

  const LightState({
    this.color,
    this.brightness,
    this.colorTemperature,
    this.effect,
    this.speed,
    required this.isOn,
    required this.isConnected,
  });

  @override
  DeviceType get deviceType => DeviceType.light;

  @override
  List<DeviceCapability> get supportedCapabilities => [
    DeviceCapability.power,
    DeviceCapability.brightness,
    DeviceCapability.color,
    DeviceCapability.colorTemperature,
    DeviceCapability.effect,
    DeviceCapability.speed,
  ];

  LightState copyWith({
    RGBColor? color,
    int? brightness,
    int? colorTemperature,
    String? effect,
    int? speed,
    bool? isOn,
    bool? isConnected,
  }) {
    return LightState(
      color: color ?? this.color,
      brightness: brightness ?? this.brightness,
      colorTemperature: colorTemperature ?? this.colorTemperature,
      effect: effect ?? this.effect,
      speed: speed ?? this.speed,
      isOn: isOn ?? this.isOn,
      isConnected: isConnected ?? this.isConnected,
    );
  }

  @override
  List<Object?> get props => [
    deviceType,
    supportedCapabilities,
    isOn,
    isConnected,
    color,
    brightness,
    colorTemperature,
    effect,
    speed,
  ];
}

/// State for a smart plug device.
class PlugState extends DeviceState {
  final bool isOn;
  final bool isConnected;
  final double? energy; // kWh
  final double? power; // Watts

  const PlugState({
    required this.isOn,
    required this.isConnected,
    this.energy,
    this.power,
  });

  @override
  DeviceType get deviceType => DeviceType.plug;

  @override
  List<DeviceCapability> get supportedCapabilities => [
    DeviceCapability.power,
    DeviceCapability.energy,
  ];

  PlugState copyWith({
    bool? isOn,
    bool? isConnected,
    double? energy,
    double? power,
  }) {
    return PlugState(
      isOn: isOn ?? this.isOn,
      isConnected: isConnected ?? this.isConnected,
      energy: energy ?? this.energy,
      power: power ?? this.power,
    );
  }

  @override
  List<Object?> get props => [
    deviceType,
    supportedCapabilities,
    isOn,
    isConnected,
    energy,
    power,
  ];
}

/// State for a fan device.
class FanState extends DeviceState {
  final bool isOn;
  final bool isConnected;
  final int? speed; // 0-100
  final String? mode;

  const FanState({
    required this.isOn,
    required this.isConnected,
    this.speed,
    this.mode,
  });

  @override
  DeviceType get deviceType => DeviceType.fan;

  @override
  List<DeviceCapability> get supportedCapabilities => [
    DeviceCapability.power,
    DeviceCapability.speed,
    DeviceCapability.effect,
  ];

  FanState copyWith({
    bool? isOn,
    bool? isConnected,
    int? speed,
    String? mode,
  }) {
    return FanState(
      isOn: isOn ?? this.isOn,
      isConnected: isConnected ?? this.isConnected,
      speed: speed ?? this.speed,
      mode: mode ?? this.mode,
    );
  }

  @override
  List<Object?> get props => [
    deviceType,
    supportedCapabilities,
    isOn,
    isConnected,
    speed,
    mode,
  ];
}

/// Generic device state for unknown/other devices.
class GenericDeviceState extends DeviceState {
  final bool isOn;
  final bool isConnected;
  final Map<String, dynamic> attributes;

  const GenericDeviceState({
    required this.isOn,
    required this.isConnected,
    this.attributes = const {},
    required DeviceType deviceType,
  }) : _deviceType = deviceType;

  final DeviceType _deviceType;

  @override
  DeviceType get deviceType => _deviceType;

  @override
  List<DeviceCapability> get supportedCapabilities => [
    DeviceCapability.power,
  ];

  GenericDeviceState copyWith({
    bool? isOn,
    bool? isConnected,
    Map<String, dynamic>? attributes,
  }) {
    return GenericDeviceState(
      isOn: isOn ?? this.isOn,
      isConnected: isConnected ?? this.isConnected,
      attributes: attributes ?? this.attributes,
      deviceType: _deviceType,
    );
  }

  @override
  List<Object?> get props => [
    deviceType,
    supportedCapabilities,
    isOn,
    isConnected,
    attributes,
  ];
}