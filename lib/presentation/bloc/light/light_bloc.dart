import 'package:bloc/bloc.dart';

import 'package:starlight/core/utils/app_logger.dart';
import 'package:starlight/domain/entities/connection_state.dart';
import 'package:starlight/domain/entities/preset.dart';
import 'package:starlight/domain/entities/rgb_color.dart';
import 'package:starlight/domain/repositories/ble_repository.dart';
import 'package:starlight/domain/repositories/preset_repository.dart';
import 'package:starlight/domain/usecases/load_presets.dart';
import 'package:starlight/domain/usecases/save_preset.dart';
import 'package:starlight/domain/usecases/send_brightness_command.dart';
import 'package:starlight/domain/usecases/send_color_command.dart';
import 'package:starlight/domain/usecases/send_power_command.dart';

import 'light_event.dart';
import 'light_state.dart';

/// BLoC for managing light control: power, color, brightness, presets.
class LightBloc extends Bloc<LightEvent, LightState> {
  final BleRepository _bleRepository;
  final PresetRepository _presetRepository;
  final SendPowerCommand _sendPower;
  final SendColorCommand _sendColor;
  final SendBrightnessCommand _sendBrightness;
  final LoadPresetsUseCase _loadPresets;
  final SavePresetUseCase _savePreset;

  RGBColor _currentColor = const RGBColor(255, 0, 0);
  int _currentBrightness = 1000;
  bool _isOn = true;
  bool _isConnected = false;
  List<Preset> _presets = [];

  @override
  String toString() => 'LightBloc(state: $state)';

  LightBloc(
    this._bleRepository,
    this._presetRepository,
  )   : _sendPower = SendPowerCommand(_bleRepository),
        _sendColor = SendColorCommand(_bleRepository),
        _sendBrightness = SendBrightnessCommand(_bleRepository),
        _loadPresets = LoadPresetsUseCase(_presetRepository),
        _savePreset = SavePresetUseCase(_presetRepository),
        super(LightInitial()) {
    on<TogglePower>(_onTogglePower);
    on<ChangeColor>(_onChangeColor);
    on<ChangeBrightness>(_onChangeBrightness);
    on<SelectPreset>(_onSelectPreset);
    on<LoadPresets>(_onLoadPresets);
    on<SavePreset>(_onSavePreset);
    on<DeletePreset>(_onDeletePreset);
    on<ClearPresets>(_onClearPresets);

    _bleRepository.connectionState.listen(_onConnectionState);
    AppLog.info('LightBloc initialized');
  }

  @override
  void onTransition(Transition<LightEvent, LightState> transition) {
    AppLog.debug(
      'LIGHT transition: ${transition.event.runtimeType} '
      '(${_stateSummary(transition.event)})\n'
      '      ${transition.currentState.runtimeType} '
      '→ ${transition.nextState.runtimeType}',
    );
    super.onTransition(transition);
  }

  static String _stateSummary(LightEvent event) {
    if (event is TogglePower) return 'on=${event.on}';
    if (event is ChangeColor) return 'rgb=${event.color.red},${event.color.green},${event.color.blue}';
    if (event is ChangeBrightness) return 'brightness=${event.brightness}';
    if (event is SelectPreset) return 'rgb=${event.red},${event.green},${event.blue}';
    if (event is SavePreset) return 'id=${event.id} name="${event.name}"';
    if (event is DeletePreset) return 'id=${event.id}';
    return '';
  }

  void _onConnectionState(DeviceConnectionState state) {
    AppLog.debug('LIGHT: connection state: $state');
    _isConnected = state == DeviceConnectionState.connected;
  }

  Future<void> _onChangeColor(
    ChangeColor event,
    Emitter<LightState> emit,
  ) async {
    AppLog.info(
      'LIGHT event: ChangeColor rgb=(${event.color.red},'
      '${event.color.green},${event.color.blue})',
    );

    try {
      await _sendColor(event.color.red, event.color.green, event.color.blue);
    } catch (e) {
      AppLog.error('LIGHT: failed to send color command', e);
      emit(LightError(e.toString()));
      return;
    }

    _currentColor = event.color;
    _isOn = true;
    emit(_currentOnState());
  }

