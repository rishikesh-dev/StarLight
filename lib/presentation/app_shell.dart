// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:starlight/presentation/bloc/ble/ble_bloc.dart';
import 'package:starlight/presentation/bloc/ble/ble_event.dart';
import 'package:starlight/presentation/pages/devices/add_device_page.dart';
import 'package:starlight/presentation/pages/home/home_page.dart';
import 'package:starlight/presentation/pages/settings/settings_page.dart';
import 'package:starlight/presentation/theme/app_theme.dart';

/// Root shell providing primary navigation: Home, Add Device, Settings.
///
/// Scenes and Automations are unfinished and intentionally not exposed here;
/// their sources are retained for future milestones.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> with WidgetsBindingObserver {
  int _currentIndex = 0;

  static const int _addDeviceIndex = 1;

  void _select(int index) {
    if (index == _currentIndex) return;
    setState(() => _currentIndex = index);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;
    final bleBloc = context.read<BleBloc>();
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        // Truly backgrounded: stop any active scan; it restarts on demand.
        bleBloc.add(const StopScanRequested());
      case AppLifecycleState.inactive:
        // Transient loss of focus only — a system permission/Bluetooth dialog,
        // the notification shade, split-screen, etc. Do NOT tear down the scan
        // here: the startup permission dialog emits `inactive`, and stopping
        // the scan at that point aborted the startup readiness flow.
        break;
      case AppLifecycleState.resumed:
        // Returning to the foreground (including from system settings):
        // re-check adapter/permission state without reopening any dialog.
        bleBloc.add(const BluetoothStateRecheck());
      case AppLifecycleState.detached:
        break;
    }
  }

  static const int _settingsIndex = 2;

  List<Widget> _buildPages() => [
    HomePage(
      onAddDevice: () => _select(_addDeviceIndex),
      onOpenSettings: () => _select(_settingsIndex),
    ),
    AddDevicePage(
      embedded: true,
      active: _currentIndex == _addDeviceIndex,
      onConnected: () => _select(0),
    ),
    const SettingsPage(),
  ];

  static const List<BottomDestination> _destinations = [
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

  @override
  Widget build(BuildContext context) {
    final useRail = MediaQuery.of(context).size.width >= 900;
    final tokens = context.tokens;

    final body = IndexedStack(index: _currentIndex, children: _buildPages());

    if (useRail) {
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              backgroundColor: tokens.surface,
              destinations: _destinations
                  .map(
                    (d) => NavigationRailDestination(
                      icon: Icon(d.icon),
                      selectedIcon: Icon(d.activeIcon),
                      label: Text(d.label),
                    ),
                  )
                  .toList(),
              selectedIndex: _currentIndex,
              onDestinationSelected: _select,
              labelType: NavigationRailLabelType.selected,
            ),
            const VerticalDivider(width: 1),
            Expanded(child: body),
          ],
        ),
      );
    }

    return Scaffold(
      body: body,
      // The nav bar reserves layout space (instead of overlaying the body) so
      // page content is never hidden behind it. Device status lives on Home
      // (hero + device card) and in the Diagnostics screen — no persistent
      // status strip is stacked above the bar.
      bottomNavigationBar: BottomBar(
        destinations: _destinations,
        currentIndex: _currentIndex,
        onTap: _select,
      ),
    );
  }
}

/// Bottom navigation bar.
///
/// The bar sizes itself to its content (with a comfortable minimum height)
/// instead of using a fixed height, so it never overflows when the system
/// bottom inset, large text scales, or the on-screen keyboard change the
/// available space. The [SafeArea] is applied *outside* the content so the
/// inset adds height rather than squeezing the row.
class BottomBar extends StatelessWidget {
  final List<BottomDestination> destinations;
  final int currentIndex;
  final ValueChanged<int> onTap;

  const BottomBar({
    super.key,
    required this.destinations,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tokens.surface,
        boxShadow: const [
          BoxShadow(
            color: Colors.black54,
            blurRadius: 12,
            offset: Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 60),
          child: Row(
            children: [
              for (int i = 0; i < destinations.length; i++)
                Expanded(
                  child: _BottomBarItem(
                    destination: destinations[i],
                    selected: i == currentIndex,
                    onTap: () => onTap(i),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BottomBarItem extends StatelessWidget {
  final BottomDestination destination;
  final bool selected;
  final VoidCallback onTap;

  const _BottomBarItem({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final color = selected ? tokens.primary : tokens.onSurfaceVariant;
    return Semantics(
      label: destination.label,
      button: true,
      selected: selected,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                height: 32,
                width: 56,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected
                      ? tokens.primary.withValues(alpha: 0.16)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Icon(
                  selected ? destination.activeIcon : destination.icon,
                  color: color,
                  size: 23,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                destination.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: color,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class BottomDestination {
  final IconData? icon;
  final IconData? activeIcon;
  final String label;

  const BottomDestination({
    required this.icon,
    required this.activeIcon,
    required this.label,
  });
}
