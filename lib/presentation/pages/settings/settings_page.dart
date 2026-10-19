// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:starlight/presentation/bloc/ble/ble_bloc.dart';
import 'package:starlight/presentation/bloc/ble/ble_event.dart';
import 'package:starlight/presentation/bloc/ble/ble_state.dart';
import 'package:starlight/presentation/bloc/profile/profile_cubit.dart';
import 'package:starlight/presentation/pages/debug/hardware_lab_page.dart';
import 'package:starlight/presentation/pages/settings/appearance_settings.dart';
import 'package:starlight/presentation/pages/settings/profiles_settings_page.dart';
import 'package:starlight/presentation/theme/app_theme.dart';

/// Settings screen — appearance, Bluetooth status and diagnostics.
///
/// Only real, supported settings are exposed; no cloud accounts, subscriptions,
/// or unrelated features. Colours follow the active theme via [AppTokens].
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings'), elevation: 0),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const _SectionTitle('Appearance'),
          const SizedBox(height: 12),
          const AppearanceSettings(),
          const SizedBox(height: 28),
          const _SectionTitle('Bluetooth'),
          const SizedBox(height: 8),
          const _BluetoothStatusCard(),
          const SizedBox(height: 28),
          const _SectionTitle('Devices'),
          const SizedBox(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              Icons.tune,
              color: Theme.of(context).colorScheme.primary,
            ),
            title: const Text('Device profiles'),
            subtitle: const Text('How StarLight talks to other controllers'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _openProfiles(context),
          ),
          const SizedBox(height: 28),
          const _SectionTitle('Effects'),
          const SizedBox(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              Icons.auto_awesome,
              color: Theme.of(context).colorScheme.primary,
            ),
            title: const Text('Effects library'),
            subtitle: const Text(
              'Device patterns and StarLight\u2019s own effects',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).pushNamed('/effects'),
          ),
          const SizedBox(height: 28),
          const _SectionTitle('Diagnostics'),
          const SizedBox(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              Icons.monitor_heart_outlined,
              color: Theme.of(context).colorScheme.primary,
            ),
            title: const Text('Diagnostics'),
            subtitle: const Text('Connection, GATT and profile details'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).pushNamed('/diagnostics'),
          ),
          const SizedBox(height: 28),
          const _SectionTitle('Not available'),
          const SizedBox(height: 4),
          _UnavailableTile(
            icon: Icons.extension_outlined,
            title: 'Installed extensions',
            subtitle: 'Not implemented in this build',
          ),
          _UnavailableTile(
            icon: Icons.hub_outlined,
            title: 'Integrations',
            subtitle: 'Not implemented in this build',
          ),
          const SizedBox(height: 28),
          const _SectionTitle('About'),
          const SizedBox(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              Icons.info,
              color: Theme.of(context).colorScheme.primary,
            ),
            title: const Text('StarLight'),
            subtitle: const Text('Version 1.0.0'),
            onLongPress: () {
              if (kDebugMode) {
                Navigator.of(context).pushNamed(HardwareLabPage.routeName);
              }
            },
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              Icons.devices,
              color: Theme.of(context).colorScheme.primary,
            ),
            title: const Text('MR Star LED Controller'),
            subtitle: const Text('Service FFF0 • Write FFF3 • Notify FFF4'),
          ),
        ],
      ),
    );
  }

  /// Opens the profile list, re-providing the [ProfileCubit] so the pushed
  /// route (a sibling of this page in the navigator) can read it.
  static void _openProfiles(BuildContext context) {
    final cubit = context.read<ProfileCubit>();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => BlocProvider<ProfileCubit>.value(
          value: cubit,
          child: const ProfilesSettingsPage(),
        ),
      ),
    );
  }
}

/// A settings row that is deliberately present but inert.
///
/// Placeholder for a future feature. It is visibly muted and labelled so the
/// app never presents a dead end as if it were a working destination.
class _UnavailableTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _UnavailableTile({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return ListTile(
      enabled: false,
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: tokens.disabled),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: Text(
        'Unavailable',
        style: TextStyle(color: tokens.onSurfaceVariant, fontSize: 12),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;

  const _SectionTitle(this.title);

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: context.tokens.onSurface,
      ),
    );
  }
}

/// Reflects the real Bluetooth adapter/connection state with an appropriate
/// action, so the user can recover from an off/denied/error condition.
class _BluetoothStatusCard extends StatelessWidget {
  const _BluetoothStatusCard();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<BleBloc, BleState>(
      builder: (context, state) {
        final bleBloc = context.read<BleBloc>();
        final tokens = context.tokens;

        final IconData icon;
        final Color color;
        final String title;
        final String subtitle;
        String? actionLabel;
        VoidCallback? onAction;

        switch (state) {
          case BleConnected(device: final device):
            icon = Icons.bluetooth_connected;
            color = tokens.success;
            title = 'Connected';
            subtitle = device.name;
            actionLabel = 'Disconnect';
            onAction = () => bleBloc.add(const DisconnectRequested());
          case BleConnecting(deviceName: final name):
            icon = Icons.bluetooth_searching;
            color = tokens.primary;
            title = 'Connecting…';
            subtitle = name;
          case BleScanning():
            icon = Icons.bluetooth_searching;
            color = tokens.primary;
            title = 'Scanning…';
            subtitle = 'Looking for nearby devices';
          case BleBluetoothEnabling():
            icon = Icons.bluetooth;
            color = tokens.primary;
            title = 'Turning on Bluetooth…';
            subtitle = 'Waiting for the adapter';
          case BleBluetoothOff(message: final m):
            icon = Icons.bluetooth_disabled;
            color = tokens.warning;
            title = 'Bluetooth is off';
            subtitle = m;
            actionLabel = 'Turn on Bluetooth';
            onAction = () => bleBloc.add(const RetryBluetooth());
          case BleBluetoothUnavailable(message: final m):
            icon = Icons.bluetooth_disabled;
            color = tokens.warning;
            title = 'Bluetooth unavailable';
            subtitle = m;
          case BlePermissionDenied(
            message: final m,
            permanentlyDenied: final perm,
          ):
            icon = Icons.lock_outline;
            color = tokens.warning;
            title = 'Permission required';
            subtitle = m;
            actionLabel = perm ? 'Open settings' : 'Grant permission';
            onAction = perm
                ? () => bleBloc.add(const OpenAppSettingsRequested())
                : () => bleBloc.add(const RetryBluetooth());
          case BleError(message: final m):
            icon = Icons.error_outline;
            color = tokens.error;
            title = 'Bluetooth error';
            subtitle = m;
            actionLabel = 'Try again';
            onAction = () => bleBloc.add(const EnsureBluetoothReady());
          default:
            icon = Icons.bluetooth;
            color = tokens.onSurfaceVariant;
            title = 'Bluetooth is on';
            subtitle = 'No device connected';
        }

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: tokens.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: tokens.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, color: color, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: TextStyle(
                            color: tokens.onSurfaceVariant,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (actionLabel != null && onAction != null) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: onAction,
                    child: Text(actionLabel),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
