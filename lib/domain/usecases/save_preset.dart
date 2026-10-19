// SPDX-License-Identifier: Apache-2.0

import '../../core/utils/app_logger.dart';
import '../entities/preset.dart';
import '../repositories/preset_repository.dart';

/// Use case for saving a preset to local storage.
class SavePresetUseCase {
  final PresetRepository repository;

  SavePresetUseCase(this.repository);

  Future<void> call(Preset preset) async {
    AppLog.debug('usecase: savePreset id=${preset.id} name="${preset.name}"');
    await repository.savePreset(preset);
  }
}
