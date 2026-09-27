import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:starlight/presentation/bloc/ble/ble_bloc.dart';
import 'package:starlight/presentation/bloc/ble/ble_state.dart';
import 'package:starlight/presentation/bloc/light/light_bloc.dart';
import 'package:starlight/presentation/bloc/light/light_event.dart';
import 'package:starlight/presentation/bloc/light/light_state.dart';
import 'package:starlight/presentation/theme/app_theme.dart';
import 'package:starlight/presentation/widgets/connected_light_card.dart';
import 'package:starlight/presentation/widgets/section_header.dart';

/// Home dashboard — the primary landing screen.
///
/// Shows a greeting, connected devices, rooms, favorites, and scenes.
/// All controls route through the existing [LightBloc]/[BleBloc].
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('StarLight'),
        elevation: 0,
      ),
      body: BlocBuilder<BleBloc, BleState>(
        builder: (context, bleState) {
          final connected = bleState is BleConnected;
          return CustomScrollView(
            slivers: [
              const SliverToBoxAdapter(
                child: _Greeting(),
              ),
              if (connected) ...[
                const SliverToBoxAdapter(
                  child: SectionHeader(
                    title: 'Connected Devices',
                    trailing: Text('1', style: TextStyle(color: AppColors.onSurfaceVariant)),
                  ),
                ),
                const SliverToBoxAdapter(
                  child: ConnectedLightCard(),
                ),
              ] else ...[
                const SliverToBoxAdapter(
                  child: _NoConnectedState(),
                ),
              ],
              const SliverToBoxAdapter(
                child: SectionHeader(title: 'Favorites'),
              ),
              const SliverToBoxAdapter(
                child: _FavoritesSection(),
              ),
              const SliverToBoxAdapter(
                child: SectionHeader(title: 'Scenes'),
              ),
              const SliverToBoxAdapter(
                child: _ScenesSection(),
              ),
              const SliverPadding(padding: EdgeInsets.all(24)),
            ],
          );
        },
      ),
    );
  }
}

class _Greeting extends StatelessWidget {
  const _Greeting();

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 18) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _greeting(),
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 4),
          Text(
            'Welcome back',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _NoConnectedState extends StatelessWidget {
  const _NoConnectedState();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          const Icon(Icons.bluetooth_searching, size: 48, color: AppColors.onSurfaceVariant),
          const SizedBox(height: 12),
          const Text(
            'No devices connected',
            style: TextStyle(color: AppColors.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.add),
            label: const Text('Add Device'),
          ),
        ],
      ),
    );
  }
}

class _FavoritesSection extends StatelessWidget {
  const _FavoritesSection();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: const Center(
        child: Text(
          'No favorites yet',
          style: TextStyle(color: AppColors.onSurfaceVariant),
        ),
      ),
    );
  }
}

class _ScenesSection extends StatelessWidget {
  const _ScenesSection();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<LightBloc, LightState>(
      builder: (context, state) {
        final presets = switch (state) {
          LightOn(:final presets) => presets,
          LightOff(:final presets) => presets,
          PresetsLoaded(:final presets) => presets,
          _ => const <dynamic>[],
        };
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final p in presets.take(4))
                _SceneChip(preset: p),
            ],
          ),
        );
      },
    );
  }
}

class _SceneChip extends StatelessWidget {
  final dynamic preset;

  const _SceneChip({required this.preset});

  @override
  Widget build(BuildContext context) {
    final color = Color(
      ((preset.red as int) << 16) | ((preset.green as int) << 8) | (preset.blue as int),
    );
    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.border, width: 1),
        boxShadow: glowShadow(color: color, radius: 8),
      ),
    );
  }
}
