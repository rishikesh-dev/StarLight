// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:starlight/domain/entities/ble_device.dart';
import 'package:starlight/presentation/bloc/ble/ble_bloc.dart';
import 'package:starlight/presentation/bloc/ble/ble_event.dart';
import 'package:starlight/presentation/bloc/ble/ble_state.dart';
import 'package:starlight/presentation/theme/app_theme.dart';
import 'package:starlight/presentation/widgets/device_list_item.dart';

/// BLE discovery page reached from the "Add Device" tab or the Devices → Add
/// Device route.
///
/// When [embedded] is true it is hosted inside the app shell's navigation (no
/// close button, no auto-pop on connect); [onConnected] is then invoked so the
/// shell can switch to the Home tab. [active] indicates whether the tab is
/// currently visible: the page scans when it becomes active and stops when it
/// is hidden, so it never scans in the background or duplicates a scan.
class AddDevicePage extends StatefulWidget {
  final bool embedded;
  final bool active;
  final VoidCallback? onConnected;

  const AddDevicePage({
    super.key,
    this.embedded = false,
    this.active = true,
    this.onConnected,
  });

  @override
  State<AddDevicePage> createState() => _AddDevicePageState();
}

class _AddDevicePageState extends State<AddDevicePage> {
  String? _connectingDeviceId;
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    if (widget.active) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _startScan());
    }
  }

  @override
  void didUpdateWidget(AddDevicePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) {
      _startScan();
    } else if (!widget.active && oldWidget.active) {
      _stopScan();
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Starts a scan unless the transport is already busy with one.
  void _startScan() {
    if (!mounted) return;
    final bloc = context.read<BleBloc>();
    final state = bloc.state;
    if (state is BleScanning ||
        state is BleConnecting ||
        state is BleConnected) {
      return;
    }
    bloc.add(const StartScan());
  }

  void _stopScan() {
    if (!mounted) return;
    context.read<BleBloc>().add(const StopScanRequested());
  }

  List<BleDevice> _filtered(List<BleDevice> devices) {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return devices;
    return devices
        .where(
          (d) =>
              d.name.toLowerCase().contains(query) ||
              d.id.toLowerCase().contains(query),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Add Device'),
        automaticallyImplyLeading: !widget.embedded,
        leading: widget.embedded
            ? null
            : IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).pop(),
              ),
        actions: [
          BlocBuilder<BleBloc, BleState>(
            buildWhen: (previous, current) =>
                (previous is BleScanning) != (current is BleScanning),
            builder: (context, state) => state is BleScanning
                ? IconButton(
                    icon: const Icon(Icons.refresh),
                    tooltip: 'Scan again',
                    onPressed: () =>
                        context.read<BleBloc>().add(const StartScan()),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
      body: BlocConsumer<BleBloc, BleState>(
        listener: (context, state) {
          if (state is BleError) {
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(SnackBar(content: Text(state.message)));
          }
          if (state is BleConnected) {
            if (widget.embedded) {
              widget.onConnected?.call();
            } else {
              Navigator.of(context).pop();
            }
          }
          if (state is BleDisconnected) {
            _connectingDeviceId = null;
          }
        },
        builder: (context, state) {
          if (state is BleScanning) {
            return _ScanResults(
              devices: _filtered(state.devices),
              totalCount: state.devices.length,
              query: _query,
              controller: _searchController,
              connectingId: _connectingDeviceId,
              onChanged: (value) => setState(() => _query = value),
              onClearQuery: () {
                _searchController.clear();
                setState(() => _query = '');
              },
              onConnect: (device) {
                setState(() => _connectingDeviceId = device.id);
                context.read<BleBloc>().add(
                  ConnectToDevice(device.id, device.name),
                );
              },
            );
          }
          if (state is BleConnecting) {
            return _StatusMessage(
              icon: Icons.bluetooth_connected,
              title: 'Connecting…',
              message: 'Connecting to ${state.deviceName}',
              busy: true,
            );
          }
          if (state is BleBluetoothEnabling) {
            return const _StatusMessage(
              icon: Icons.bluetooth,
              title: 'Turning on Bluetooth…',
              message: 'Waiting for Bluetooth to become available.',
              busy: true,
            );
          }
          if (state is BleBluetoothOff) {
            return _StatusMessage(
              icon: Icons.bluetooth_disabled,
              title: 'Bluetooth is off',
              message: state.message,
              actionLabel: 'Turn on Bluetooth',
              onAction: () => context.read<BleBloc>().add(RetryBluetooth()),
            );
          }
          if (state is BleBluetoothUnavailable) {
            return _StatusMessage(
              icon: Icons.bluetooth_disabled,
              title: 'Bluetooth unavailable',
              message: state.message,
            );
          }
          if (state is BlePermissionDenied) {
            return _StatusMessage(
              icon: Icons.lock_outline,
              title: 'Bluetooth permission needed',
              message: state.message,
              actionLabel: state.permanentlyDenied
                  ? 'Open settings'
                  : 'Grant permission',
              onAction: state.permanentlyDenied
                  ? () => context.read<BleBloc>().add(
                      const OpenAppSettingsRequested(),
                    )
                  : () => context.read<BleBloc>().add(const RetryBluetooth()),
            );
          }
          if (state is BleError) {
            return _StatusMessage(
              icon: Icons.error_outline,
              title: 'Something went wrong',
              message: state.message,
              actionLabel: 'Try again',
              onAction: () =>
                  context.read<BleBloc>().add(const EnsureBluetoothReady()),
            );
          }
          return _ScanPrompt(
            savedDeviceName: state is BleDisconnected
                ? state.device?.name
                : null,
            onScan: _startScan,
          );
        },
      ),
    );
  }
}

/// Centered status message with an optional action button.
class _StatusMessage extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final bool busy;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _StatusMessage({
    required this.icon,
    required this.title,
    required this.message,
    this.busy = false,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (busy)
              const SizedBox(
                width: 36,
                height: 36,
                child: CircularProgressIndicator(strokeWidth: 3),
              )
            else
              Icon(icon, size: 40, color: tokens.onSurfaceVariant),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: tokens.onSurfaceVariant),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: onAction,
                  child: Text(actionLabel!),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Empty/idle state with an explicit scan action.
class _ScanPrompt extends StatelessWidget {
  final String? savedDeviceName;
  final VoidCallback onScan;

  const _ScanPrompt({this.savedDeviceName, required this.onScan});

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.bluetooth_searching,
              size: 48,
              color: tokens.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            const Text(
              'Find your device',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(
              'Make sure your StarLight is powered on and nearby.',
              textAlign: TextAlign.center,
              style: TextStyle(color: tokens.onSurfaceVariant),
            ),
            if (savedDeviceName != null && savedDeviceName!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                'Saved device: $savedDeviceName',
                textAlign: TextAlign.center,
                style: TextStyle(color: tokens.onSurfaceVariant, fontSize: 12),
              ),
            ],
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onScan,
                icon: const Icon(Icons.search),
                label: const Text('Scan for devices'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The scanning state: a search field (once results exist) plus the list of
/// discovered devices, or a progress indicator while nothing is found yet.
class _ScanResults extends StatelessWidget {
  final List<BleDevice> devices;
  final int totalCount;
  final String query;
  final TextEditingController controller;
  final String? connectingId;
  final ValueChanged<String> onChanged;
  final VoidCallback onClearQuery;
  final ValueChanged<BleDevice> onConnect;

  const _ScanResults({
    required this.devices,
    required this.totalCount,
    required this.query,
    required this.controller,
    this.connectingId,
    required this.onChanged,
    required this.onClearQuery,
    required this.onConnect,
  });

  @override
  Widget build(BuildContext context) {
    if (totalCount == 0) return const _ScanningEmpty();
    return Column(
      children: [
        _SearchField(
          controller: controller,
          onChanged: onChanged,
          hasQuery: query.trim().isNotEmpty,
          onClear: onClearQuery,
        ),
        Expanded(
          child: devices.isEmpty
              ? _NoMatches(query: query)
              : _DeviceList(
                  devices: devices,
                  connectingId: connectingId,
                  onConnect: onConnect,
                ),
        ),
      ],
    );
  }
}

class _SearchField extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback? onClear;
  final bool hasQuery;

  const _SearchField({
    required this.controller,
    required this.onChanged,
    this.onClear,
    this.hasQuery = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: 'Search devices',
          prefixIcon: const Icon(Icons.search),
          isDense: true,
          suffixIcon: hasQuery
              ? IconButton(
                  icon: const Icon(Icons.clear),
                  tooltip: 'Clear search',
                  onPressed: onClear,
                )
              : null,
        ),
      ),
    );
  }
}

class _ScanningEmpty extends StatelessWidget {
  const _ScanningEmpty();

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 36,
              height: 36,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
            const SizedBox(height: 16),
            const Text(
              'Searching for devices…',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(
              'Make sure your StarLight is powered on and nearby.',
              textAlign: TextAlign.center,
              style: TextStyle(color: tokens.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _NoMatches extends StatelessWidget {
  final String query;

  const _NoMatches({required this.query});

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off, size: 40, color: tokens.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(
              'No devices match "$query"',
              textAlign: TextAlign.center,
              style: TextStyle(color: tokens.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

/// Sorted list of discovered devices (known StarLight devices first, then by
/// signal strength).
class _DeviceList extends StatelessWidget {
  final List<BleDevice> devices;
  final String? connectingId;
  final ValueChanged<BleDevice> onConnect;

  const _DeviceList({
    required this.devices,
    this.connectingId,
    required this.onConnect,
  });

  @override
  Widget build(BuildContext context) {
    final sorted = [...devices]
      ..sort((a, b) {
        final aDemo = a.name.contains('GATT--DEMO');
        final bDemo = b.name.contains('GATT--DEMO');
        if (aDemo && !bDemo) return -1;
        if (!aDemo && bDemo) return 1;
        return b.rssi.compareTo(a.rssi);
      });

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: sorted.length,
      itemBuilder: (context, index) {
        final device = sorted[index];
        return DeviceListItem(
          device: device,
          isConnecting: connectingId == device.id,
          onConnect: () => onConnect(device),
          onDisconnect: () {},
        );
      },
    );
  }
}
