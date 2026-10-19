// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:starlight/core/errors/exceptions.dart';
import 'package:starlight/core/utils/app_logger.dart';
import 'package:starlight/data/datasources/ble_datasource.dart';
import 'package:starlight/domain/entities/command_result.dart';
import 'package:starlight/domain/entities/device_capability.dart';
import 'package:starlight/domain/entities/device_command.dart';
import 'package:starlight/domain/entities/device_profile.dart';
import 'package:starlight/domain/entities/device_state_update.dart';
import 'package:starlight/domain/entities/profile_command.dart';
import 'package:starlight/domain/entities/profile_verification.dart';
import 'package:starlight/domain/services/profile_executor.dart';

/// Executes custom GATT profiles against the single connected device.
///
/// It owns no connection of its own: every read/write/subscribe goes through
/// the shared [BleDataSource]. Verification inspects the *live* discovered
/// services and characteristic properties, so a profile can never claim a
/// capability the device does not actually expose.
class BleGattProfileExecutor implements ProfileExecutor {
  final BleDataSource dataSource;

  final Map<String, _VerifiedTarget> _verified = {};

  /// Notification subscriptions keyed by profile id.
  final Map<String, StreamSubscription<List<int>>> _notifySubs = {};
  final Map<String, BluetoothCharacteristic> _notifyChars = {};

  final StreamController<DeviceStateUpdate> _stateUpdates =
      StreamController<DeviceStateUpdate>.broadcast();

  StreamSubscription<BluetoothConnectionState>? _connSub;

  BleGattProfileExecutor(this.dataSource) {
    _connSub = dataSource.connectionState.listen((state) {
      if (state != BluetoothConnectionState.connected) {
        unawaited(reset());
      }
    });
  }

  @override
  Stream<DeviceStateUpdate> get stateUpdates => _stateUpdates.stream;

  @override
  bool isVerified(String profileId) => _verified.containsKey(profileId);

  @override
  Future<ProfileVerification> verify(DeviceProfile profile) async {
    if (profile.isBuiltIn) {
      return const ProfileVerification.unverified();
    }
    if (!dataSource.isConnected) {
      _verified.remove(profile.id);
      return const ProfileVerification.notConnected();
    }

    try {
      final target = await dataSource.resolveGattTarget(
        serviceUuid: profile.serviceUuid,
        writeCharacteristicUuid: profile.writeCharacteristicUuid,
        notifyCharacteristicUuid: profile.notifyCharacteristicUuid,
      );

      final modeCheck = _resolveWriteMode(profile, target);
      if (modeCheck.error != null) {
        _verified.remove(profile.id);
        await _cancelNotify(profile.id);
        return ProfileVerification.failed(modeCheck.error!);
      }

      await _cancelNotify(profile.id);
      if (target.notifyCharacteristic != null && profile.hasNotifications) {
        await dataSource.subscribeNotifications(target.notifyCharacteristic!);
        _notifyChars[profile.id] = target.notifyCharacteristic!;
        _notifySubs[profile.id] = target.notifyCharacteristic!.onValueReceived
            .listen(
              (data) {
                final updates = profile.notifications!.decode(data);
                for (final update in updates) {
                  if (!_stateUpdates.isClosed) _stateUpdates.add(update);
                }
              },
              onError: (Object e) {
                AppLog.warn(
                  'profile notify stream error for ${profile.id}: $e',
                );
              },
            );
      }

      _verified[profile.id] = _VerifiedTarget(
        target: target,
        writeWithoutResponse: modeCheck.withoutResponse,
      );

      return ProfileVerification(
        status: ProfileVerificationStatus.verified,
        serviceUuid: profile.serviceUuid,
        writeCharacteristicUuid: profile.writeCharacteristicUuid,
        notifyCharacteristicUuid: target.notifyCharacteristic == null
            ? null
            : profile.notifyCharacteristicUuid,
        supportsWriteWithResponse: target.supportsWriteWithResponse,
        supportsWriteWithoutResponse: target.supportsWriteWithoutResponse,
        supportsNotify: target.supportsNotify,
        writeWithoutResponse: modeCheck.withoutResponse,
        verifiedAt: DateTime.now(),
        message: modeCheck.withoutResponse
            ? 'Writes without response'
            : 'Writes with response',
      );
    } on BleException catch (e) {
      _verified.remove(profile.id);
      await _cancelNotify(profile.id);
      return ProfileVerification.failed(e.message);
    } on Exception catch (e) {
      _verified.remove(profile.id);
      await _cancelNotify(profile.id);
      return ProfileVerification.failed(e.toString());
    }
  }

