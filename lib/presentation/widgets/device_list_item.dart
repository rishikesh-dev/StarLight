import 'package:flutter/material.dart';

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
    final isDemo = device.name.contains('GATT--DEMO');

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: isDemo
              ? const Color(0xFF8E6CFF)
              : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.2),
          child: const Icon(Icons.bluetooth, size: 20),
        ),
        title: Row(
          children: [
            Text(
              device.name,
              style: theme.textTheme.titleMedium,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (isDemo) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF8E6CFF).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  'MR Star',
                  style: TextStyle(
                    color: Color(0xFF8E6CFF),
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
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
                    icon: const Icon(Icons.cancel, color: Colors.red),
                    onPressed: onDisconnect,
                  )
                : IconButton(
                    icon: const Icon(Icons.power, color: Color(0xFF8E6CFF)),
                    onPressed: onConnect,
                  ),
      ),
    );
  }
}
