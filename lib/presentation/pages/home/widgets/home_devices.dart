// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:starlight/domain/entities/ble_device.dart';
import 'package:starlight/domain/entities/device_capability.dart';
import 'package:starlight/presentation/bloc/ble/ble_bloc.dart';
import 'package:starlight/presentation/bloc/ble/ble_state.dart';
import 'package:starlight/presentation/bloc/light/light_bloc.dart'
    show LightBloc;
import 'package:starlight/presentation/bloc/light/light_event.dart';
import 'package:starlight/presentation/bloc/light/light_state.dart';
import 'package:starlight/presentation/bloc/light/light_state_view.dart';
import 'package:starlight/presentation/bloc/registry/device_registry_cubit.dart';
import 'package:starlight/presentation/pages/home/widgets/home_section_header.dart';
import 'package:starlight/presentation/theme/app_theme.dart';

/// The "Devices" section of Home: a compact list of the devices StarLight
/// actually knows — the persisted registry plus the paired BLE controller
/// (deduplicated by id), filtered to the room selected in the room selector.
///
/// Each row shows the real device name and its honest connection state; a
/// power quick-control appears only for the device that is *actually*
/// connected and only when the device exposes the power capability. Nothing
/// here is invented: a saved-but-disconnected device says "Not connected" and
/// offers no controls.
class HomeDevices extends StatelessWidget {
  final VoidCallback onAddDevice;

  /// Room filter from the room selector; `null` shows every device.
  final String? selectedRoomId;

