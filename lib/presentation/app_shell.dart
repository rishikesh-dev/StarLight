import 'package:flutter/material.dart';

import 'package:starlight/presentation/pages/devices/devices_page.dart';
import 'package:starlight/presentation/pages/home/home_page.dart';
import 'package:starlight/presentation/pages/scenes/scenes_page.dart';
import 'package:starlight/presentation/pages/automations/automations_page.dart';
import 'package:starlight/presentation/widgets/mini_player.dart';
import 'package:starlight/presentation/theme/app_theme.dart';

/// Root shell providing primary navigation: Home, Devices, Scenes, Automations.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _currentIndex = 0;

  static const List<Widget> _pages = [
    HomePage(),
    DevicesPage(),
    ScenesPage(),
    AutomationsPage(),
  ];

  static const List<_NavDestination> _destinations = [
    _NavDestination(icon: Icons.home_outlined, activeIcon: Icons.home, label: 'Home'),
    _NavDestination(icon: Icons.devices_outlined, activeIcon: Icons.devices, label: 'Devices'),
    _NavDestination(icon: Icons.auto_awesome_outlined, activeIcon: Icons.auto_awesome, label: 'Scenes'),
    _NavDestination(icon: Icons.schedule_outlined, activeIcon: Icons.schedule, label: 'Automations'),
  ];

  bool get _isDesktop =>
      defaultTargetPlatform == TargetPlatform.linux ||
      defaultTargetPlatform == TargetPlatform.macOS ||
      defaultTargetPlatform == TargetPlatform.windows;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final useRail = _isDesktop || width >= 900;

    final body = IndexedStack(
      index: _currentIndex,
      children: _pages,
    );

    if (useRail) {
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              backgroundColor: AppColors.surface,
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
              onDestinationSelected: (i) => setState(() => _currentIndex = i),
              labelType: NavigationRailLabelType.selected,
            ),
            const VerticalDivider(width: 1, color: AppColors.border),
            Expanded(
              child: Stack(
                children: [
                  body,
                  const Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: MiniPlayer(),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      body: Stack(
        children: [
          body,
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const MiniPlayer(),
                BottomBar(
                  destinations: _destinations
                      .map(
                        (d) => BottomDestination(
                          icon: Icon(d.icon),
                          activeIcon: Icon(d.activeIcon),
                          label: d.label,
                        ),
                      )
                      .toList(),
                  currentIndex: _currentIndex,
                  onTap: (i) => setState(() => _currentIndex = i),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NavDestination {
  final/iconData;
  final/iconData;
  final String label;

  const _NavDestination({
    required this.icon,
    required this.activeIcon,
    required this.label,
  });
}

/// Bottom navigation bar.
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
    return Container(
      height: 64,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black54,
            blurRadius: 12,
            offset: Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Row(
          children: [
            for (int i = 0; i < destinations.length; i++)
              Expanded(
                child: TapRegion(
                  onTap: () => onTap(i),
                  child: Column(
                    children: [
                      const Spacer(),
                      Icon(
                        i == currentIndex
                            ? destinations[i].activeIcon
                            : destinations[i].icon,
                        color: i == currentIndex
                            ? AppColors.primary
                            : AppColors.onSurfaceVariant,
                        size: 24,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        destinations[i].label,
                        style: TextStyle(
                          fontSize: 12,
                          color: i == currentIndex
                              ? AppColors.primary
                              : AppColors.onSurfaceVariant,
                          fontWeight: i == currentIndex
                              ? FontWeight.w600
                              : FontWeight.normal,
                        ),
                      ),
                      const Spacer(),
                      if (i == currentIndex)
                        Container(
                          width: 24,
                          height: 3,
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      const SizedBox(height: 4),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class BottomDestination {
  final Widget icon;
  final Widget activeIcon;
  final String label;

  const BottomDestination({
    required this.icon,
    required this.activeIcon,
    required this.label,
  });
}