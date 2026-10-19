// SPDX-License-Identifier: Apache-2.0

import '../../core/ble/protocol_encoder.dart';
import '../../core/utils/app_logger.dart';
import '../entities/light_command.dart';
import '../repositories/ble_repository.dart';

/// Use case for sending a brightness command.
///
/// The brightness value is a 16-bit integer sent as big-endian bytes,
/// with a minimum of 3 (matching e1/d.java).
class SendBrightnessCommand {
  final BleRepository repository;

  SendBrightnessCommand(this.repository);

  Future<void> call(int brightness) {
    AppLog.debug('usecase: sendBrightness ($brightness)');
    final bytes = ProtocolEncoder.brightness(brightness);
    return repository.sendCommand(
      LightCommand(type: 'brightness', bytes: bytes),
    );
  }
}
