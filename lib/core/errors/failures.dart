/// Failures are returned by repositories to the presentation layer.
abstract class Failure {
  final String message;
  const Failure(this.message);

  @override
  String toString() => '$runtimeType: $message';
}

class BleFailure extends Failure {
  const BleFailure(super.message);
}

class BluetoothNotEnabledFailure extends BleFailure {
  BluetoothNotEnabledFailure() : super('Bluetooth is not enabled');
}

class BluetoothPermissionDeniedFailure extends BleFailure {
  BluetoothPermissionDeniedFailure() : super('Bluetooth permission denied');
}

class DeviceNotFoundFailure extends BleFailure {
  DeviceNotFoundFailure(String id) : super('Device not found: $id');
}

class ConnectionTimeoutFailure extends BleFailure {
  ConnectionTimeoutFailure() : super('Connection timed out');
}

class GattErrorFailure extends BleFailure {
  GattErrorFailure(int status) : super('GATT error: $status');
}

class ServiceNotFoundFailure extends BleFailure {
  ServiceNotFoundFailure(String uuid) : super('Service not found: $uuid');
}

class CharacteristicNotFoundFailure extends BleFailure {
  CharacteristicNotFoundFailure(String uuid) : super('Characteristic not found: $uuid');
}

class DisconnectedFailure extends BleFailure {
  DisconnectedFailure() : super('Device disconnected');
}
