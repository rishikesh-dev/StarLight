import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:starlight/domain/entities/ble_device.dart';
import 'package:starlight/presentation/bloc/ble/ble_bloc.dart';
import 'package:starlight/presentation/bloc/ble/ble_event.dart';
import 'package:starlight/presentation/bloc/ble/ble_state.dart';
import 'package:starlight/presentation/widgets/device_list_item.dart';

/// BLE scanner page reached from Devices → Add Device.
class AddDevicePage extends StatefulWidget {
  const AddDevicePage({super.key});

  @override
  State<AddDevicePage> createState() => _AddDevicePageState();
}

class _AddDevicePageState extends State<AddDevicePage> {
  String? _connectingDeviceId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Add Device'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: BlocConsumer<BleBloc, BleState>(
        listener: (context, state) {
          if (state is BleError) {
            ScaffoldMessenger.of(context).showsnackbar(
              Snackbar(content: Text(state.message)),
            );
          }
          if (state is BleConnected) {
            Navigator.of(context).pop();
          }
          if (state is BleDisconnected) {
            _connectingDeviceId = null;
          }
        },
        builder: (context, state) {
          if (state is BleScanning) {
            if (state.devices.isEmpty) {
              return _EmptyScan(onScan: () => context.read<BleBloc>().add(StartScan()));
            }
            return _DeviceList(
              devices: state.devices,
              connectingId: _connectingDeviceId,
              onConnect: (device) {
                setState(() => _connectingDeviceId = device.id);
                context.read<BleBloc>().add(ConnectToDevice(device.id, device.name));
              },
            );
          }
          if (state is BleConnecting) {
            return const Center(
              child: Column(
                children: [
                  SizedBox(height: 16),
                  Text('Connecting...'),
                ],
              ),
            );
          }
          return _EmptyScan(onScan: () => context.read<BleBloc>().add(StartScan()));
        },
      ),
    );
  }
}

class _EmptyScan extends StatelessWidget {
  final VoidCallback onScan;

  const _EmptyScan({required this.onScan});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        children: [
          const Icon(Icons.bluetooth_searching, size: 64, color: Colors.grey),
          const SizedBox(height: 16),
          const Text(
            'No devices found',
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: onScan,
            icon: const Icon(Icons.search),
            label: const Text('Scan for BLE devices'),
          ),
        ],
      ),
    );
  }
}

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
