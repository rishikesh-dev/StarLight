/// Exceptions that can occur during BLE operations.
abstract class BleException implements Exception {
  final String message;
  BleException(this.message);

  @override
  String toString() => '$runtimeType: $message';
}

class BluetoothNotEnabledException extends BleException {
  BluetoothNotEnabledException() : super('Bluetooth is not enabled');
}

class BluetoothPermissionDeniedException extends BleException {
  BluetoothPermissionDeniedException() : super('Bluetooth permission denied');
}

class DeviceNotFoundException extends BleException {
  DeviceNotFoundException(String id) : super('Device not found: $id');
}

class ConnectionTimeoutException extends BleException {
  ConnectionTimeoutException() : super('Connection timed out');
}

class GattErrorException extends BleException {
  final int status;
  GattErrorException(this.status) : super('GATT error: $status (status=$status)');
}

class ServiceNotFoundException extends BleException {
  ServiceNotFoundException(String uuid) : super('Service not found: $uuid');
}

class CharacteristicNotFoundException extends BleException {
  CharacteristicNotFoundException(String uuid) : super('Characteristic not found: $uuid');
}

class CharacteristicWriteException extends BleException {
  CharacteristicWriteException(String msg) : super('Write failed: $msg');
}

class DisconnectedException extends BleException {
  DisconnectedException() : super('Device disconnected');
}
