import '../../core/utils/app_logger.dart';
import '../entities/connection_state.dart';
import '../repositories/ble_repository.dart';

/// Use case for connecting to a BLE device.
class ConnectDevice {
  final BleRepository repository;

  ConnectDevice(this.repository);

  Stream<DeviceConnectionState> call(String deviceId) {
    AppLog.debug('usecase: connectDevice ($deviceId)');
    return repository.connectDevice(deviceId);
  }
}
