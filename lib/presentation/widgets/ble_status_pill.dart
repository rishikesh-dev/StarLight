// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';

import 'package:starlight/presentation/bloc/ble/ble_state.dart';
import 'package:starlight/presentation/theme/app_theme.dart';

/// Compact, accessible pill that reflects the live Bluetooth/connection state.
///
/// It is a pure projection of [BleState]; it never shows a state the
/// transport did not report.
class BleStatusPill extends StatelessWidget {
  final BleState state;

  const BleStatusPill({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    final (label, color, icon) = _describe(context, state);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  (String, Color, IconData) _describe(BuildContext context, BleState state) {
    final primary = Theme.of(context).colorScheme.primary;
    final tokens = context.tokens;
    return switch (state) {
      BleConnected() => (
        'Connected',
        tokens.success,
        Icons.bluetooth_connected,
      ),
      BleConnecting() => ('Connecting…', primary, Icons.bluetooth_searching),
      BleScanning() => ('Scanning…', primary, Icons.bluetooth_searching),
      BleBluetoothEnabling() => ('Enabling…', primary, Icons.bluetooth),
      BleCheckingPermissions() => ('Checking…', primary, Icons.lock_outline),
      BleBluetoothOff() => (
        'Bluetooth off',
        tokens.warning,
        Icons.bluetooth_disabled,
      ),
      BleBluetoothUnavailable() => (
        'Unavailable',
        tokens.warning,
        Icons.bluetooth_disabled,
      ),
      BlePermissionDenied() => (
        'Permission needed',
        tokens.warning,
        Icons.lock_outline,
      ),
      BleError() => ('Error', tokens.error, Icons.error_outline),
      _ => ('Ready', tokens.onSurfaceVariant, Icons.bluetooth),
    };
  }
}
