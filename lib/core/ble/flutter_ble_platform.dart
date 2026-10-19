// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'ble_platform.dart';

/// Default [BlePlatform] implementation that delegates to [FlutterBluePlus].
class FlutterBlePlatform implements BlePlatform {
  const FlutterBlePlatform();

  @override
  Stream<BluetoothAdapterState> get adapterState =>
      FlutterBluePlus.adapterState;

  @override
  BluetoothAdapterState get adapterStateNow => FlutterBluePlus.adapterStateNow;

  @override
  Stream<List<ScanResult>> get scanResults => FlutterBluePlus.scanResults;

  @override
  Future<void> startScan({
    Duration? timeout,
    AndroidScanMode androidScanMode = AndroidScanMode.lowPower,
    bool continuousUpdates = false,
  }) {
    return FlutterBluePlus.startScan(
      timeout: timeout,
      androidScanMode: androidScanMode,
      continuousUpdates: continuousUpdates,
    );
  }

  @override
  Future<void> stopScan() {
    return FlutterBluePlus.stopScan();
  }

  @override
  Future<bool> get isSupported => FlutterBluePlus.isSupported;

  @override
  Future<void> turnOn({int timeout = 60}) =>
      FlutterBluePlus.turnOn(timeout: timeout);
}
