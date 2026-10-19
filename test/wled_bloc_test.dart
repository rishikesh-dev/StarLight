import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:starlight/domain/entities/command_result.dart';
import 'package:starlight/domain/entities/device_capability.dart';
import 'package:starlight/domain/entities/device_command.dart';
import 'package:starlight/domain/entities/device_event.dart';
import 'package:starlight/domain/entities/device_type.dart';
import 'package:starlight/domain/entities/network_device.dart';
import 'package:starlight/domain/entities/rgb_color.dart';
import 'package:starlight/domain/entities/wled_config.dart';
import 'package:starlight/domain/entities/wled_probe.dart';
import 'package:starlight/domain/repositories/wled_repository.dart';
import 'package:starlight/presentation/bloc/wled/wled_bloc.dart';
import 'package:starlight/presentation/bloc/wled/wled_event.dart';
import 'package:starlight/presentation/bloc/wled/wled_state.dart';

Future<void> pumpEventQueue() async {
  await Future<void>.delayed(Duration.zero);
}

/// Waits for the bloc to emit a state matching [predicate].
Future<void> waitForState(
  WledBloc bloc,
  bool Function(WledState) predicate,
) async {
  await bloc.stream.firstWhere(predicate);
}

class MockWledRepository extends Mock implements WledRepository {}

NetworkDevice makeWledDevice({
  String id = 'wled-aabbccddeeff',
  String name = 'WLED Desk',
  String address = 'wled.local:80',
  bool on = true,
  int brightness = 200,
  RGBColor? color = const RGBColor(10, 20, 30),
  List<DeviceCapability> capabilities = const [
    DeviceCapability.power,
    DeviceCapability.brightness,
    DeviceCapability.color,
    DeviceCapability.effect,
    DeviceCapability.speed,
    DeviceCapability.palette,
  ],
  List<String> effects = const ['Solid', 'Rainbow'],
  List<String> palettes = const ['Default'],
  Map<String, dynamic> metadata = const {},
  String? effect,
}) {
  return NetworkDevice(
    id: id,
    name: name,
    type: DeviceType.light,
    address: address,
    capabilities: capabilities,
    connectionState:
        NetworkConnectionState.connected, // overwritten by the bloc
    brightness: brightness,
    color: color,
    isOn: on,
    ledCount: 60,
    firmwareVersion: '0.14.4',
    supportedEffects: effects,
    supportedPalettes: palettes,
    metadata: metadata,
    effect: effect,
  );
}

