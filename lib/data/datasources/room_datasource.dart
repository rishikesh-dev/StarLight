// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:starlight/core/utils/app_logger.dart';

import '../models/room_model.dart';

/// Data source for persisting rooms to SharedPreferences.
class RoomDataSource {
  static const String roomsKey = 'starlight_rooms_v1';

  final SharedPreferences prefs;

  RoomDataSource(this.prefs);

  Future<List<RoomModel>> loadRooms() async {
    AppLog.debug('loadRooms: reading key "$roomsKey"');
    final raw = prefs.getString(roomsKey);
    if (raw == null || raw.isEmpty) {
      AppLog.debug('loadRooms: no saved rooms');
      return const [];
    }
    try {
      final List<dynamic> json = jsonDecode(raw) as List<dynamic>;
      return json
          .map((e) => RoomModel.fromMap(Map<String, dynamic>.from(e)))
          .toList();
    } catch (e) {
      AppLog.warn('loadRooms: failed to decode, returning empty: $e');
      return const [];
    }
  }

  Future<void> saveRooms(List<RoomModel> rooms) async {
    final json = rooms.map((r) => r.toMap()).toList();
    await prefs.setString(roomsKey, jsonEncode(json));
    AppLog.debug('saveRooms: saved ${rooms.length} room(s)');
  }

  Future<void> saveRoom(RoomModel room) async {
    final rooms = await loadRooms();
    final index = rooms.indexWhere((r) => r.id == room.id);
    if (index >= 0) {
      rooms[index] = room;
    } else {
      rooms.add(room);
    }
    await saveRooms(rooms);
  }

  Future<void> removeRoom(String roomId) async {
    final rooms = await loadRooms();
    rooms.removeWhere((r) => r.id == roomId);
    await saveRooms(rooms);
  }
}
