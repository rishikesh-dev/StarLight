// SPDX-License-Identifier: Apache-2.0

import '../entities/command_result.dart';
import '../entities/device_command.dart';
import '../entities/device_event.dart';
import '../entities/network_device.dart';
import '../entities/wled_config.dart';
import '../entities/wled_probe.dart';

/// Repository for WLED devices over the WLED JSON HTTP API.
///
/// Contract rules (shared with the MR Star flow):
/// - [sendCommand] never throws for expected device conditions; failures are
///   returned in [CommandResult] so callers can surface the real outcome.
/// - A saved configuration never implies the device is online: restored
///   devices are `disconnected` until a live HTTP exchange succeeds.
/// - Per-device requests are serialized so overlapping commands from rapid
///   UI input cannot interleave or clobber each other's confirmed state.
abstract class WledRepository {
  /// Shared device event stream (connected / disconnected / stateChanged /
  /// error), device-id keyed like the BLE registry.
  Stream<DeviceEvent> get events;

  /// Restores saved WLED devices. Restored devices are marked disconnected:
  /// reachability is only ever established by a live probe.
  Future<void> loadDevices();

  /// Lists registered WLED devices (persisted + session state).
  Future<List<NetworkDevice>> getWledDevices();

  /// Gets one registered WLED device by id.
  Future<NetworkDevice?> getWledDevice(String deviceId);

  /// Attempts to reach a WLED device at [host] and returns its reported
  /// identity, capabilities and current state in [WledProbe]. Never throws;
  /// configuration and network failures are carried in the probe result.
  Future<WledProbe> probe({
    required String host,
    required int port,
    required bool useHttps,
    String? name,
    int timeoutSeconds = 5,
  });

  /// Registers a probed device. Rejects a second registration of a
  /// host:port that is already in the registry.
  Future<CommandResult> addDevice(
    WledConfig config,
    NetworkDevice device, {
    String? name,
  });

  /// Removes a device and cancels any queued activity for it.
  Future<void> removeDevice(String deviceId);

  /// Renames a saved device (display name only; address is untouched).
  Future<void> renameDevice(String deviceId, String name);

  /// Sends a command to a device.
  ///
  /// The command is applied through the WLED JSON API and only reported as
  /// successful after the resulting state has been confirmed by the device
  /// (state echo, or a follow-up state read on firmwares that only answer
  /// `{"success": true}`). Unsupported commands fail with
  /// `unsupported_command` without touching the network.
  Future<CommandResult> sendCommand(String deviceId, DeviceCommand command);

  /// Reads the current state from the device and returns the updated device,
  /// or null when the device could not be reached.
  Future<NetworkDevice?> readState(String deviceId);

  /// Closes the underlying transport. After this, no further calls are
  /// valid.
  void dispose();
}
