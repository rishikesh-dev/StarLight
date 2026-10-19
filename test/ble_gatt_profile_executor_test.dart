import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:starlight/core/errors/exceptions.dart';
import 'package:starlight/data/adapters/ble_gatt_profile_executor.dart';
import 'package:starlight/data/datasources/ble_datasource.dart';
import 'package:starlight/domain/entities/device_capability.dart';
import 'package:starlight/domain/entities/device_command.dart';
import 'package:starlight/domain/entities/device_profile.dart';
import 'package:starlight/domain/entities/device_state_update.dart';
import 'package:starlight/domain/entities/notification_format.dart';
import 'package:starlight/domain/entities/profile_command.dart';
import 'package:starlight/domain/entities/profile_verification.dart';

class MockBleDataSource extends Mock implements BleDataSource {}

class MockBluetoothCharacteristic extends Mock
    implements BluetoothCharacteristic {}

CommandTemplate _t(String source) => CommandTemplate.parse(source).template!;

DeviceProfile _profile({
  GattWriteMode writeMode = GattWriteMode.automatic,
  String? notifyUuid,
  NotificationFormat? notifications,
}) {
  return DeviceProfile(
    id: 'p1',
    name: 'Test strip',
    serviceUuid: 'fff0',
    writeCharacteristicUuid: 'fff3',
    notifyCharacteristicUuid: notifyUuid,
    writeMode: writeMode,
    capabilities: const {DeviceCapability.power, DeviceCapability.brightness},
    commands: GattCommandSet(
      powerOn: _t('A1'),
      powerOff: _t('A0'),
      brightness: _t('B0 {brightness}'),
    ),
    notifications: notifications,
  );
}

MockBluetoothCharacteristic _characteristic({
  bool write = false,
  bool writeWithoutResponse = false,
  bool notify = false,
  Stream<List<int>>? values,
}) {
  final char = MockBluetoothCharacteristic();
  when(() => char.properties).thenReturn(
    CharacteristicProperties(
      write: write,
      writeWithoutResponse: writeWithoutResponse,
      notify: notify,
    ),
  );
  when(() => char.onValueReceived)
      .thenAnswer((_) => values ?? const Stream<List<int>>.empty());
  return char;
}

