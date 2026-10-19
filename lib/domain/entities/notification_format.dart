// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/foundation.dart';

import 'device_state_update.dart';
import 'profile_command.dart';

/// A device state field a notification packet can carry.
enum NotificationTarget {
  power('power', 'Power'),
  brightness('brightness', 'Brightness'),
  red('red', 'Red'),
  green('green', 'Green'),
  blue('blue', 'Blue');

  const NotificationTarget(this.id, this.label);

  final String id;
  final String label;

  static NotificationTarget? fromId(String id) {
    for (final t in NotificationTarget.values) {
      if (t.id == id) return t;
    }
    return null;
  }
}

/// Extracts one field from a notification packet by byte offset.
///
/// Values are read little/big-endian per [width], then transformed with
/// `value * scale + offset`. For [NotificationTarget.power] the transformed
/// value is compared against [onThreshold] (default `1`, i.e. any non-zero byte
/// means "on").
@immutable
class NotificationRule {
  final NotificationTarget target;
  final int byteOffset;
  final NumericWidth width;
  final double scale;
  final double offset;
  final int onThreshold;

  const NotificationRule({
    required this.target,
    required this.byteOffset,
    this.width = NumericWidth.u8,
    this.scale = 1,
    this.offset = 0,
    this.onThreshold = 1,
  });

  /// Reads the raw integer, or null when [bytes] is too short for this rule.
  int? rawValue(List<int> bytes) {
    final end = byteOffset + width.byteLength;
    if (byteOffset < 0 || end > bytes.length) return null;
    switch (width) {
      case NumericWidth.u8:
        return bytes[byteOffset] & 0xFF;
      case NumericWidth.u16le:
        return (bytes[byteOffset] & 0xFF) |
            ((bytes[byteOffset + 1] & 0xFF) << 8);
      case NumericWidth.u16be:
        return ((bytes[byteOffset] & 0xFF) << 8) |
            (bytes[byteOffset + 1] & 0xFF);
    }
  }

  /// The transformed value, or null when the packet is too short.
  num? value(List<int> bytes) {
    final raw = rawValue(bytes);
    if (raw == null) return null;
    return raw * scale + offset;
  }

  NotificationRule copyWith({
    NotificationTarget? target,
    int? byteOffset,
    NumericWidth? width,
    double? scale,
    double? offset,
    int? onThreshold,
  }) {
    return NotificationRule(
      target: target ?? this.target,
      byteOffset: byteOffset ?? this.byteOffset,
      width: width ?? this.width,
      scale: scale ?? this.scale,
      offset: offset ?? this.offset,
      onThreshold: onThreshold ?? this.onThreshold,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is NotificationRule &&
      other.target == target &&
      other.byteOffset == byteOffset &&
      other.width == width &&
      other.scale == scale &&
      other.offset == offset &&
      other.onThreshold == onThreshold;

  @override
  int get hashCode =>
      Object.hash(target, byteOffset, width, scale, offset, onThreshold);
}

/// Optional notification decoding configuration for a device profile.
///
/// Only used when the profile declares a notification characteristic. A
/// malformed or too-short packet yields no updates rather than a fabricated
/// value; the app never assumes a device reported state it did not.
@immutable
class NotificationFormat {
  final List<NotificationRule> rules;

  const NotificationFormat(this.rules);

  bool get isEmpty => rules.isEmpty;

  /// Decodes [bytes] into zero or more state updates.
  List<DeviceStateUpdate> decode(List<int> bytes) {
    final updates = <DeviceStateUpdate>[];

    for (final rule in rules) {
      switch (rule.target) {
        case NotificationTarget.power:
          final v = rule.value(bytes);
          if (v != null) {
            updates.add(
              DeviceStateUpdate(
                type: StateUpdateType.power,
                value: v >= rule.onThreshold,
              ),
            );
          }
        case NotificationTarget.brightness:
          final v = rule.value(bytes);
          if (v != null) {
            updates.add(
              DeviceStateUpdate(
                type: StateUpdateType.brightness,
                value: v.round(),
              ),
            );
          }
        case NotificationTarget.red:
        case NotificationTarget.green:
        case NotificationTarget.blue:
          // Colour is emitted as one update only when all three channels are
          // configured, so a partial packet can never imply a wrong colour.
          break;
      }
    }

    final hasColour = rules.any(
      (r) =>
          r.target == NotificationTarget.red ||
          r.target == NotificationTarget.green ||
          r.target == NotificationTarget.blue,
    );
    if (hasColour) {
      final red = _valueFor(NotificationTarget.red, bytes);
      final green = _valueFor(NotificationTarget.green, bytes);
      final blue = _valueFor(NotificationTarget.blue, bytes);
      if (red != null && green != null && blue != null) {
        updates.add(
          DeviceStateUpdate(
            type: StateUpdateType.color,
            value: {
              'red': red.round().clamp(0, 255),
              'green': green.round().clamp(0, 255),
              'blue': blue.round().clamp(0, 255),
            },
          ),
        );
      }
    }

    return updates;
  }

  num? _valueFor(NotificationTarget target, List<int> bytes) {
    for (final rule in rules) {
      if (rule.target == target) return rule.value(bytes);
    }
    return null;
  }

  @override
  bool operator ==(Object other) =>
      other is NotificationFormat && listEquals(other.rules, rules);

  @override
  int get hashCode => Object.hashAll(rules);
}
