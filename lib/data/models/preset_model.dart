// SPDX-License-Identifier: Apache-2.0

import 'package:equatable/equatable.dart';

/// Data layer model for a preset.
class PresetModel extends Equatable {
  final int id;
  final String name;
  final int red;
  final int green;
  final int blue;

  const PresetModel({
    required this.id,
    required this.name,
    required this.red,
    required this.green,
    required this.blue,
  });

  Map<String, dynamic> toMap() {
    return {'id': id, 'name': name, 'red': red, 'green': green, 'blue': blue};
  }

  factory PresetModel.fromMap(Map<String, dynamic> map) {
    return PresetModel(
      id: map['id'] as int,
      name: map['name'] as String,
      red: map['red'] as int,
      green: map['green'] as int,
      blue: map['blue'] as int,
    );
  }

  @override
  List<Object?> get props => [id, name, red, green, blue];
}
