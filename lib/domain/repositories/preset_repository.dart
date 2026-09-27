import '../entities/preset.dart';

/// Abstract repository for preset storage.
abstract class PresetRepository {
  /// Loads all presets from local storage.
  Future<List<Preset>> loadPresets();

  /// Saves a single preset.
  Future<void> savePreset(Preset preset);

  /// Deletes a preset by ID.
  Future<void> deletePreset(int id);

  /// Saves the entire preset list.
  Future<void> savePresets(List<Preset> presets);
}