  _WriteMode _resolveWriteMode(
    DeviceProfile profile,
    ResolvedGattTarget target,
  ) {
    switch (profile.writeMode) {
      case GattWriteMode.withResponse:
        if (!target.supportsWriteWithResponse) {
          return _WriteMode.error(
            'The device cannot write with response to '
            '${profile.writeCharacteristicUuid}.',
          );
        }
        return const _WriteMode(withoutResponse: false);
      case GattWriteMode.withoutResponse:
        if (!target.supportsWriteWithoutResponse) {
          return _WriteMode.error(
            'The device cannot write without response to '
            '${profile.writeCharacteristicUuid}.',
          );
        }
        return const _WriteMode(withoutResponse: true);
      case GattWriteMode.automatic:
        if (!target.supportsWriteWithResponse &&
            !target.supportsWriteWithoutResponse) {
          return _WriteMode.error(
            'Characteristic ${profile.writeCharacteristicUuid} is not writable.',
          );
        }
        return _WriteMode(withoutResponse: target.supportsWriteWithoutResponse);
    }
  }

  @override
  Future<CommandResult> send(
    DeviceProfile profile,
    DeviceCommand command,
  ) async {
    final verified = _verified[profile.id];
    if (verified == null) {
      return CommandResult.failure(
        'profile_not_verified',
        'Verify this profile against the device before sending commands.',
      );
    }

    final template = _templateFor(profile, command);
    if (template == null) {
      return CommandResult.failure(
        'unsupported_command',
        'This profile has no mapping for "${command.type}".',
      );
    }

    final values = _valuesFor(profile, command);
    try {
      final bytes = template.encode(values);
      await dataSource.writeBytes(
        bytes,
        characteristic: verified.target.writeCharacteristic,
        withoutResponse: verified.writeWithoutResponse,
      );
      return const CommandResult.ok();
    } on TimeoutException {
      AppLog.warn('profile write timed out for ${profile.id}');
      return CommandResult.failure(
        'write_timeout',
        'The device did not acknowledge the write in time.',
      );
    } on DisconnectedException {
      return CommandResult.failure(
        'not_connected',
        'The device disconnected before the command was sent.',
      );
    } on CharacteristicNotFoundException {
      return CommandResult.failure(
        'characteristic_not_found',
        'The configured write characteristic is no longer available.',
      );
    } on StateError catch (e) {
      return CommandResult.failure('encoding_failed', e.message);
    } on Exception catch (e) {
      AppLog.error('profile write failed for ${profile.id}', e);
      return CommandResult.failure('write_failed', 'The write failed.');
    }
  }

  CommandTemplate? _templateFor(DeviceProfile profile, DeviceCommand command) {
    switch (command.type) {
      case 'power':
        final on = command.parameters['on'];
        if (on is! bool) return null;
        if (!profile.capabilities.contains(DeviceCapability.power)) return null;
        return on ? profile.commands.powerOn : profile.commands.powerOff;
      case 'brightness':
        if (!profile.capabilities.contains(DeviceCapability.brightness)) {
          return null;
        }
        return profile.commands.brightness;
      case 'color':
        if (!profile.capabilities.contains(DeviceCapability.color)) return null;
        return profile.commands.color;
      default:
        return null;
    }
  }

  Map<ProfileValue, int> _valuesFor(
    DeviceProfile profile,
    DeviceCommand command,
  ) {
    switch (command.type) {
      case 'power':
        return const {};
      case 'brightness':
        final value = command.parameters['value'];
        if (value is! int) return const {};
        return {
          ProfileValue.brightness: profile.commands.scaleBrightness(value),
        };
      case 'color':
        final red = command.parameters['red'];
        final green = command.parameters['green'];
        final blue = command.parameters['blue'];
        if (red is! int || green is! int || blue is! int) return const {};
        return {
          ProfileValue.red: red & 0xFF,
          ProfileValue.green: green & 0xFF,
          ProfileValue.blue: blue & 0xFF,
        };
      default:
        return const {};
    }
  }

  @override
  Future<void> reset() async {
    for (final id in _notifySubs.keys.toList()) {
      await _cancelNotify(id);
    }
    _verified.clear();
  }

  Future<void> _cancelNotify(String profileId) async {
    final sub = _notifySubs.remove(profileId);
    final char = _notifyChars.remove(profileId);
    await sub?.cancel();
    if (char != null) {
      await dataSource.unsubscribeNotifications(char);
    }
  }

  Future<void> dispose() async {
    await reset();
    await _connSub?.cancel();
    _connSub = null;
    await _stateUpdates.close();
  }
}

class _VerifiedTarget {
  final ResolvedGattTarget target;
  final bool writeWithoutResponse;

  _VerifiedTarget({required this.target, required this.writeWithoutResponse});
}

class _WriteMode {
  final bool withoutResponse;
  final String? error;

  const _WriteMode({required this.withoutResponse}) : error = null;

  const _WriteMode.error(String message)
    : withoutResponse = false,
      error = message;
}
