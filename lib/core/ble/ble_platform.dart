// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

/// Abstraction over [FlutterBluePlus] static methods that interact with the
/// Bluetooth adapter and scanning.
///
/// The default implementation delegates to [FlutterBluePlus]. Tests can provide
/// a mock implementation to verify scan/adapter-state behavior without real
/// hardware.
abstract class BlePlatform {
  /// Stream of Bluetooth adapter state changes.
  Stream<BluetoothAdapterState> get adapterState;

  /// Synchronous snapshot of the current adapter state.
  BluetoothAdapterState get adapterStateNow;

  /// Stream of scan results.
  Stream<List<ScanResult>> get scanResults;

  /// Starts a BLE scan.
  Future<void> startScan({
    Duration? timeout,
    AndroidScanMode androidScanMode,
    bool continuousUpdates,
  });

  /// Stops any active BLE scan.
  Future<void> stopScan();

  /// Whether the platform supports Bluetooth (false on unsupported hardware).
  Future<bool> get isSupported;

  /// Requests the platform to turn the Bluetooth adapter on. On Android this
  /// shows the system enable dialog and completes once the adapter is on.
  /// Throws when the user declines or the adapter cannot be enabled.
  Future<void> turnOn({int timeout});
}
