import '../../core/utils/app_logger.dart';
import '../entities/ble_device.dart';
import '../repositories/ble_repository.dart';

/// Use case for scanning BLE devices.
class ScanDevices {
  final BleRepository repository;

  ScanDevices(this.repository);

  Stream<List<BleDevice>> call() {
    AppLog.debug('usecase: scanDevices');
    return repository.scanDevices();
  }
}
