import 'package:equatable/equatable.dart';

/// A user-defined or built-in color preset.
class Preset extends Equatable {
  final int id;
  final String name;
  final int red;
  final int green;
  final int blue;

  const Preset({
    required this.id,
    required this.name,
    required this.red,
    required this.green,
    required this.blue,
  });

  Preset copyWith({
    int? id,
    String? name,
    int? red,
    int? green,
    int? blue,
  }) {
    return Preset(
      id: id ?? this.id,
      name: name ?? this.name,
      red: red ?? this.red,
      green: green ?? this.green,
      blue: blue ?? this.blue,
    );
  }

  @override
  List<Object?> get props => [id, name, red, green, blue];
}