  const HomeDevices({
    super.key,
    required this.onAddDevice,
    this.selectedRoomId,
  });

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<DeviceRegistryCubit, DeviceRegistryState>(
      builder: (context, registry) {
        return BlocBuilder<BleBloc, BleState>(
          builder: (context, bleState) {
            final connectedId = switch (bleState) {
              BleConnected(:final device) => device.id,
              _ => null,
            };
            final connectingId = switch (bleState) {
              BleConnecting(:final deviceId) => deviceId,
              _ => null,
            };
            final bleDevice = _deviceOf(bleState);

            // Registry devices (room-filtered), then the paired BLE device if
            // the registry does not know it (it still deserves a row).
            final rows = <_DeviceRow>[];
            final seen = <String>{};
            for (final device in registry.devices) {
              final inRoom =
                  selectedRoomId == null || device.roomId == selectedRoomId;
              if (!inRoom) continue;
              seen.add(device.id);
              rows.add(
                _DeviceRow(
                  id: device.id,
                  name: device.name,
                  connected: device.id == connectedId,
                  connecting: device.id == connectingId,
                ),
              );
            }
            if (bleDevice != null && !seen.contains(bleDevice.id)) {
              // Not in the registry ⇒ unassigned ⇒ only in the overview.
              if (selectedRoomId == null) {
                rows.add(
                  _DeviceRow(
                    id: bleDevice.id,
                    name: bleDevice.name,
                    connected: bleDevice.id == connectedId,
                    connecting: bleDevice.id == connectingId,
                  ),
                );
              }
            }

            return BlocBuilder<LightBloc, LightState>(
              builder: (context, lightState) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    HomeSectionHeader(
                      title: 'Devices',
                      subtitle: rows.isEmpty
                          ? 'Nothing paired yet'
                          : '${rows.length} device${rows.length == 1 ? '' : 's'}',
                    ),
                    const SizedBox(height: 12),
                    if (rows.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: _EmptyRow(onAddDevice: onAddDevice),
                      )
                    else
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Column(
                          children: [
                            for (var i = 0; i < rows.length; i++) ...[
                              if (i > 0) const SizedBox(height: 8),
                              _DeviceListRow(
                                row: rows[i],
                                lightState: lightState,
                                confirmed: context
                                    .read<LightBloc>()
                                    .hasConfirmedState,
                              ),
                            ],
                          ],
                        ),
                      ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  static BleDevice? _deviceOf(BleState state) {
    return switch (state) {
      BleConnected(:final device) => device,
      BleDisconnected(:final device) => device,
      BleConnecting(:final deviceId, :final deviceName) => BleDevice(
        id: deviceId,
        name: deviceName,
        rssi: 0,
      ),
      _ => null,
    };
  }
}

/// One device as listed on Home.
class _DeviceRow {
  final String id;
  final String name;
  final bool connected;
  final bool connecting;

  const _DeviceRow({
    required this.id,
    required this.name,
    required this.connected,
    required this.connecting,
  });
}

/// Compact, tappable device row.
class _DeviceListRow extends StatelessWidget {
  final _DeviceRow row;
  final LightState lightState;
  final bool confirmed;

  const _DeviceListRow({
    required this.row,
    required this.lightState,
    required this.confirmed,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.tokens;
    final isOn = confirmed && lightState.isLightOn;
    final canPower =
        row.connected &&
        lightState.lightCapabilities.contains(DeviceCapability.power);

    final statusColor = row.connecting
        ? tokens.warning
        : row.connected
        ? (isOn ? tokens.success : tokens.onSurfaceVariant)
        : tokens.onSurfaceVariant;
    final statusLabel = row.connecting
        ? 'Connecting…'
        : row.connected
        ? (confirmed
              ? (isOn ? 'On · Connected' : 'Off · Connected')
              : 'Connected')
        : 'Not connected';

    return Material(
      color: tokens.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: tokens.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context).pushNamed('/controller'),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 64),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                _DeviceGlyph(active: row.connected),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        row.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: tokens.onSurface,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Container(
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(
                              color: statusColor,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 7),
                          Flexible(
                            child: Text(
                              statusLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: tokens.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (canPower)
                  _RowPowerButton(
                    on: isOn,
                    onTap: () =>
                        context.read<LightBloc>().add(TogglePower(!isOn)),
                  ),
                Icon(
                  Icons.chevron_right,
                  color: tokens.onSurfaceVariant,
                  size: 22,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DeviceGlyph extends StatelessWidget {
  final bool active;

  const _DeviceGlyph({required this.active});

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final color = active ? tokens.primary : tokens.onSurfaceVariant;
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: active
            ? tokens.primary.withValues(alpha: 0.14)
            : tokens.surfaceHigh,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: active ? tokens.primary.withValues(alpha: 0.4) : tokens.border,
        ),
      ),
      child: Icon(Icons.lightbulb_outline, color: color, size: 20),
    );
  }
}

/// Compact power quick-control shown only for the connected device when the
/// power capability is actually exposed.
class _RowPowerButton extends StatelessWidget {
  final bool on;
  final VoidCallback onTap;

  const _RowPowerButton({required this.on, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final color = on ? tokens.success : tokens.onSurfaceVariant;
    return Semantics(
      label: on ? 'Turn off' : 'Turn on',
      button: true,
      child: InkResponse(
        onTap: onTap,
        radius: 24,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: on
                ? tokens.success.withValues(alpha: 0.14)
                : tokens.surfaceHigh,
            border: Border.all(
              color: on ? tokens.success : tokens.border,
              width: 1.5,
            ),
          ),
          child: Icon(Icons.power_settings_new, color: color, size: 20),
        ),
      ),
    );
  }
}

/// Compact empty state for the device list.
class _EmptyRow extends StatelessWidget {
  final VoidCallback onAddDevice;

  const _EmptyRow({required this.onAddDevice});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.tokens;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: tokens.border),
      ),
      child: Row(
        children: [
          Icon(
            Icons.lightbulb_outline,
            color: tokens.onSurfaceVariant,
            size: 22,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'No devices yet',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: tokens.onSurfaceVariant,
              ),
            ),
          ),
          // Scales down rather than overflowing on very narrow screens or
          // large text scales (the label stays readable, never clipped).
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: FilledButton.tonalIcon(
                onPressed: onAddDevice,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add Device'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 36),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  textStyle: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
