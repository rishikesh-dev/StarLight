// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:permission_handler/permission_handler.dart';

/// Narrow seam over the platform runtime-permission flow.
///
/// Isolates the BLE data source from the `permission_handler` plugin so the
/// permission logic can be exercised deterministically in tests without
/// platform channels or system dialogs.
abstract class BlePermissionGateway {
  /// Whether every permission required to scan/connect is currently granted.
  Future<bool> hasRequiredPermissions();

  /// Whether any required permission is permanently denied. When true the
  /// system will not show a request dialog again and the user must change it
  /// in the app settings.
  Future<bool> isPermanentlyDenied();

  /// Requests every required permission and returns whether they are granted
  /// afterwards.
  ///
  /// Implementations MUST issue exactly one platform request. Android rejects
  /// a second concurrent runtime-permission request with an error, which
  /// previously propagated out of the startup readiness check and aborted it.
  Future<bool> requestRequiredPermissions();

  /// Opens the OS app-settings page for this app so a permanently denied
  /// permission can be granted manually.
  Future<void> openSystemSettings();
}

/// Default [BlePermissionGateway] backed by `permission_handler`.
///
/// Only the Bluetooth runtime permissions gate scanning/connecting:
/// - Android >= 12: [Permission.bluetoothScan] and [Permission.bluetoothConnect]
///   are the real runtime permissions.
/// - Android <= 11: the plugin reports both as granted when the legacy
///   `BLUETOOTH` manifest permission is present, so the same check is correct.
///
/// Location is deliberately NOT required here. The `flutter_blue_plus`
/// transport requests `ACCESS_FINE_LOCATION` itself when it is actually needed
/// (Android <= 11); requiring it in the readiness check only added an
/// irrelevant dialog on modern devices.
class PermissionHandlerBlePermissionGateway implements BlePermissionGateway {
  const PermissionHandlerBlePermissionGateway();

  /// The permissions that gate scanning and connecting. Exposed so the
  /// required set can be asserted in tests without touching the platform.
  static const List<Permission> requiredPermissions = [
    Permission.bluetoothScan,
    Permission.bluetoothConnect,
  ];

  @override
  Future<bool> hasRequiredPermissions() async {
    if (!Platform.isAndroid) return true;
    for (final permission in requiredPermissions) {
      if (!await permission.isGranted) return false;
    }
    return true;
  }

  @override
  Future<bool> isPermanentlyDenied() async {
    if (!Platform.isAndroid) return false;
    for (final permission in requiredPermissions) {
      if ((await permission.status).isPermanentlyDenied) return true;
    }
    return false;
  }

  @override
  Future<bool> requestRequiredPermissions() async {
    if (!Platform.isAndroid) return true;
    // A single batched request. Never request permissions concurrently: the
    // Android plugin rejects a second in-flight request with an error.
    final statuses = await requiredPermissions.request();
    for (final permission in requiredPermissions) {
      if (!(statuses[permission]?.isGranted ?? false)) return false;
    }
    return true;
  }

  @override
  Future<void> openSystemSettings() async {
    await openAppSettings();
  }
}
