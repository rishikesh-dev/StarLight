import '../../core/utils/app_logger.dart';
import '../repositories/ble_repository.dart';

/// Use case for disconnecting from the BLE device.
class DisconnectDevice {
  final BleRepository repository;

  DisconnectDevice(this.repository);

  Future<void> call() async {
    AppLog.debug('usecase: disconnectDevice');
    await repository.disconnectDevice();
  }
}
