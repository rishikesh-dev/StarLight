// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/foundation.dart';

import '../../core/utils/uuid_utils.dart';
import '../entities/device_capability.dart';
import '../entities/device_profile.dart';
import '../entities/notification_format.dart';
import '../entities/profile_command.dart';

/// A single field-level validation problem.
@immutable
class ProfileValidationError {
  /// Machine-readable field key used to attach the message to a form field.
  final String field;

  /// Human-readable message.
  final String message;

  const ProfileValidationError(this.field, this.message);

  @override
  bool operator ==(Object other) =>
      other is ProfileValidationError &&
      other.field == field &&
      other.message == message;

  @override
  int get hashCode => Object.hash(field, message);

  @override
  String toString() => '$field: $message';
}

/// Validates the [DeviceProfile] domain rules.
///
/// This is the single source of truth for "is this profile usable?". The editor
/// surfaces the messages per field; the cubit refuses to persist an invalid
/// profile; the executor refuses to encode a command for a capability whose
/// mapping is missing.
@immutable
class ProfileValidator {
  const ProfileValidator();

  static const int maxNameLength = 40;

  /// Returns every validation problem, or an empty list when [profile] is
  /// structurally complete and safe to execute.
  static List<ProfileValidationError> validate(DeviceProfile profile) {
    // The built-in profile describes behaviour implemented in code.
    if (profile.isBuiltIn) return const [];

    final errors = <ProfileValidationError>[];

    if (profile.name.trim().isEmpty) {
      errors.add(const ProfileValidationError('name', 'Name is required.'));
    } else if (profile.name.trim().length > maxNameLength) {
      errors.add(
        const ProfileValidationError(
          'name',
          'Name must be $maxNameLength characters or fewer.',
        ),
      );
    }

    if (profile.protocol != ProfileProtocol.bleGatt) {
      errors.add(
        const ProfileValidationError(
          'protocol',
          'Only Bluetooth LE (GATT) profiles are supported.',
        ),
      );
    }

    _uuid(
      errors,
      field: 'serviceUuid',
      label: 'Service UUID',
      value: profile.serviceUuid,
      required: true,
    );
    _uuid(
      errors,
      field: 'writeCharacteristicUuid',
      label: 'Write characteristic UUID',
      value: profile.writeCharacteristicUuid,
      required: true,
    );

    final notify = profile.notifyCharacteristicUuid?.trim() ?? '';
    if (notify.isNotEmpty) {
      _uuid(
        errors,
        field: 'notifyCharacteristicUuid',
        label: 'Notify characteristic UUID',
        value: notify,
        required: false,
      );
    }
    if (profile.notifications != null &&
        !profile.notifications!.isEmpty &&
        notify.isEmpty) {
      errors.add(
        const ProfileValidationError(
          'notifyCharacteristicUuid',
          'Notification decoding requires a notify characteristic UUID.',
        ),
      );
    }

    if (profile.capabilities.isEmpty) {
      errors.add(
        const ProfileValidationError(
          'capabilities',
          'Select at least one capability.',
        ),
      );
    }
    for (final c in profile.capabilities) {
      if (!kExecutableProfileCapabilities.contains(c)) {
        errors.add(
          ProfileValidationError(
            'capabilities',
            '${c.label} is not supported for custom profiles yet.',
          ),
        );
      }
    }

    _commands(profile, errors);
    _notifications(profile, errors);

    return errors;
  }

  /// A convenience map of field → first message, for form rendering.
  static Map<String, String> errorMap(DeviceProfile profile) {
    final map = <String, String>{};
    for (final e in validate(profile)) {
      map.putIfAbsent(e.field, () => e.message);
    }
    return map;
  }

  static bool isValid(DeviceProfile profile) => validate(profile).isEmpty;

  static void _uuid(
    List<ProfileValidationError> errors, {
    required String field,
    required String label,
    required String value,
    required bool required,
  }) {
    final v = value.trim();
    if (v.isEmpty) {
      if (required) {
        errors.add(ProfileValidationError(field, '$label is required.'));
      }
      return;
    }
    if (!UuidUtils.isValid(v)) {
      errors.add(
        ProfileValidationError(
          field,
          'Enter a valid UUID (16-bit like "fff0", 32-bit, or full 128-bit).',
        ),
      );
    }
  }

  static void _commands(
    DeviceProfile profile,
    List<ProfileValidationError> errors,
  ) {
    final commands = profile.commands;

    if (profile.capabilities.contains(DeviceCapability.power)) {
      _template(
        errors,
        field: 'powerOn',
        label: 'Power-on command',
        template: commands.powerOn,
        allowed: const {ProfileValue.checksum},
      );
      _template(
        errors,
        field: 'powerOff',
        label: 'Power-off command',
        template: commands.powerOff,
        allowed: const {ProfileValue.checksum},
      );
    }

    if (profile.capabilities.contains(DeviceCapability.brightness)) {
      _template(
        errors,
        field: 'brightness',
        label: 'Brightness command',
        template: commands.brightness,
        allowed: const {ProfileValue.brightness, ProfileValue.checksum},
      );
      if (commands.brightnessMax <= commands.brightnessMin) {
        errors.add(
          const ProfileValidationError(
            'brightnessRange',
            'Maximum must be greater than minimum.',
          ),
        );
      }
      if (commands.brightnessMin < 0 || commands.brightnessMax > 0xFFFF) {
        errors.add(
          const ProfileValidationError(
            'brightnessRange',
            'Brightness range must be between 0 and 65535.',
          ),
        );
      }
    }

    if (profile.capabilities.contains(DeviceCapability.color)) {
      _template(
        errors,
        field: 'color',
        label: 'Colour command',
        template: commands.color,
        allowed: const {
          ProfileValue.red,
          ProfileValue.green,
          ProfileValue.blue,
          ProfileValue.checksum,
        },
      );
    }
  }

  static void _template(
    List<ProfileValidationError> errors, {
    required String field,
    required String label,
    required CommandTemplate? template,
    required Set<ProfileValue> allowed,
  }) {
    if (template == null) {
      errors.add(
        ProfileValidationError(
          field,
          '$label is required for this capability.',
        ),
      );
      return;
    }
    for (final token in template.tokens) {
      if (token is CommandPlaceholder && !allowed.contains(token.value)) {
        errors.add(
          ProfileValidationError(
            field,
            '$label cannot use "{${token.value.id}}".',
          ),
        );
      }
    }
  }

  static void _notifications(
    DeviceProfile profile,
    List<ProfileValidationError> errors,
  ) {
    final format = profile.notifications;
    if (format == null || format.isEmpty) return;

    final seen = <NotificationTarget>{};
    for (final rule in format.rules) {
      if (rule.byteOffset < 0) {
        errors.add(
          const ProfileValidationError(
            'notifications',
            'Byte offsets cannot be negative.',
          ),
        );
      }
      if (rule.scale == 0) {
        errors.add(
          const ProfileValidationError(
            'notifications',
            'Scale cannot be zero.',
          ),
        );
      }
      if (!seen.add(rule.target)) {
        errors.add(
          ProfileValidationError(
            'notifications',
            'Only one rule per state field is allowed.',
          ),
        );
      }
    }
  }
}
