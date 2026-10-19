import 'dart:async';

import 'package:starlight/domain/entities/command_result.dart';
import 'package:starlight/domain/entities/device_command.dart';
import 'package:starlight/domain/entities/device_profile.dart';
import 'package:starlight/domain/entities/device_state_update.dart';
import 'package:starlight/domain/entities/profile_verification.dart';
import 'package:starlight/domain/services/profile_executor.dart';

/// A scriptable [ProfileExecutor] for tests.
///
/// It records every attempted send and returns the verification result the test
/// configured, so tests never need real BLE. [isVerified] follows the last
/// [verify] call, mirroring the real executor's caching.
class FakeProfileExecutor implements ProfileExecutor {
  FakeProfileExecutor({
    this.verification = const ProfileVerification.notConnected(),
    this.result = const CommandResult.ok(),
  });

  /// Result returned by the next [verify] call.
  ProfileVerification verification;

  /// Result returned by the next [send] call.
  CommandResult result;

  /// Commands the router asked the executor to send, in order.
  final List<(DeviceProfile, DeviceCommand)> sent = [];

  int verifyCalls = 0;
  int resetCalls = 0;

  final Set<String> _verified = {};
  final StreamController<DeviceStateUpdate> _updates =
      StreamController<DeviceStateUpdate>.broadcast();

  /// Pushes a decoded notification update through [stateUpdates].
  void emit(DeviceStateUpdate update) => _updates.add(update);

  @override
  Stream<DeviceStateUpdate> get stateUpdates => _updates.stream;

  @override
  bool isVerified(String profileId) => _verified.contains(profileId);

  @override
  Future<ProfileVerification> verify(DeviceProfile profile) async {
    verifyCalls++;
    if (verification.isVerified) {
      _verified.add(profile.id);
    } else {
      _verified.remove(profile.id);
    }
    return verification;
  }

  @override
  Future<CommandResult> send(
    DeviceProfile profile,
    DeviceCommand command,
  ) async {
    sent.add((profile, command));
    return result;
  }

  @override
  Future<void> reset() async {
    resetCalls++;
    _verified.clear();
  }

  Future<void> dispose() => _updates.close();
}
