// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/foundation.dart';

import '../../core/ble/protocol_encoder.dart';
import '../../core/utils/app_logger.dart';
import '../entities/device_capability.dart';
import '../entities/device_command.dart';
import '../entities/device_profile.dart';
import '../entities/effect.dart';
import '../entities/light_command.dart';
import '../repositories/ble_repository.dart';
import 'profile_executor.dart';

/// Thrown when a command cannot be routed to the device.
class CommandRoutingException implements Exception {
  final String code;
  final String message;

  CommandRoutingException(this.code, this.message);

  @override
  String toString() => message;
}

/// Decides how a [DeviceCommand] reaches the connected device.
///
/// When a *verified* custom profile is active, the command is encoded by that
/// profile and written through [ProfileExecutor]. Otherwise it falls back to
/// the existing MR Star [ProtocolEncoder] path — so built-in behaviour is
/// byte-for-byte unchanged and a custom profile can never be encoded by the
/// MR Star encoder (or vice versa).
///
/// [capabilities] is the set the UI is allowed to expose. It mirrors the
/// active profile (or the built-in MR Star set) so unverified profiles cannot
/// drive controls.
class CommandRouter extends ChangeNotifier {
  final BleRepository _bleRepository;
  ProfileExecutor? _executor;

  DeviceProfile? _activeProfile;
  Set<DeviceCapability> _capabilities = kDefaultLightCapabilities;

  CommandRouter(this._bleRepository, {ProfileExecutor? executor}) {
    _executor = executor;
  }
  void attachExecutor(ProfileExecutor executor) => _executor = executor;

  /// The verified custom profile currently driving commands, or null when the
  /// built-in MR Star path is active.
  DeviceProfile? get activeProfile => _activeProfile;

  /// Capabilities the UI may expose for the connected device.
  Set<DeviceCapability> get capabilities => _capabilities;

  /// Sets (or clears) the active custom profile and the exposed capabilities.
  ///
  /// A built-in or null [profile] selects the built-in MR Star path. Pass an
  /// empty [capabilities] set for an assigned-but-unverified profile so the UI
  /// exposes no controls until it is verified.
  void applyProfile(
    DeviceProfile? profile, {
    Set<DeviceCapability>? capabilities,
  }) {
    final custom = (profile != null && !profile.isBuiltIn) ? profile : null;
    final nextCapabilities =
        capabilities ??
        (custom != null ? custom.capabilities : kDefaultLightCapabilities);
    final changed =
        _activeProfile?.id != custom?.id ||
        !setEquals(_capabilities, nextCapabilities);

    _activeProfile = custom;
    _capabilities = nextCapabilities;

    if (changed) {
      AppLog.info(
        'CommandRouter: profile=${_activeProfile?.id ?? 'built-in MR Star'} '
        'capabilities=${_capabilities.map((c) => c.name).join(',')}',
      );
      notifyListeners();
    }
  }

  /// Falls back to built-in behaviour and capabilities.
  void reset() => applyProfile(null);

  /// Encodes and sends [command] through the active route.
  ///
  /// Throws [CommandRoutingException] on a refused/failed command so callers
  /// (LightBloc) surface the real outcome instead of assuming success.
  Future<void> send(DeviceCommand command) async {
    final profile = _activeProfile;
    if (profile != null) {
      final executor = _executor;
      if (executor == null || !executor.isVerified(profile.id)) {
        throw CommandRoutingException(
          'profile_not_verified',
          'The assigned device profile is not verified yet. Verify it in '
              'Device details.',
        );
      }
      final result = await executor.send(profile, command);
      if (!result.success) {
        throw CommandRoutingException(
          result.error ?? 'command_failed',
          result.message ?? 'The device rejected the command.',
        );
      }
      return;
    }

    await _sendMrStar(command);
  }

  Future<void> _sendMrStar(DeviceCommand command) async {
    AppLog.debug('router: MR Star path for ${command.type}');
    final Uint8List? bytes;
    try {
      bytes = _encodeMrStar(command);
    } on ArgumentError catch (e) {
      // A validated-parameter failure (e.g. an out-of-range speed) is a caller
      // error, not a transport problem — surface it as an explicit typed
      // failure instead of letting it escape as an unexpected exception.
      throw CommandRoutingException(
        'invalid_parameter',
        e.message?.toString() ?? 'Invalid command parameter.',
      );
    }
    if (bytes == null) {
      throw CommandRoutingException(
        'unsupported_command',
        'Command type ${command.type} is not supported.',
      );
    }
    await _bleRepository.sendCommand(
      LightCommand(type: command.type, bytes: bytes),
    );
  }

  Uint8List? _encodeMrStar(DeviceCommand command) {
    switch (command.type) {
      case 'power':
        final on = command.parameters['on'];
        if (on is! bool) return null;
        return on ? ProtocolEncoder.powerOn() : ProtocolEncoder.powerOff();
      case 'brightness':
        final value = command.parameters['value'];
        if (value is! int) return null;
        return ProtocolEncoder.brightness(value);
      case 'color':
        final red = command.parameters['red'];
        final green = command.parameters['green'];
        final blue = command.parameters['blue'];
        if (red is! int || green is! int || blue is! int) return null;
        return ProtocolEncoder.colorFromRGB(red, green, blue);
      case 'effect':
        // Resolve through the canonical catalogue — the single authoritative
        // name → mode id mapping. An unknown name is an explicit
        // `unsupported_command`; it is never silently mapped to a default mode.
        final name = command.parameters['name'];
        if (name is! String || name.isEmpty) return null;
        final effect = effectByCommandName(name);
        final modeId = effect?.protocolModeId;
        if (modeId == null) return null;
        return ProtocolEncoder.setMode(modeId);
      case 'speed':
        // Type check here; the byte-field range is enforced by the encoder,
        // which throws ArgumentError → 'invalid_parameter' (never a silent
        // wrap). The wider 0–100 app contract is validated in EffectEngine.
        final value = command.parameters['value'];
        if (value is! int) return null;
        return ProtocolEncoder.setSpeed(value);
      default:
        if (command.type == 'raw') {
          final bytes = command.parameters['bytes'];
          if (bytes is Uint8List) return bytes;
        }
        return null;
    }
  }
}
