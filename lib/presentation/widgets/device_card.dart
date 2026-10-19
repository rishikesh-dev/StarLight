// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';

import 'package:starlight/domain/entities/connection_state.dart';
import 'package:starlight/domain/entities/device.dart';
import 'package:starlight/domain/entities/device_capability.dart';
import 'package:starlight/domain/entities/device_type.dart';
import 'package:starlight/presentation/theme/app_theme.dart';

/// Reusable card for displaying a device in lists and grids.
class DeviceCard extends StatelessWidget {
  final Device device;
  final VoidCallback? onTap;
  final VoidCallback? onPowerToggle;
  final VoidCallback? onFavoriteToggle;
  final bool showPower;
  final bool compact;

  const DeviceCard({
    super.key,
    required this.device,
    this.onTap,
    this.onPowerToggle,
    this.onFavoriteToggle,
    this.showPower = true,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final connected = device.connectionState == DeviceConnectionState.connected;
    final connecting =
        device.connectionState == DeviceConnectionState.connecting;
    final hasPower = device.supports(DeviceCapability.power);

    return Card(
      margin: compact
          ? const EdgeInsets.symmetric(horizontal: 4, vertical: 4)
          : const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: ListTile(
        onTap: onTap,
        leading: _DeviceIcon(
          device: device,
          connected: connected,
          connecting: connecting,
        ),
        title: Text(
          device.name,
          style: theme.textTheme.titleMedium,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _connectionLabel(device.connectionState),
              style: theme.textTheme.bodySmall?.copyWith(
                color: _stateColor(device.connectionState),
                fontWeight: FontWeight.w500,
              ),
            ),
            if (device.roomId != null)
              Text(
                device.roomId ?? "",
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.onSurfaceVariant,
                ),
              ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (onFavoriteToggle != null)
              IconButton(
                icon: Icon(
                  device.favorite ? Icons.favorite : Icons.favorite_border,
                  color: device.favorite
                      ? AppColors.primary
                      : AppColors.onSurfaceVariant,
                  size: 20,
                ),
                onPressed: onFavoriteToggle,
                tooltip: device.favorite ? 'Unfavorite' : 'Favorite',
              ),
            if (showPower && hasPower && onPowerToggle != null && connected)
              IconButton(
                icon: Icon(
                  device.state.isOn ? Icons.power : Icons.power_off,
                  color: device.state.isOn
                      ? AppColors.success
                      : AppColors.onSurfaceVariant,
                ),
                onPressed: onPowerToggle,
                tooltip: device.state.isOn ? 'Turn off' : 'Turn on',
              )
            else if (showPower &&
                hasPower &&
                onPowerToggle != null &&
                !connected)
              const Icon(Icons.power_off, color: AppColors.disabled, size: 20),
            const Icon(Icons.chevron_right, color: AppColors.onSurfaceVariant),
          ],
        ),
      ),
    );
  }

  String _connectionLabel(DeviceConnectionState state) {
    return switch (state) {
      DeviceConnectionState.connected => 'Connected',
      DeviceConnectionState.connecting => 'Connecting…',
      DeviceConnectionState.disconnecting => 'Disconnecting…',
      DeviceConnectionState.disconnected => 'Disconnected',
      DeviceConnectionState.error => 'Error',
    };
  }

  Color _stateColor(DeviceConnectionState state) {
    return switch (state) {
      DeviceConnectionState.connected => AppColors.success,
      DeviceConnectionState.connecting => AppColors.warning,
      DeviceConnectionState.disconnecting => AppColors.warning,
      DeviceConnectionState.disconnected => AppColors.onSurfaceVariant,
      DeviceConnectionState.error => AppColors.error,
    };
  }
}

class _DeviceIcon extends StatelessWidget {
  final Device device;
  final bool connected;
  final bool connecting;

  const _DeviceIcon({
    required this.device,
    required this.connected,
    required this.connecting,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: connected ? AppColors.success : AppColors.border,
          width: connected ? 2 : 1,
        ),
      ),
      child: connecting
          ? const Padding(
              padding: EdgeInsets.all(10),
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(_iconFor(device.type), color: AppColors.primary, size: 22),
    );
  }

  IconData _iconFor(DeviceType type) => type.icon;
}