void main() {
  late MockBleDataSource dataSource;
  late StreamController<BluetoothConnectionState> connectionController;

  setUpAll(() {
    registerFallbackValue('');
    registerFallbackValue(Uint8List(0));
    registerFallbackValue(false);
    registerFallbackValue(MockBluetoothCharacteristic());
  });

  setUp(() {
    dataSource = MockBleDataSource();
    connectionController =
        StreamController<BluetoothConnectionState>.broadcast();
    when(() => dataSource.connectionState)
        .thenAnswer((_) => connectionController.stream);
    when(() => dataSource.isConnected).thenReturn(true);
    when(() => dataSource.subscribeNotifications(any()))
        .thenAnswer((_) async {});
    when(() => dataSource.unsubscribeNotifications(any()))
        .thenAnswer((_) async {});
    when(
      () => dataSource.writeBytes(
        any(),
        characteristic: any(named: 'characteristic'),
        withoutResponse: any(named: 'withoutResponse'),
      ),
    ).thenAnswer((_) async {});

    addTearDown(connectionController.close);
  });

  BleGattProfileExecutor newExecutor() {
    final executor = BleGattProfileExecutor(dataSource);
    addTearDown(executor.dispose);
    return executor;
  }

  void stubTarget({
    required bool write,
    required bool writeWithoutResponse,
    BluetoothCharacteristic? notify,
  }) {
    when(
      () => dataSource.resolveGattTarget(
        serviceUuid: any(named: 'serviceUuid'),
        writeCharacteristicUuid: any(named: 'writeCharacteristicUuid'),
        notifyCharacteristicUuid: any(named: 'notifyCharacteristicUuid'),
      ),
    ).thenAnswer(
      (_) async => ResolvedGattTarget(
        writeCharacteristic: _characteristic(
          write: write,
          writeWithoutResponse: writeWithoutResponse,
        ),
        notifyCharacteristic: notify,
      ),
    );
  }

  group('verify', () {
    test('never verifies the built-in profile', () async {
      final executor = newExecutor();
      final result = await executor.verify(DeviceProfile.mrStar);
      expect(result.status, ProfileVerificationStatus.unverified);
    });

    test('reports notConnected when no device is connected', () async {
      when(() => dataSource.isConnected).thenReturn(false);
      final executor = newExecutor();
      final result = await executor.verify(_profile());
      expect(result.status, ProfileVerificationStatus.notConnected);
      expect(executor.isVerified('p1'), isFalse);
    });

    test('fails when the configured service is missing', () async {
      when(
        () => dataSource.resolveGattTarget(
          serviceUuid: any(named: 'serviceUuid'),
          writeCharacteristicUuid: any(named: 'writeCharacteristicUuid'),
          notifyCharacteristicUuid: any(named: 'notifyCharacteristicUuid'),
        ),
      ).thenThrow(ServiceNotFoundException('fff0'));

      final executor = newExecutor();
      final result = await executor.verify(_profile());
      expect(result.status, ProfileVerificationStatus.failed);
      expect(result.message, contains('fff0'));
      expect(executor.isVerified('p1'), isFalse);
    });

    test('automatic mode prefers write-without-response', () async {
      stubTarget(write: true, writeWithoutResponse: true);
      final executor = newExecutor();
      final result = await executor.verify(_profile());
      expect(result.status, ProfileVerificationStatus.verified);
      expect(result.writeWithoutResponse, isTrue);
      expect(result.supportsWriteWithResponse, isTrue);
      expect(executor.isVerified('p1'), isTrue);
    });

    test('automatic mode falls back to write-with-response', () async {
      stubTarget(write: true, writeWithoutResponse: false);
      final executor = newExecutor();
      final result = await executor.verify(_profile());
      expect(result.status, ProfileVerificationStatus.verified);
      expect(result.writeWithoutResponse, isFalse);
    });

    test('fails when an explicit mode is unsupported by the device', () async {
      stubTarget(write: true, writeWithoutResponse: false);
      final executor = newExecutor();
      final result = await executor.verify(
        _profile(writeMode: GattWriteMode.withoutResponse),
      );
      expect(result.status, ProfileVerificationStatus.failed);
      expect(result.message, contains('without response'));
      expect(executor.isVerified('p1'), isFalse);
    });

    test('fails when the characteristic supports no write at all', () async {
      stubTarget(write: false, writeWithoutResponse: false);
      final executor = newExecutor();
      final result = await executor.verify(_profile());
      expect(result.status, ProfileVerificationStatus.failed);
      expect(result.message, contains('not writable'));
    });

    test('subscribes to notifications when the profile defines them', () async {
      final notify = MockBluetoothCharacteristic();
      when(() => notify.properties)
          .thenReturn(const CharacteristicProperties(notify: true));
      when(() => notify.onValueReceived)
          .thenAnswer((_) => const Stream<List<int>>.empty());
      stubTarget(write: true, writeWithoutResponse: true, notify: notify);

      final executor = newExecutor();
      final result = await executor.verify(
        _profile(
          notifyUuid: 'fff4',
          notifications: const NotificationFormat([
            NotificationRule(
              target: NotificationTarget.brightness,
              byteOffset: 0,
            ),
          ]),
        ),
      );
      expect(result.status, ProfileVerificationStatus.verified);
      expect(result.supportsNotify, isTrue);
      verify(() => dataSource.subscribeNotifications(notify)).called(1);
    });

    test(
      'does not subscribe when the profile has no notification rules',
      () async {
        final notify = MockBluetoothCharacteristic();
        when(() => notify.properties)
            .thenReturn(const CharacteristicProperties(notify: true));
        when(() => notify.onValueReceived)
            .thenAnswer((_) => const Stream<List<int>>.empty());
        stubTarget(write: true, writeWithoutResponse: true, notify: notify);

        final executor = newExecutor();
        await executor.verify(_profile(notifyUuid: 'fff4'));
        verifyNever(() => dataSource.subscribeNotifications(any()));
      },
    );

    test('decodes notification packets into state updates', () async {
      final notify = MockBluetoothCharacteristic();
      final controller = StreamController<List<int>>.broadcast();
      when(() => notify.properties)
          .thenReturn(const CharacteristicProperties(notify: true));
      when(() => notify.onValueReceived).thenAnswer((_) => controller.stream);
      stubTarget(write: true, writeWithoutResponse: true, notify: notify);

      final executor = newExecutor();
      final updates = <DeviceStateUpdate>[];
      final sub = executor.stateUpdates.listen(updates.add);

      await executor.verify(
        _profile(
          notifyUuid: 'fff4',
          notifications: const NotificationFormat([
            NotificationRule(target: NotificationTarget.power, byteOffset: 0),
            NotificationRule(
              target: NotificationTarget.brightness,
              byteOffset: 1,
            ),
          ]),
        ),
      );

      controller.add([1, 200]);
      await pumpEventQueue();

      expect(updates, hasLength(2));
      expect(updates[0].type, StateUpdateType.power);
      expect(updates[0].value, isTrue);
      expect(updates[1].type, StateUpdateType.brightness);
      expect(updates[1].value, 200);

      await sub.cancel();
      await controller.close();
    });
  });

  group('send', () {
    test('refuses to send before the profile is verified', () async {
      final executor = newExecutor();
      final result = await executor.send(_profile(), DeviceCommand.power(true));
      expect(result.success, isFalse);
      expect(result.error, 'profile_not_verified');
      verifyNever(
        () => dataSource.writeBytes(
          any(),
          characteristic: any(named: 'characteristic'),
          withoutResponse: any(named: 'withoutResponse'),
        ),
      );
    });

    test('reports an unsupported command type', () async {
      stubTarget(write: true, writeWithoutResponse: true);
      final executor = newExecutor();
      final profile = _profile();
      await executor.verify(profile);

      final result = await executor.send(
        profile,
        DeviceCommand.custom('effect', const {}),
      );
      expect(result.success, isFalse);
      expect(result.error, 'unsupported_command');
    });

    test('encodes and writes brightness through the resolved target', () async {
      stubTarget(write: true, writeWithoutResponse: true);
      final executor = newExecutor();
      final profile = _profile();
      await executor.verify(profile);

      final result = await executor.send(
        profile,
        DeviceCommand.brightness(1000),
      );
      expect(result.success, isTrue);

      final captured = verify(
        () => dataSource.writeBytes(
          captureAny(),
          characteristic: captureAny(named: 'characteristic'),
          withoutResponse: captureAny(named: 'withoutResponse'),
        ),
      ).captured;
      final bytes = captured.whereType<Uint8List>().single;
      final characteristic = captured
          .whereType<BluetoothCharacteristic>()
          .single;
      final withoutResponse = captured.whereType<bool>().single;
      expect(bytes, [0xB0, 0xFF]);
      expect(withoutResponse, isTrue);
      expect(characteristic, isNotNull);
    });

    test('maps a write timeout to a typed failure', () async {
      stubTarget(write: true, writeWithoutResponse: true);
      final executor = newExecutor();
      final profile = _profile();
      await executor.verify(profile);
      when(
        () => dataSource.writeBytes(
          any(),
          characteristic: any(named: 'characteristic'),
          withoutResponse: any(named: 'withoutResponse'),
        ),
      ).thenThrow(TimeoutException('timed out'));

      final result = await executor.send(profile, DeviceCommand.power(true));
      expect(result.success, isFalse);
      expect(result.error, 'write_timeout');
    });

    test('maps a disconnect to a typed failure', () async {
      stubTarget(write: true, writeWithoutResponse: true);
      final executor = newExecutor();
      final profile = _profile();
      await executor.verify(profile);
      when(
        () => dataSource.writeBytes(
          any(),
          characteristic: any(named: 'characteristic'),
          withoutResponse: any(named: 'withoutResponse'),
        ),
      ).thenThrow(DisconnectedException());

      final result = await executor.send(profile, DeviceCommand.power(true));
      expect(result.success, isFalse);
      expect(result.error, 'not_connected');
    });

    test('maps a missing characteristic back to a typed failure', () async {
      stubTarget(write: true, writeWithoutResponse: true);
      final executor = newExecutor();
      final profile = _profile();
      await executor.verify(profile);
      when(
        () => dataSource.writeBytes(
          any(),
          characteristic: any(named: 'characteristic'),
          withoutResponse: any(named: 'withoutResponse'),
        ),
      ).thenThrow(CharacteristicNotFoundException('fff3'));

      final result = await executor.send(profile, DeviceCommand.power(true));
      expect(result.success, isFalse);
      expect(result.error, 'characteristic_not_found');
    });
  });

  group('lifecycle', () {
    test('reset clears verification so the next send is refused', () async {
      stubTarget(write: true, writeWithoutResponse: true);
      final executor = newExecutor();
      final profile = _profile();
      await executor.verify(profile);
      expect(executor.isVerified(profile.id), isTrue);

      await executor.reset();
      expect(executor.isVerified(profile.id), isFalse);
      final result = await executor.send(profile, DeviceCommand.power(true));
      expect(result.error, 'profile_not_verified');
    });

    test('a disconnect resets the cached verification', () async {
      stubTarget(write: true, writeWithoutResponse: true);
      final executor = newExecutor();
      final profile = _profile();
      await executor.verify(profile);
      expect(executor.isVerified(profile.id), isTrue);

      connectionController.add(BluetoothConnectionState.disconnected);
      await pumpEventQueue();

      expect(executor.isVerified(profile.id), isFalse);
    });
  });
}
