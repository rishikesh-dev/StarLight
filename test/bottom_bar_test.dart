import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starlight/presentation/app_shell.dart';

/// Widget tests for the bottom navigation bar layout.
///
/// These guard against the bottom-nav overflow regression: the bar must fit
/// within the available height for small/short viewports, in the presence of a
/// system bottom inset (gesture navigation), and at large text scales.
void main() {
  const destinations = [
    BottomDestination(
      icon: Icons.home_outlined,
      activeIcon: Icons.home,
      label: 'Home',
    ),
    BottomDestination(
      icon: Icons.add_circle_outline,
      activeIcon: Icons.add_circle,
      label: 'Add Device',
    ),
    BottomDestination(
      icon: Icons.settings_outlined,
      activeIcon: Icons.settings,
      label: 'Settings',
    ),
  ];

  Future<void> pumpBar(
    WidgetTester tester, {
    required Size size,
    double textScale = 1.0,
    double bottomInset = 0,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) {
          final mq = MediaQuery.of(context);
          return MediaQuery(
            data: mq.copyWith(
              textScaler: TextScaler.linear(textScale),
              padding: EdgeInsets.only(bottom: bottomInset),
              viewPadding: EdgeInsets.only(bottom: bottomInset),
              viewInsets: EdgeInsets.zero,
            ),
            child: child!,
          );
        },
        home: Scaffold(
          body: const SizedBox.expand(),
          // Mirrors the real shell: the bar is the Scaffold's
          // bottomNavigationBar, sized to its content.
          bottomNavigationBar: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              BottomBar(
                destinations: destinations,
                currentIndex: 1,
                onTap: (_) {},
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('renders without overflow at the reported 360x784 viewport', (
    tester,
  ) async {
    await pumpBar(tester, size: const Size(360, 784), bottomInset: 34);
    expect(tester.takeException(), isNull);
    expect(find.text('Add Device'), findsOneWidget);
  });

  testWidgets('renders without overflow on a small 320x480 viewport', (
    tester,
  ) async {
    await pumpBar(tester, size: const Size(320, 480));
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders without overflow at 1.3x text scale with inset', (
    tester,
  ) async {
    await pumpBar(
      tester,
      size: const Size(411, 866),
      textScale: 1.3,
      bottomInset: 48,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders without overflow at 2.0x text scale', (tester) async {
    await pumpBar(
      tester,
      size: const Size(360, 640),
      textScale: 2.0,
      bottomInset: 34,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders without overflow when the keyboard is open', (
    tester,
  ) async {
    // A short remaining height models the scaffold resizing for the keyboard.
    await pumpBar(tester, size: const Size(360, 240), bottomInset: 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tapping a destination reports the index', (tester) async {
    final taps = <int>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BottomBar(
            destinations: destinations,
            currentIndex: 0,
            onTap: taps.add,
          ),
        ),
      ),
    );
    await tester.tap(find.text('Settings'));
    expect(taps, [2]);
  });
}
