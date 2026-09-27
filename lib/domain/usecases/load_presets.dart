import '../../core/utils/app_logger.dart';
import '../entities/preset.dart';
import '../repositories/preset_repository.dart';

/// Use case for loading all presets from local storage.
class LoadPresetsUseCase {
  final PresetRepository repository;

  LoadPresetsUseCase(this.repository);

  Future<List<Preset>> call() async {
    AppLog.debug('usecase: loadPresets');
    final presets = await repository.loadPresets();
    AppLog.debug('usecase: loadPresets returned ${presets.length} preset(s)');
    return presets;
  }
}
