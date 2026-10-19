// SPDX-License-Identifier: Apache-2.0

import '../../core/utils/app_logger.dart';
import '../entities/connection_state.dart';
import '../repositories/ble_repository.dart';
import '../repositories/saved_device_repository.dart';

/// Use case: read the paired device and attempt to connect.
/// Returns a stream of connection-state updates, or an empty stream if
/// no device was paired.
class ConnectToSavedDevice {
  final BleRepository _bleRepository;
  final SavedDeviceRepository _savedRepo;

  ConnectToSavedDevice(this._bleRepository, this._savedRepo);

  Stream<DeviceConnectionState> call() async* {
    final saved = await _savedRepo.load();
    if (saved == null) {
      AppLog.debug('ConnectToSavedDevice: no paired device');
      return;
    }
    AppLog.info(
      'ConnectToSavedDevice: auto-connecting to ${saved.id} (${saved.name})',
    );
    yield* _bleRepository.connectDevice(saved.id);
  }
}
