// SPDX-License-Identifier: Apache-2.0

import '../../core/ble/protocol_encoder.dart';
import '../../core/utils/app_logger.dart';
import '../entities/light_command.dart';
import '../repositories/ble_repository.dart';

/// Use case for sending a color command.
///
/// Converts RGB to the exact HSV-based format used by the original APK.
class SendColorCommand {
  final BleRepository repository;

  SendColorCommand(this.repository);

  Future<void> call(int red, int green, int blue) {
    AppLog.debug('usecase: sendColor rgb=($red,$green,$blue)');
    final bytes = ProtocolEncoder.colorFromRGB(red, green, blue);
    return repository.sendCommand(LightCommand(type: 'color', bytes: bytes));
  }
}