void main() {
  late MockWledRepository repo;
  late WledBloc bloc;
  late StreamController<DeviceEvent> eventController;

  setUpAll(() {
    registerFallbackValue(DeviceCommand.power(true));
    registerFallbackValue(DeviceCommand.brightness(50));
    registerFallbackValue(const WledConfig(host: 'test.local'));
    registerFallbackValue(
      NetworkDevice(
        id: 'test',
        name: 'Test',
        type: DeviceType.light,
        address: 'test:80',
        capabilities: const [],
        connectionState: NetworkConnectionState.disconnected,
      ),
    );
  });

  setUp(() {
    repo = MockWledRepository();
    eventController = StreamController<DeviceEvent>.broadcast();
    when(() => repo.events).thenAnswer((_) => eventController.stream);
    when(() => repo.dispose()).thenReturn(null);
    bloc = WledBloc(repo);
  });

  tearDown(() async {
    await bloc.close();
    await eventController.close();
  });

  group('WledDevicesLoad', () {
    test('maps persisted devices; restored devices are unreachable', () async {
      when(() => repo.getWledDevices()).thenAnswer(
        (_) async => [makeWledDevice(), makeWledDevice(id: 'wled-2')],
      );

      bloc.add(WledDevicesLoad());
      await waitForState(bloc, (s) => !s.loading);

      final state = bloc.state;
      expect(state.loading, isFalse);
      expect(state.devices, hasLength(2));
      expect(state.devices['wled-aabbccddeeff']!.reachable, isFalse);
      expect(state.devices['wled-2']!.reachable, isFalse);
    });
  });

  group('connectivity test', () {
    test('success surfaces version and led count', () async {
      when(
        () => repo.probe(
          host: '192.168.1.5',
          port: 80,
          useHttps: false,
          name: null,
        ),
      ).thenAnswer(
        (_) async =>
            WledProbe.success(makeWledDevice(address: '192.168.1.5:80')),
      );

      bloc.add(
        const WledConnectionTest(host: '192.168.1.5', port: 80, https: false),
      );
      await waitForState(bloc, (s) => s.probe != null);

      final probe = bloc.state.probe!;
      expect(probe.success, isTrue);
      expect(probe.version, '0.14.4');
      expect(probe.ledCount, 60);
      expect(probe.matches('192.168.1.5', 80, false), isTrue);
    });

    test('failure surfaces the error message', () async {
      when(() => repo.probe(host: 'bad', port: 80, useHttps: false, name: null))
          .thenAnswer(
            (_) async =>
                const WledProbe.failure('dns_failure', 'Could not resolve bad'),
          );

      bloc.add(const WledConnectionTest(host: 'bad', port: 80, https: false));
      await waitForState(bloc, (s) => s.probe != null);

      final probe = bloc.state.probe!;
      expect(probe.success, isFalse);
      expect(probe.error, 'Could not resolve bad');
    });

    test('probe progress flags reset after the test', () async {
      when(() => repo.probe(host: 'ok', port: 80, useHttps: false, name: null))
          .thenAnswer(
            (_) async => const WledProbe.failure('timeout', 'timed out'),
          );

      bloc.add(const WledConnectionTest(host: 'ok', port: 80, https: false));
      await waitForState(bloc, (s) => !s.probeInProgress);
      expect(bloc.state.probeInProgress, isFalse);
    });
  });

  group('add device', () {
    test(
      'registers after a fresh probe and keeps the device in state',
      () async {
        final device = makeWledDevice(address: '10.0.0.2:80');
        when(
          () => repo.probe(
            host: '10.0.0.2',
            port: 80,
            useHttps: false,
            name: 'Desk',
          ),
        ).thenAnswer((_) async => WledProbe.success(device));
        when(() => repo.addDevice(any(), any(), name: 'Desk'))
            .thenAnswer((_) async => const CommandResult.ok());
        when(
          () => repo.getWledDevice(device.id),
        ).thenAnswer((_) async => makeWledDevice(id: device.id, name: 'Desk'));

        bloc.add(
          const WledDeviceAdd(
            host: '10.0.0.2',
            port: 80,
            https: false,
            name: 'Desk',
          ),
        );
        await waitForState(bloc, (s) => s.device(device.id) != null);

        final info = bloc.state.device(device.id);
        expect(info, isNotNull);
        expect(info!.name, 'Desk');
        expect(info.reachable, isTrue);
        expect(info.capabilities, isNotEmpty);
        expect(bloc.state.addInProgress, isFalse);
      },
    );

    test(
      'duplicate registration surfaces the error and adds nothing',
      () async {
        when(
          () => repo.probe(
            host: '10.0.0.2',
            port: 80,
            useHttps: false,
            name: null,
          ),
        ).thenAnswer(
          (_) async =>
              WledProbe.success(makeWledDevice(address: '10.0.0.2:80')),
        );
        when(() => repo.addDevice(any(), any(), name: null)).thenAnswer(
          (_) async =>
              const CommandResult.failure('duplicate_device', 'already added'),
        );

        bloc.add(const WledDeviceAdd(host: '10.0.0.2', port: 80, https: false));
        await waitForState(bloc, (s) => !s.addInProgress);

        expect(bloc.state.devices, isEmpty);
        expect(bloc.state.probe!.success, isFalse);
        expect(bloc.state.probe!.error, 'already added');
      },
    );
  });

  group('refresh', () {
    test('refresh updates confirmed state and marks reachable', () async {
      final device = makeWledDevice(on: false, brightness: 30);
      when(() => repo.getWledDevice(device.id)).thenAnswer((_) async => device);
      // Seed state via load.
      when(() => repo.getWledDevices()).thenAnswer((_) async => [device]);
      bloc.add(WledDevicesLoad());
      await waitForState(bloc, (s) => !s.loading);

      when(() => repo.readState(device.id)).thenAnswer((_) async => device);

      bloc.add(WledDeviceRefresh(device.id));
      await waitForState(bloc, (s) => !s.device(device.id)!.busy);

      final info = bloc.state.device(device.id)!;
      expect(info.reachable, isTrue);
      expect(info.on, isFalse);
      expect(info.brightness255, 30);
      expect(info.busy, isFalse);
    });

    test('unreachable refresh reports the error', () async {
      final device = makeWledDevice();
      when(() => repo.getWledDevices()).thenAnswer((_) async => [device]);
      bloc.add(WledDevicesLoad());
      await waitForState(bloc, (s) => !s.loading);
      when(() => repo.readState(device.id)).thenAnswer((_) async => null);

      bloc.add(WledDeviceRefresh(device.id));
      await waitForState(bloc, (s) => !s.device(device.id)!.busy);

      final info = bloc.state.device(device.id)!;
      expect(info.reachable, isFalse);
      expect(info.error, 'Could not reach the device');
      expect(info.busy, isFalse);
    });
  });

  group('commands', () {
    /// Seeds one reachable device in the bloc state.
    Future<NetworkDevice> seed() async {
      final device = makeWledDevice();
      when(() => repo.getWledDevice(device.id)).thenAnswer((_) async => device);
      when(() => repo.getWledDevices()).thenAnswer((_) async => [device]);
      bloc.add(WledDevicesLoad());
      // Mark reachable so commands pass the gate.
      eventController.add(
        DeviceEvent.connectionChanged(deviceId: device.id, connected: true),
      );
      await pumpEventQueue();
      return device;
    }

    test('power toggles confirmed state', () async {
      final offDevice = makeWledDevice(on: false);
      when(() => repo.getWledDevice(offDevice.id))
          .thenAnswer((_) async => offDevice);
      when(() => repo.getWledDevices()).thenAnswer((_) async => [offDevice]);
      bloc.add(WledDevicesLoad());
      await waitForState(bloc, (s) => !s.loading);
      eventController.add(
        DeviceEvent.connectionChanged(deviceId: offDevice.id, connected: true),
      );
      await pumpEventQueue();

      when(() => repo.sendCommand(offDevice.id, DeviceCommand.power(true)))
          .thenAnswer((_) async => const CommandResult.ok());
      when(() => repo.getWledDevice(offDevice.id))
          .thenAnswer((_) async => makeWledDevice(id: offDevice.id, on: true));

      bloc.add(WledPower(offDevice.id, true));
      await waitForState(bloc, (s) => !s.device(offDevice.id)!.busy);

      expect(bloc.state.device(offDevice.id)!.on, isTrue);
    });

    test('commands are refused without I/O when unreachable', () async {
      final device = await seed();
      // Flip to unreachable.
      eventController.add(
        DeviceEvent.connectionChanged(deviceId: device.id, connected: false),
      );
      await pumpEventQueue();

      bloc.add(WledPower(device.id, true));
      await waitForState(bloc, (s) => s.device(device.id)!.error != null);

      expect(
        bloc.state.device(device.id)!.error,
        'Device unreachable — tap refresh to retry',
      );
      verifyNever(() => repo.sendCommand(any(), any()));
    });

    test('brightness command carries the percent value', () async {
      final device = await seed();
      when(() => repo.sendCommand(device.id, DeviceCommand.brightness(42)))
          .thenAnswer((_) async => const CommandResult.ok());
      when(
        () => repo.getWledDevice(device.id),
      ).thenAnswer((_) async => makeWledDevice(id: device.id, brightness: 107));

      bloc.add(WledBrightness(device.id, 42));
      await waitForState(bloc, (s) => !s.device(device.id)!.busy);

      verify(() => repo.sendCommand(device.id, DeviceCommand.brightness(42)))
          .called(1);
      expect(bloc.state.device(device.id)!.brightness255, 107);
    });

    test('color command carries rgb channels', () async {
      final device = await seed();
      final color = const RGBColor(1, 2, 3);
      when(() => repo.sendCommand(device.id, DeviceCommand.color(1, 2, 3)))
          .thenAnswer((_) async => const CommandResult.ok());
      when(() => repo.getWledDevice(device.id))
          .thenAnswer((_) async => makeWledDevice(id: device.id, color: color));

      bloc.add(WledColor(device.id, color));
      await waitForState(bloc, (s) => !s.device(device.id)!.busy);

      verify(() => repo.sendCommand(device.id, DeviceCommand.color(1, 2, 3)))
          .called(1);
    });

    test('effect selection sends the device-reported id', () async {
      final device = await seed();
      when(
        () =>
            repo.sendCommand(device.id, DeviceCommand.effect('Rainbow', id: 1)),
      ).thenAnswer((_) async => const CommandResult.ok());
      when(() => repo.getWledDevice(device.id)).thenAnswer(
        (_) async => makeWledDevice(
          id: device.id,
          effect: 'Rainbow',
          metadata: {'wledEffectId': 1},
        ),
      );

      bloc.add(WledEffectSelect(device.id, 1));
      await waitForState(bloc, (s) => !s.device(device.id)!.busy);

      verify(
        () =>
            repo.sendCommand(device.id, DeviceCommand.effect('Rainbow', id: 1)),
      ).called(1);
      expect(bloc.state.device(device.id)!.effectName, 'Rainbow');
    });

    test('palette selection sends the palette id', () async {
      final device = await seed();
      when(() => repo.sendCommand(device.id, DeviceCommand.palette(4)))
          .thenAnswer((_) async => const CommandResult.ok());
      when(() => repo.getWledDevice(device.id)).thenAnswer(
        (_) async =>
            makeWledDevice(id: device.id, metadata: {'wledPaletteId': 4}),
      );

      bloc.add(WledPaletteSelect(device.id, 4));
      await waitForState(bloc, (s) => !s.device(device.id)!.busy);

      verify(() => repo.sendCommand(device.id, DeviceCommand.palette(4)))
          .called(1);
    });

    test('command failure surfaces a friendly error and keeps state', () async {
      final device = await seed();
      when(() => repo.sendCommand(device.id, DeviceCommand.power(true)))
          .thenAnswer(
            (_) async => const CommandResult.failure('timeout', 'timed out'),
          );

      bloc.add(WledPower(device.id, true));
      await waitForState(bloc, (s) => !s.device(device.id)!.busy);

      final info = bloc.state.device(device.id)!;
      expect(info.error, 'The device did not respond in time');
      expect(info.busy, isFalse);
      expect(info.on, isTrue); // confirmed state unchanged
    });

    test('rapid repeated commands all complete in order', () async {
      final device = await seed();
      var call = 0;
      when(() => repo.sendCommand(device.id, any())).thenAnswer((_) async {
        call++;
        return const CommandResult.ok();
      });
      when(() => repo.getWledDevice(device.id)).thenAnswer((_) async {
        // Final state reflects the last command.
        return call >= 2
            ? makeWledDevice(id: device.id, on: false)
            : makeWledDevice(id: device.id, on: true);
      });

      bloc.add(WledPower(device.id, true));
      await waitForState(bloc, (s) => !s.device(device.id)!.busy);
      bloc.add(WledPower(device.id, false));
      await waitForState(bloc, (s) => !s.device(device.id)!.busy);

      verify(() => repo.sendCommand(device.id, DeviceCommand.power(true)))
          .called(1);
      verify(() => repo.sendCommand(device.id, DeviceCommand.power(false)))
          .called(1);
      expect(bloc.state.device(device.id)!.on, isFalse);
    });
  });

  group('remove / rename', () {
    test('remove removes the device from state', () async {
      final device = makeWledDevice();
      when(() => repo.getWledDevices()).thenAnswer((_) async => [device]);
      when(() => repo.removeDevice(device.id)).thenAnswer((_) async {});
      bloc.add(WledDevicesLoad());
      await waitForState(bloc, (s) => !s.loading);

      bloc.add(WledDeviceRemove(device.id));
      await waitForState(bloc, (s) => s.device(device.id) == null);

      expect(bloc.state.device(device.id), isNull);
      verify(() => repo.removeDevice(device.id)).called(1);
    });

    test('rename updates the display name', () async {
      final device = makeWledDevice(name: 'Old');
      when(() => repo.getWledDevices()).thenAnswer((_) async => [device]);
      when(() => repo.renameDevice(device.id, 'New')).thenAnswer((_) async {});
      bloc.add(WledDevicesLoad());
      await waitForState(bloc, (s) => !s.loading);

      bloc.add(WledDeviceRename(device.id, 'New'));
      await waitForState(bloc, (s) => s.device(device.id)!.name == 'New');

      expect(bloc.state.device(device.id)!.name, 'New');
      verify(() => repo.renameDevice(device.id, 'New')).called(1);
    });
  });

  test('repository disconnected event marks device unreachable', () async {
    final device = makeWledDevice();
    when(() => repo.getWledDevices()).thenAnswer((_) async => [device]);
    bloc.add(WledDevicesLoad());
    await waitForState(bloc, (s) => !s.loading);
    eventController.add(
      DeviceEvent.connectionChanged(deviceId: device.id, connected: true),
    );
    await pumpEventQueue();
    expect(bloc.state.device(device.id)!.reachable, isTrue);

    eventController.add(
      DeviceEvent.connectionChanged(deviceId: device.id, connected: false),
    );
    await pumpEventQueue();
    expect(bloc.state.device(device.id)!.reachable, isFalse);
  });
}
