// SPDX-License-Identifier: Apache-2.0

import '../entities/command_result.dart';
import '../entities/device_command.dart';
import '../entities/device_profile.dart';
import '../entities/device_state_update.dart';
import '../entities/profile_verification.dart';

/// Executes a custom BLE GATT [DeviceProfile] against the single connected
/// device.
///
/// Implementations must route every operation through the existing coordinated
/// BLE transport (never open a second connection), verify the configured UUIDs
/// and characteristic properties before use, and report a real
/// [CommandResult] — a command is only successful when the transport accepted
/// the write.
abstract class ProfileExecutor {
  /// Live notification updates decoded with the profile's notification format.
  Stream<DeviceStateUpdate> get stateUpdates;

  /// Whether [profileId] is currently verified against the connected device.
  bool isVerified(String profileId);

  /// Verifies [profile] against the currently connected device's live GATT
  /// table and caches the result when it matches. Never fabricates success.
  Future<ProfileVerification> verify(DeviceProfile profile);

  /// Sends [command] using [profile]. Returns a failure (never throws for
  /// expected device conditions) when the profile is not verified, the command
  /// has no mapping, the write fails, or the device disconnects.
  Future<CommandResult> send(DeviceProfile profile, DeviceCommand command);

  /// Clears cached verification and cancels notification subscriptions. Called
  /// on disconnect so a stale verification can never be reused.
  Future<void> reset();
}
