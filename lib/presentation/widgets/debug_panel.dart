import 'package:flutter/material.dart';

import '../../core/ble/ble_constants.dart';

/// Debug panel showing BLE connection details and last packets.
///
/// Displays:
/// - Connected device ID and name
/// - RSSI
/// - Service UUID
/// - Write characteristic UUID
/// - Notify characteristic UUID
/// - Last command sent (hex)
/// - Last notification received (hex)
/// - Connection state
class DebugPanel extends StatelessWidget {
  final String? connectedDeviceId;
  final String? connectedDeviceName;
  final int? rssi;
  // These are fixed by the MR Star protocol, so they default to the
  // constants instead of being nullable.
  final String serviceUuid;
  final String writeCharUuid;
  final String notifyCharUuid;
  final String? lastCommandHex;
  final String? lastNotificationHex;
  final String? connectionState;

  const DebugPanel({
    super.key,
    this.connectedDeviceId,
    this.connectedDeviceName,
    this.rssi,
    this.serviceUuid = BleConstants.serviceUuid,
    this.writeCharUuid = BleConstants.writeCharUuid,
    this.notifyCharUuid = BleConstants.notifyCharUuid,
    this.lastCommandHex,
    this.lastNotificationHex,
    this.connectionState,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Card(
      margin: const EdgeInsets.all(16),
      color: isDark ? Colors.grey.shade900 : Colors.grey.shade100,
      child: ExpansionTile(
        title: const Text('Debug / Developer'),
        leading: const Icon(Icons.bug_report, color: Color(0xFF8E6CFF)),
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildRow('Connected Device', connectedDeviceName ?? 'None'),
                _buildRow('Device ID', connectedDeviceId ?? '—'),
                _buildRow('RSSI', rssi?.toString() ?? '—'),
                _buildRow('Service UUID', serviceUuid),
                _buildRow('Write Char UUID', writeCharUuid),
                _buildRow('Notify Char UUID', notifyCharUuid),
                _buildRow('Connection State',
                    connectionState ?? 'unknown'),
                const Divider(height: 20),
                Text(
                  'TX:',
                  style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey),
                ),
                _buildHexDump(lastCommandHex),
                Text(
                  'RX:',
                  style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey),
                ),
                _buildHexDump(lastNotificationHex),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text('$label:', style: const TextStyle(color: Colors.grey)),
          ),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 12))),
        ],
      ),
    );
  }

  Widget _buildHexDump(String? hex) {
    if (hex == null || hex.isEmpty) {
      return const Text('—', style: TextStyle(color: Colors.grey));
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.black45,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        hex,
        style: const TextStyle(
          fontFamily: 'monospace',
          fontSize: 12,
          color: Colors.greenAccent,
        ),
      ),
    );
  }
}
