// SPDX-License-Identifier: Apache-2.0

/// BLE protocol constants extracted from the decompiled MR Star APK.
///
/// Service UUID:   FFF0 (0000FFF0-0000-1000-8000-00805f9b34fb)
/// Write Char UUID: FFF3 (0000FFF3-0000-1000-8000-00805f9b34fb)
/// Notify Char UUID: FFF4 (0000FFF4-0000-1000-8000-00805f9b34fb)
/// Descriptor:      2902 (00002902-0000-1000-8000-00805f9b34fb)
class BleConstants {
  BleConstants._();

  static const String serviceUuid = '0000fff0-0000-1000-8000-00805f9b34fb';
  static const String writeCharUuid = '0000fff3-0000-1000-8000-00805f9b34fb';
  static const String notifyCharUuid = '0000fff4-0000-1000-8000-00805f9b34fb';
  static const String cccDescriptorUuid =
      '00002902-0000-1000-8000-00805f9b34fb';

  /// The device name prefix used to identify MR Star controllers.
  static const String deviceNamePrefix = 'GATT--DEMO';

  /// Maximum BLE MTU for write-without-response chunking.
  static const int maxWriteChunkSize = 20;

  /// Write timeout in milliseconds.
  static const int writeTimeoutMs = 5000;

  /// Packet start byte.
  static const int startByte = 0xBC;

  /// Packet end byte.
  static const int endByte = 0x55;
}
