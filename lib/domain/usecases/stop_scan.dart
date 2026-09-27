import '../../core/utils/app_logger.dart';
import '../repositories/ble_repository.dart';

/// Use case for stopping the BLE scan.
class StopScan {
  final BleRepository repository;

  StopScan(this.repository);

  Future<void> call() async {
    AppLog.debug('usecase: stopScan');
    await repository.stopScan();
  }
}
