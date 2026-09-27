import 'package:flutter/material.dart';

import '../../domain/entities/connection_state.dart';
import '../utils/text_style_extension.dart';

/// Visual indicator of the BLE connection status.
class ConnectionStatusIndicator extends StatelessWidget {
  final DeviceConnectionState connectionState;
  final String? deviceId;

  const ConnectionStatusIndicator({
    super.key,
    required this.connectionState,
    this.deviceId,
  });

  @override
  Widget build(BuildContext context) {
    final (color, text, icon) = _getStatus();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color, width: 1),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Text(
            text,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: color),
          ),
          if (deviceId != null && deviceId!.isNotEmpty) ...[
            const SizedBox(width: 8),
            Text(
              deviceId!,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyColor(Colors.grey),
            ),
          ],
        ],
      ),
    );
  }

  (Color, String, IconData) _getStatus() {
    switch (connectionState) {
      case DeviceConnectionState.connected:
        return (Colors.green, 'Connected', Icons.check_circle);
      case DeviceConnectionState.connecting:
        return (const Color(0xFFFFA726), 'Connecting...', Icons.sync);
      case DeviceConnectionState.disconnecting:
        return (const Color(0xFFFFA726), 'Disconnecting...', Icons.sync);
      case DeviceConnectionState.disconnected:
        return (Colors.red, 'Disconnected', Icons.error);
      case DeviceConnectionState.error:
        return (Colors.red, 'Error', Icons.error);
    }
  }
}