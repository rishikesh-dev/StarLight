// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';

import 'package:starlight/presentation/theme/app_theme.dart';

import '../../domain/entities/ble_device.dart';

/// Widget for displaying a discovered BLE device in the scan list.
class DeviceListItem extends StatelessWidget {
  final BleDevice device;
  final VoidCallback onConnect;
  final VoidCallback onDisconnect;
  final bool isConnecting;

  const DeviceListItem({
    super.key,
    required this.device,
    required this.onConnect,
    required this.onDisconnect,
    this.isConnecting = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.tokens;
    final isDemo = device.name.contains('GATT--DEMO');

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: isDemo
              ? tokens.primary
              : tokens.onSurfaceVariant.withValues(alpha: 0.2),
          child: const Icon(Icons.bluetooth, size: 20),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                device.name,
                style: theme.textTheme.titleMedium,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (isDemo) ...[
              const SizedBox(width: 8),
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'MR Star',
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: theme.colorScheme.primary,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
        subtitle: Text(
          'RSSI: ${device.rssi} dBm  |  ID: ${device.id}',
          style: theme.textTheme.bodySmall,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: isConnecting
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : device.isConnected
            ? IconButton(
                icon: Icon(Icons.cancel, color: tokens.error),
                onPressed: onDisconnect,
              )
            : IconButton(
                icon: Icon(Icons.power, color: tokens.primary),
                onPressed: onConnect,
              ),
      ),
    );
  }
}
