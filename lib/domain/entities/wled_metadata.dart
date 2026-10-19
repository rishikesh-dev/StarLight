// SPDX-License-Identifier: Apache-2.0

import 'package:equatable/equatable.dart';

/// Represents a WLED effect metadata.
class WledEffect extends Equatable {
  final int id;
  final String name;

  const WledEffect({required this.id, required this.name});

  @override
  List<Object?> get props => [id, name];
}

/// Represents a WLED palette metadata.
class WledPalette extends Equatable {
  final int id;
  final String name;

  const WledPalette({required this.id, required this.name});

  @override
  List<Object?> get props => [id, name];
}
