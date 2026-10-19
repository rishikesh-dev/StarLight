// SPDX-License-Identifier: Apache-2.0

import 'package:equatable/equatable.dart';
import 'package:starlight/domain/entities/device.dart';
import 'package:starlight/domain/entities/device_state.dart';

/// Base class for automation conditions
abstract class AutomationCondition extends Equatable {
  final String type;
  final Map<String, dynamic> config;

  const AutomationCondition({required this.type, required this.config});

  /// Evaluates whether this condition is met
  Future<bool> evaluate(Map<String, Device> devices);

  @override
  List<Object?> get props => [type, config];
}

/// Time range condition - true during specified time periods
class TimeRangeCondition extends AutomationCondition {
  TimeRangeCondition({
    required String startTime,
    required String endTime,
    List<int>? days,
  }) : super(
         type: 'time_range',
         config: {
           'startTime': startTime,
           'endTime': endTime,
           'days': days ?? [1, 2, 3, 4, 5, 6, 7],
         },
       );

  @override
  Future<bool> evaluate(Map<String, Device> devices) async {
    final now = DateTime.now();
    final startParts = (config['startTime'] as String).split(':');
    final endParts = (config['endTime'] as String).split(':');
    final startMinutes =
        int.parse(startParts[0]) * 60 + int.parse(startParts[1]);
    final endMinutes = int.parse(endParts[0]) * 60 + int.parse(endParts[1]);
    final nowMinutes = now.hour * 60 + now.minute;
    final day = now.weekday;

    if (!(config['days'] as List<int>).contains(day)) return false;
    if (startMinutes <= endMinutes) {
      return nowMinutes >= startMinutes && nowMinutes <= endMinutes;
    }
    // Crosses midnight
    return nowMinutes >= startMinutes || nowMinutes <= endMinutes;
  }
}

/// Device state condition
class DeviceStateCondition extends AutomationCondition {
  DeviceStateCondition({
    required String deviceId,
    required String capability,
    required dynamic value,
    String operator = 'equals',
  }) : super(
         type: 'device_state',
         config: {
           'deviceId': deviceId,
           'capability': capability,
           'value': value,
           'operator': operator,
         },
       );

  @override
  Future<bool> evaluate(Map<String, Device> devices) async {
    final device = devices[config['deviceId']];
    if (device == null) return false;
    final currentValue = _getDeviceStateValue(
      device,
      config['capability'] as String,
    );
    if (currentValue == null) return false;
    final expectedValue = config['value'];
    final operator = config['operator'] as String;

    switch (operator) {
      case 'equals':
        return _valuesEqual(currentValue, expectedValue);
      case 'not_equals':
        return !_valuesEqual(currentValue, expectedValue);
      case 'greater_than':
        return _cmp(currentValue, expectedValue) > 0;
      case 'less_than':
        return _cmp(currentValue, expectedValue) < 0;
      case 'in':
        return (expectedValue as List).any(
          (v) => _valuesEqual(currentValue, v),
        );
      default:
        return false;
    }
  }

  dynamic _getDeviceStateValue(Device device, String capability) {
    // Works for any device state; non-light states simply report null for
    // light-specific capabilities instead of throwing.
    final state = device.state;
    if (state is LightState) {
      switch (capability) {
        case 'power':
          return state.isOn;
        case 'brightness':
          return state.brightness;
        case 'color':
          return state.color?.toHexStr() ?? '#000000';
        case 'effect':
          return state.effect;
        case 'speed':
          return state.speed;
        case 'colorTemperature':
          return state.colorTemperature;
      }
    }
    return null;
  }

  bool _valuesEqual(dynamic a, dynamic b) {
    if (a == null || b == null) return a == b;
    return a == b;
  }

  int _cmp(dynamic a, dynamic b) {
    final x = a is num ? a : 0;
    final y = b is num ? b : 0;
    return x.compareTo(y);
  }
}
