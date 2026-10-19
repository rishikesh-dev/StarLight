import 'package:flutter_test/flutter_test.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:starlight/core/ble/ble_permission_gateway.dart';

/// Regression tests for the BLE permission gateway.
///
/// Guards the startup regression where three runtime permissions were
/// requested concurrently. Android rejects a second in-flight request, which
/// aborted the startup readiness flow; the gateway now performs one batched
/// request and no longer requires location.
void main() {
  group('PermissionHandlerBlePermissionGateway', () {
    test('requires the Bluetooth permissions but not location', () {
      final required =
          PermissionHandlerBlePermissionGateway.requiredPermissions;

      expect(required, contains(Permission.bluetoothScan));
      expect(required, contains(Permission.bluetoothConnect));
      expect(
        required,
        isNot(contains(Permission.locationWhenInUse)),
        reason:
            'location must not gate scanning on Android 12+; the transport '
            'requests ACCESS_FINE_LOCATION itself only on Android <= 11',
      );
    });

    test('treats non-Android platforms as already granted', () async {
      // The test host is not Android, so the gateway must not touch the
      // platform permission APIs at all.
      const gateway = PermissionHandlerBlePermissionGateway();

      expect(await gateway.hasRequiredPermissions(), isTrue);
      expect(await gateway.requestRequiredPermissions(), isTrue);
      expect(await gateway.isPermanentlyDenied(), isFalse);
    });
  });
}
