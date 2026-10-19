// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:starlight/presentation/bloc/registry/device_registry_cubit.dart';
import 'package:starlight/presentation/bloc/room/room_cubit.dart';
import 'package:starlight/presentation/bloc/scene/scene_bloc.dart';
import 'package:starlight/presentation/bloc/scene/scene_event.dart';
import 'package:starlight/presentation/bloc/scene/scene_state.dart';
import 'package:starlight/presentation/pages/home/widgets/home_devices.dart';
import 'package:starlight/presentation/pages/home/widgets/home_header.dart';
import 'package:starlight/presentation/pages/home/widgets/home_hero.dart';
import 'package:starlight/presentation/pages/home/widgets/home_quick_actions.dart';
import 'package:starlight/presentation/pages/home/widgets/home_rooms.dart';
import 'package:starlight/presentation/pages/home/widgets/home_scenes.dart';

/// Home dashboard — the primary landing screen.
///
/// Every section is a projection of the real [BleBloc]/[LightBloc]/[RoomCubit]/[SceneBloc]
/// state: the header, the featured overview, the scene previews, the device card
/// and the quick actions. Nothing counts, colours or connections on this screen
/// are invented — where a feature (such as rooms) is not implemented yet, that
/// section degrades to an honest, non-fictional representation instead of a
/// placeholder.
class HomePage extends StatefulWidget {
  /// Invoked when the user needs to pair a device.
  final VoidCallback? onAddDevice;

  /// Invoked when the user opens Settings. The shell reports Settings via the
  /// bottom bar, so this only needs to exist when a real destination does.
  final VoidCallback? onOpenSettings;

  const HomePage({super.key, this.onAddDevice, this.onOpenSettings});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String? _selectedRoomId;

  @override
  Widget build(BuildContext context) {
    final onAddDevice = widget.onAddDevice ?? () {};
    return MultiBlocListener(
      listeners: [
        BlocListener<SceneBloc, SceneState>(
          listener: (context, state) {
            // SceneBloc handles its own loading/error states
          },
        ),
      ],
      child: BlocBuilder<RoomCubit, RoomState>(
        builder: (context, roomState) {
          final rooms = roomState.rooms;
          return BlocBuilder<DeviceRegistryCubit, DeviceRegistryState>(
            builder: (context, registryState) {
              // Compute device counts per room
              final roomDeviceCounts = <String, int>{};
              // Overview count: every device StarLight knows about.
              roomDeviceCounts['__home__'] = registryState.devices.length;
              // Per-room counts come from the real membership (device.roomId).
              for (final room in rooms) {
                roomDeviceCounts[room.id] = registryState
                    .inRoom(room.id)
                    .length;
              }

              return Scaffold(
                body: SafeArea(
                  bottom: false,
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 720),
                      child: ListView(
                        padding: const EdgeInsets.only(top: 4, bottom: 28),
                        children: [
                          HomeHeader(onOpenSettings: widget.onOpenSettings),
                          const SizedBox(height: 12),
                          HomeHero(onAddDevice: onAddDevice),
                          const SizedBox(height: 20),
                          HomeRooms(
                            rooms: rooms,
                            selectedRoomId: _selectedRoomId,
                            onSelect: (id) =>
                                setState(() => _selectedRoomId = id),
                            roomDeviceCounts: roomDeviceCounts,
                          ),
                          const SizedBox(height: 20),
                          HomeScenes(onRunScene: _runScene),
                          const SizedBox(height: 20),
                          HomeDevices(
                            onAddDevice: onAddDevice,
                            selectedRoomId: _selectedRoomId,
                          ),
                          const SizedBox(height: 20),
                          HomeQuickActions(
                            onAddDevice: onAddDevice,
                            onOpenSettings: widget.onOpenSettings,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  void _runScene(String sceneId) {
    context.read<SceneBloc>().add(RunScene(sceneId));
  }
}
