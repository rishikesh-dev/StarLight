// SPDX-License-Identifier: Apache-2.0

import 'package:equatable/equatable.dart';

/// The single paired MR Star controller the app restores automatically.
///
/// Persisted so that, on the next launch, [BleBloc] can re-connect without a
/// scan. The MAC [id] is the primary identifier; [name] is kept for display.
class SavedDevice extends Equatable {
  final String id;
  final String name;

  const SavedDevice({required this.id, required this.name});

  @override
  List<Object?> get props => [id, name];
}
