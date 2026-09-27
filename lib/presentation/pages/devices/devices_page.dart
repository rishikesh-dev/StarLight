import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:starlight/presentation/bloc/ble/ble_bloc.dart';
import 'package:starlight/presentation/bloc/ble/ble_event.dart';
import 'package:starlight/presentation/bloc/ble/ble_state.dart';
import 'package:starlight/presentation/theme/app_theme.dart';
import 'package:starlight/presentation/widgets/device_card.dart';

/// Devices management screen.
///
/// Lists configured devices with filters. The BLE scanner lives under
/// "Add Device" — this page is no longer scanner-first.
class DevicesPage extends StatefulWidget {
  const DevicesPage({super.key});

  @override
  State<DevicesPage> createState() => _DevicesPageState();
}

class _DevicesPageState extends State<DevicesPage> {
  String _filter = 'all';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Devices'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => Navigator.of(context).pushNamed('/add-device'),
            tooltip: 'Add device',
          ),
        ],
      ),
      body: BlocBuilder<BleBloc, BleState>(
        builder: (context, state) {
          final connected = state is BleConnected;
          final connecting = state is BleConnecting;

          return CustomScrollView(
            slivers: [
              const SliverToBoxAdapter(
                child: _FilterBar(),
              ),
              if (connected)
                const SliverToBoxAdapter(
                  child: _ConnectedBanner(),
                ),
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  child: Text('No other devices configured', style: TextStyle(color: AppColors.onSurfaceVariant)),
                ),
              ),
              if (connecting)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                ),
              const SliverPadding(padding: EdgeInsets.all(24)),
            ],
          );
        },
      ),
    );
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar();

  @override
  Widget build(BuildContext context) {
    final filters = ['all', 'lights', 'plugs', 'fans', 'sensors', 'tv', 'other'];
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: filters.length,
        itemBuilder: (context, index) {
          final f = filters[index];
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            child: FilterChip(
              selected: false,
              label: Text(f[0].toUpperCase() + f.substring(1)),
              onSelected: (_) {},
            ),
          );
        },
      ),
    );
  }
}

class _ConnectedBanner extends StatelessWidget {
  const _ConnectedBanner();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<BleBloc, BleState>(
      builder: (context, state) {
        final device = (state is BleConnected) ? state.device : null;
        if (device == null) return const SizedBox.shrink();
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          child: DeviceCard(
            device: device,
            onTap: () => Navigator.of(context).pushNamed('/controller'),
            onPowerToggle: () {},
          ),
        );
      },
    );
  }
}
