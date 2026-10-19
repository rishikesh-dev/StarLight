import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starlight/domain/entities/ble_device.dart';
import 'package:starlight/presentation/theme/app_theme.dart';
import 'package:starlight/presentation/widgets/device_list_item.dart';

/// Regression coverage for the horizontal RenderFlex overflow in the device
/// list (device_list_item.dart) caused by very long names, long identifiers and
/// large text scales.
BleDevice _device({
  required String name,
  String id = 'AA:BB:CC:DD:EE:FF',
  int rssi = -42,
  bool isConnected = false,
}) {
  return BleDevice(id: id, name: name, rssi: rssi, isConnected: isConnected);
}

Widget _harness(Widget child, {double width = 320, double textScale = 1.0}) {
  return MaterialApp(
    theme: buildAppTheme(),
    home: MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
      child: Scaffold(
        body: Center(
          child: SizedBox(width: width, child: child),
        ),
      ),
    ),
  );
}

Widget _item({
  required String name,
  String id = 'AA:BB:CC:DD:EE:FF',
  bool isConnecting = false,
  bool isConnected = false,
}) {
  return DeviceListItem(
    device: _device(name: name, id: id, isConnected: isConnected),
    isConnecting: isConnecting,
    onConnect: () {},
    onDisconnect: () {},
  );
}

void main() {
  testWidgets('does not overflow on a narrow screen with a long name', (
    tester,
  ) async {
    await tester.pumpWidget(_harness(_item(name: 'A' * 400), width: 320));
    expect(tester.takeException(), isNull);
    expect(find.text('A' * 400), findsOneWidget);
  });

  testWidgets('does not overflow with a long name and the MR Star badge', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(_item(name: 'GATT--DEMO ${'Y' * 300}'), width: 200),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders a fallback name without overflowing', (tester) async {
    await tester.pumpWidget(
      _harness(_item(name: 'Unknown BLE device'), width: 180),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Unknown BLE device'), findsOneWidget);
  });

  testWidgets(
    'does not overflow with a long identifier at a large text scale',
    (tester) async {
      await tester.pumpWidget(
        _harness(
          _item(name: 'Lamp', id: 'AA:BB:CC:DD:EE:FF:00:11:22:33:44:55'),
          width: 320,
          textScale: 2.0,
        ),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('shows a progress indicator while connecting', (tester) async {
    await tester.pumpWidget(_harness(_item(name: 'Lamp', isConnecting: true)));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
