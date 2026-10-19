// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:starlight/core/ble/ble_constants.dart';
import 'package:starlight/presentation/bloc/ble/ble_bloc.dart';
import 'package:starlight/presentation/bloc/ble/ble_state.dart';
import 'package:starlight/presentation/bloc/light/light_bloc.dart';
import 'package:starlight/presentation/bloc/light/light_state.dart';
import 'package:starlight/presentation/bloc/light/light_state_view.dart';
import 'package:starlight/presentation/bloc/profile/profile_cubit.dart';
import 'package:starlight/presentation/bloc/profile/profile_state.dart';
import 'package:starlight/presentation/theme/app_theme.dart';

/// Read-only diagnostics (route `/diagnostics`).
///
/// Everything on this screen is a value StarLight actually holds: the live BLE
/// connection, the fixed MR Star GATT constants, the assigned profile and its
/// real verification result, and the last *confirmed* light command values.
/// Nothing is sampled from hardware that was not observed and no packet log is
/// invented.
class DiagnosticsPage extends StatelessWidget {
  const DiagnosticsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Diagnostics'), elevation: 0),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
        children: const [
          _SectionTitle('Connection'),
          SizedBox(height: 10),
          _ConnectionCard(),
          SizedBox(height: 24),
          _SectionTitle('GATT (MR Star)'),
          SizedBox(height: 10),
          _GattCard(),
          SizedBox(height: 24),
          _SectionTitle('Device profile'),
          SizedBox(height: 10),
          _ProfileDiagnosticsCard(),
          SizedBox(height: 24),
          _SectionTitle('Last confirmed light values'),
          SizedBox(height: 10),
          _LightDiagnosticsCard(),
          SizedBox(height: 24),
          _SectionTitle('App'),
          SizedBox(height: 10),
          _AppCard(),
        ],
      ),
    );
  }
}

class _ConnectionCard extends StatelessWidget {
  const _ConnectionCard();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<BleBloc, BleState>(
      builder: (context, state) {
        final (label, device, rssi) = switch (state) {
          BleConnected(:final device) => (
            'Connected',
            device.id,
            device.rssi.toString(),
          ),
          BleDisconnected(:final device) => (
            'Disconnected',
            device?.id ?? '—',
            '—',
          ),
          BleConnecting(:final deviceName, :final deviceId) => (
            'Connecting to $deviceName',
            deviceId,
            '—',
          ),
          BleScanning(:final devices) => (
            'Scanning (${devices.length} found)',
            '—',
            '—',
          ),
          BleBluetoothOff(:final message) => (
            'Bluetooth off — $message',
            '—',
            '—',
          ),
          BleBluetoothUnavailable(:final message) => (
            'Bluetooth unavailable — $message',
            '—',
            '—',
          ),
          BlePermissionDenied(:final message) => (
            'Permission denied — $message',
            '—',
            '—',
          ),
          BleError(:final message) => ('Error — $message', '—', '—'),
          _ => ('Not connected', '—', '—'),
        };
        return _Card(
          rows: [
            _Row('State', label),
            _Row('Device ID', device),
            _Row('RSSI', rssi == '—' ? '—' : '$rssi dBm'),
          ],
        );
      },
    );
  }
}

class _GattCard extends StatelessWidget {
  const _GattCard();

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return _Card(
      rows: const [
        _Row('Service', BleConstants.serviceUuid),
        _Row('Write', BleConstants.writeCharUuid),
        _Row('Notify', BleConstants.notifyCharUuid),
      ],
      footer: Text(
        'Fixed by the MR Star protocol. A frame starts with 0x'
        '${BleConstants.startByte.toRadixString(16).toUpperCase()} and ends '
        'with 0x${BleConstants.endByte.toRadixString(16).toUpperCase()} '
        '(max ${BleConstants.maxWriteChunkSize} bytes per write).',
        style: TextStyle(color: tokens.onSurfaceVariant, fontSize: 12),
      ),
    );
  }
}

class _ProfileDiagnosticsCard extends StatelessWidget {
  const _ProfileDiagnosticsCard();

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return BlocBuilder<ProfileCubit, ProfileState>(
      builder: (context, state) {
        final deviceId = state.activeDeviceId;
        final assigned = deviceId == null
            ? null
            : state.assignedProfile(deviceId);
        if (assigned == null) {
          return _Card(
            rows: const [_Row('Profile', 'Built-in (MR Star)')],
            footer: Text(
              'No custom profile is assigned to the active device.',
              style: TextStyle(color: tokens.onSurfaceVariant, fontSize: 12),
            ),
          );
        }
        final verification = state.verificationFor(assigned.id);
        return _Card(
          rows: [
            _Row('Profile', assigned.name),
            _Row('Profile ID', assigned.id),
            _Row('Verification', verification.label),
            if (verification.message != null &&
                verification.message!.isNotEmpty)
              _Row('Detail', verification.message!),
            _Row(
              'Capabilities',
              assigned.capabilities.map((c) => c.label).join(', '),
            ),
          ],
        );
      },
    );
  }
}

class _LightDiagnosticsCard extends StatelessWidget {
  const _LightDiagnosticsCard();

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return BlocBuilder<LightBloc, LightState>(
      builder: (context, state) {
        if (state is LightError) {
          return _Card(rows: [_Row('Error', state.message)]);
        }
        final capabilities = state.lightCapabilities.toList()
          ..sort((a, b) => a.name.compareTo(b.name));
        final color = state.lightColor;
        return _Card(
          rows: [
            _Row('Connected', state.lightIsConnected ? 'yes' : 'no'),
            _Row('Power', state.isLightOn ? 'on' : 'off'),
            _Row('Colour', '${color.red}, ${color.green}, ${color.blue}'),
            _Row('Brightness', '${state.lightBrightness}'),
            _Row('Effect', state.lightEffect ?? '—'),
            _Row('Speed', state.lightSpeed?.toString() ?? '—'),
            _Row(
              'Capabilities',
              capabilities.isEmpty
                  ? 'none (profile not verified)'
                  : capabilities.map((c) => c.label).join(', '),
            ),
          ],
          footer: Text(
            'These are the last values StarLight confirmed writing. They are '
            'not a live read-back from the hardware.',
            style: TextStyle(color: tokens.onSurfaceVariant, fontSize: 12),
          ),
        );
      },
    );
  }
}

class _AppCard extends StatelessWidget {
  const _AppCard();

  @override
  Widget build(BuildContext context) {
    final connectedState = context.select<BleBloc, String>(
      (state) => state is BleConnecting
          ? 'connecting'
          : state is BleConnected
          ? 'connected'
          : 'idle',
    );
    return _Card(
      rows: [
        const _Row('Version', '1.0.0'),
        const _Row('Effect schema', 'v1'),
        _Row('Transport', 'Bluetooth Low Energy'),
        _Row('Connection state', connectedState),
      ],
    );
  }
}

/// Small helper to keep the many rows consistent.
class _Row {
  final String label;
  final String value;

  const _Row(this.label, this.value);
}

class _Card extends StatelessWidget {
  final List<_Row> rows;
  final Widget? footer;

  const _Card({required this.rows, this.footer});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.tokens;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: tokens.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final row in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 120,
                    child: Text(
                      row.label,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: tokens.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      row.value,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (footer != null) ...[const SizedBox(height: 10), footer!],
        ],
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
        fontSize: 16,
        fontWeight: FontWeight.w700,
        color: context.tokens.onSurface,
      ),
    );
  }
}
