// SPDX-License-Identifier: Apache-2.0

import '../entities/saved_device.dart';

/// Persists the single paired device so the connection can be restored
/// across app restarts.
abstract class SavedDeviceRepository {
  /// Returns the paired device, or `null` when none has been paired yet.
  Future<SavedDevice?> load();

  /// Persists [device] as the current paired device (replacing any previous).
  Future<void> save(SavedDevice device);

  /// Removes the paired device.
  Future<void> remove();
}
