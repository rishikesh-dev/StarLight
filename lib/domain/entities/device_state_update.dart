// SPDX-License-Identifier: Apache-2.0

import 'package:equatable/equatable.dart';

/// Types of state updates that can be parsed from notify packets.
enum StateUpdateType { power, brightness, color, mic, unknown }

/// A structured state update parsed from a notify packet.
class DeviceStateUpdate extends Equatable {
  final StateUpdateType type;
  final dynamic value;

  const DeviceStateUpdate({required this.type, required this.value});

  @override
  List<Object?> get props => [type, value];
}
