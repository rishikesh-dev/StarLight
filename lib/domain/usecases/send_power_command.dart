// SPDX-License-Identifier: Apache-2.0

import '../../core/ble/protocol_encoder.dart';
import '../../core/utils/app_logger.dart';
import '../entities/light_command.dart';
import '../repositories/ble_repository.dart';

/// Use case for sending a power command.
class SendPowerCommand {
  final BleRepository repository;

  SendPowerCommand(this.repository);

  Future<void> call(bool on) {
    AppLog.debug('usecase: sendPower on=$on');
    final bytes = on ? ProtocolEncoder.powerOn() : ProtocolEncoder.powerOff();
    return repository.sendCommand(LightCommand(type: 'power', bytes: bytes));
  }
}