  LightState _currentOnState() {
    if (_isOn) {
      return LightOn(
        color: _currentColor,
        brightness: _currentBrightness,
        presets: List.of(_presets),
        isConnected: _isConnected,
      );
    }
    return LightOff(
      brightness: _currentBrightness,
      presets: List.of(_presets),
      isConnected: _isConnected,
    );
  }

  Future<void> _onTogglePower(
    TogglePower event,
    Emitter<LightState> emit,
  ) async {
    AppLog.info('LIGHT event: TogglePower on=${event.on}');
    try {
      await _sendPower(event.on);
    } catch (e) {
      AppLog.error('LIGHT: failed to send power command', e);
      emit(LightError(e.toString()));
      return;
    }
    _isOn = event.on;
    emit(_currentOnState());
  }

  Future<void> _onChangeBrightness(
    ChangeBrightness event,
    Emitter<LightState> emit,
  ) async {
    AppLog.info('LIGHT event: ChangeBrightness ${event.brightness}');
    try {
      await _sendBrightness(event.brightness);
    } catch (e) {
      AppLog.error('LIGHT: failed to send brightness command', e);
      emit(LightError(e.toString()));
      return;
    }
    _currentBrightness = event.brightness;
    emit(_currentOnState());
  }

  Future<void> _onSelectPreset(
    SelectPreset event,
    Emitter<LightState> emit,
  ) async {
    AppLog.info(
      'LIGHT event: SelectPreset rgb=(${event.red},${event.green},${event.blue})',
    );
    try {
      await _sendColor(event.red, event.green, event.blue);
    } catch (e) {
      AppLog.error('LIGHT: failed to send preset color command', e);
      emit(LightError(e.toString()));
      return;
    }
    _currentColor = RGBColor(event.red, event.green, event.blue);
    _isOn = true;
    emit(_currentOnState());
  }

  Future<void> _onLoadPresets(
    LoadPresets event,
    Emitter<LightState> emit,
  ) async {
    AppLog.info('LIGHT event: LoadPresets');
    try {
      _presets = await _loadPresets();
      AppLog.debug('LIGHT: loaded ${_presets.length} preset(s)');
    } catch (e) {
      AppLog.error('LIGHT: failed to load presets', e);
      emit(LightError(e.toString()));
      return;
    }
    emit(PresetsLoaded(
      color: _currentColor,
      brightness: _currentBrightness,
      presets: List.of(_presets),
      isOn: _isOn,
      isConnected: _isConnected,
    ));
  }

  Future<void> _onSavePreset(
    SavePreset event,
    Emitter<LightState> emit,
  ) async {
    AppLog.info(
      'LIGHT event: SavePreset id=${event.id} name="${event.name}" '
      'rgb=(${event.red},${event.green},${event.blue})',
    );
    try {
      await _savePreset(Preset(
        id: event.id,
        name: event.name,
        red: event.red,
        green: event.green,
        blue: event.blue,
      ));
      add(LoadPresets());
    } catch (e) {
      AppLog.error('LIGHT: failed to save preset', e);
      emit(LightError(e.toString()));
    }
  }

  Future<void> _onDeletePreset(
    DeletePreset event,
    Emitter<LightState> emit,
  ) async {
    AppLog.info('LIGHT event: DeletePreset id=${event.id}');
    try {
      await _presetRepository.deletePreset(event.id);
      add(LoadPresets());
    } catch (e) {
      AppLog.error('LIGHT: failed to delete preset', e);
      emit(LightError(e.toString()));
    }
  }

  Future<void> _onClearPresets(
    ClearPresets event,
    Emitter<LightState> emit,
  ) async {
    AppLog.info('LIGHT event: ClearPresets');
    try {
      await _presetRepository.savePresets([]);
      _presets = [];
      add(LoadPresets());
    } catch (e) {
      AppLog.error('LIGHT: failed to clear presets', e);
      emit(LightError(e.toString()));
    }
  }
}