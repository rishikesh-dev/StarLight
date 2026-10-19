// SPDX-License-Identifier: Apache-2.0

import '../../core/utils/app_logger.dart';
import '../../domain/entities/preset.dart';
import '../../domain/repositories/preset_repository.dart';
import '../datasources/preset_datasource.dart';
import '../models/preset_model.dart';

/// Implementation of [PresetRepository] using local SharedPreferences storage.
class PresetRepositoryImpl implements PresetRepository {
  final PresetDataSource dataSource;

  PresetRepositoryImpl(this.dataSource) {
    AppLog.debug('PresetRepositoryImpl created');
  }

  @override
  Future<List<Preset>> loadPresets() async {
    AppLog.debug('repository: loadPresets');
    final models = await dataSource.loadPresets();
    return models
        .map(
          (m) => Preset(
            id: m.id,
            name: m.name,
            red: m.red,
            green: m.green,
            blue: m.blue,
          ),
        )
        .toList();
  }

  @override
  Future<void> savePreset(Preset preset) {
    AppLog.debug(
      'repository: savePreset id=${preset.id} name="${preset.name}"',
    );
    return dataSource.savePreset(
      PresetModel(
        id: preset.id,
        name: preset.name,
        red: preset.red,
        green: preset.green,
        blue: preset.blue,
      ),
    );
  }

  @override
  Future<void> deletePreset(int id) {
    AppLog.debug('repository: deletePreset id=$id');
    return dataSource.deletePreset(id);
  }

  @override
  Future<void> savePresets(List<Preset> presets) {
    AppLog.debug('repository: savePresets (${presets.length} preset(s))');
    return dataSource.savePresets(
      presets
          .map(
            (p) => PresetModel(
              id: p.id,
              name: p.name,
              red: p.red,
              green: p.green,
              blue: p.blue,
            ),
          )
          .toList(),
    );
  }
}
