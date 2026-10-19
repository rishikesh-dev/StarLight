// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:flutter/foundation.dart';

import 'package:starlight/core/utils/app_logger.dart';
import 'package:starlight/domain/entities/connection_state.dart';
import 'package:starlight/domain/entities/device_capability.dart';
import 'package:starlight/domain/entities/device_command.dart';
import 'package:starlight/domain/entities/device_state_update.dart';
import 'package:starlight/domain/entities/effect.dart';
import 'package:starlight/domain/entities/preset.dart';
import 'package:starlight/domain/entities/rgb_color.dart';
import 'package:starlight/domain/repositories/ble_repository.dart';
import 'package:starlight/domain/repositories/preset_repository.dart';
import 'package:starlight/domain/services/command_router.dart';
import 'package:starlight/domain/services/custom_effect_player.dart';
import 'package:starlight/domain/services/effect_engine.dart';
import 'package:starlight/domain/usecases/load_presets.dart';
import 'package:starlight/domain/usecases/save_preset.dart';

import 'light_event.dart';
import 'light_state.dart';

/// BLoC for managing light control: power, color, brightness, presets.
class LightBloc extends Bloc<LightEvent, LightState> {
  final BleRepository _bleRepository;
  final PresetRepository _presetRepository;
  final LoadPresetsUseCase _loadPresets;
  final SavePresetUseCase _savePreset;

  /// Routes commands either to a verified custom profile or the built-in MR
  /// Star encoder. Shared with the profile cubit so assignment/verification
  /// decisions drive what the controls actually send.
  late final CommandRouter _router;

  CommandRouter get router => _router;

  /// Validates and dispatches effect/speed requests through [_router]. Keeps
  /// effect execution coherent (capability + parameter validation, stale-result
  /// suppression) without bypassing the single BLE owner.
  late final EffectEngine _effectEngine;

  /// Streams StarLight's custom effects as a bounded global-colour sequence
  /// through [_router]. Never opens a connection and never writes BLE directly.
  late final CustomEffectPlayer _customPlayer;

  RGBColor _currentColor = const RGBColor(255, 0, 0);
  int _currentBrightness = 1000;
  bool _isOn = true;
  bool _isConnected = false;

  /// Whether the current power/brightness/colour values are backed by a real
  /// observation: a device state notification (FFF4) or a command write that
  /// completed while connected. Until then the values are startup assumptions
  /// and the UI must not present them as the device's actual state.
  bool _hasConfirmedState = false;

  /// The device id the current session's confirmations belong to.
  String? _boundDeviceId;
  String? _currentEffect;
  int? _currentSpeed;
  String? _customEffectId;
  bool _customPlaying = false;
  int _customSpeed = 50;
  int _customIntensity = 70;
  String? _customPaletteId;
  List<Preset> _presets = [];
  Set<DeviceCapability> _capabilities = kDefaultLightCapabilities;
  StreamSubscription<DeviceConnectionState>? _connectionSub;
  StreamSubscription<DeviceStateUpdate>? _stateUpdateSub;
  StreamSubscription<DeviceStateUpdate>? _profileStateSub;

  @override
  String toString() => 'LightBloc(state: $state)';

  /// Whether the current power/brightness/colour values have been confirmed by
  /// the device (an FFF4 state notification) or by a command write that
  /// completed while connected. When `false` the UI should describe the
  /// connection without claiming an ON/OFF state or concrete values.
  bool get hasConfirmedState => _hasConfirmedState;

  LightBloc(
    this._bleRepository,
    this._presetRepository, {
    CommandRouter? router,
    Stream<DeviceStateUpdate>? profileStateUpdates,
  }) : _loadPresets = LoadPresetsUseCase(_presetRepository),
       _savePreset = SavePresetUseCase(_presetRepository),
       super(LightInitial()) {
    _router = router ?? CommandRouter(_bleRepository);
    _effectEngine = EffectEngine(_router);
    _customPlayer = CustomEffectPlayer(_router)
      ..onStopped = (result) => add(CustomEffectStopped(result));
    _capabilities = _router.capabilities;
    _router.addListener(_onRouterChanged);

    on<TogglePower>(_onTogglePower);
    on<ChangeColor>(_onChangeColor);
    on<ChangeBrightness>(_onChangeBrightness);
    on<ChangeEffect>(_onChangeEffect);
    on<ChangeSpeed>(_onChangeSpeed);
    on<PlayCustomEffect>(_onPlayCustomEffect);
    on<StopCustomEffect>(_onStopCustomEffect);
    on<ConfigureCustomEffect>(_onConfigureCustomEffect);
    on<CustomEffectStopped>(_onCustomEffectStopped);
    on<SelectPreset>(_onSelectPreset);
    on<LoadPresets>(_onLoadPresets);
    on<SavePreset>(_onSavePreset);
    on<DeletePreset>(_onDeletePreset);
    on<ClearPresets>(_onClearPresets);
    on<ConnectionChanged>(_onConnectionChanged);
    on<DeviceStateReceived>(_onDeviceStateReceived);
    on<CapabilitiesChanged>(_onCapabilitiesChanged);

    // The repository stream is app-lifetime, so this subscription stays live
    // across connects/disconnects (registering before any connect is safe).
    _connectionSub = _bleRepository.connectionState.listen(_onConnectionState);

    // Real device state notifications (decoded from FFF4). These feed the UI
    // with confirmed device state; command writes are never treated as
    // confirmation. Errors are surfaced without tearing down the bloc.
    _stateUpdateSub = _bleRepository.stateUpdates.listen(
      (update) => add(DeviceStateReceived(update.type, update.value)),
      onError: (Object e) {
        AppLog.warn('LIGHT: state update stream error: $e');
      },
    );

    // Custom-profile notifications, decoded by the profile executor.
    if (profileStateUpdates != null) {
      _profileStateSub = profileStateUpdates.listen(
        (update) => add(DeviceStateReceived(update.type, update.value)),
        onError: (Object e) {
          AppLog.warn('LIGHT: profile state update stream error: $e');
        },
      );
    }
    AppLog.info('LightBloc initialized');
  }

  /// Called by the app-level BLE listener when the active device changes.
  ///
  /// Rebinding invalidates any in-flight effect work so a result for the
  /// previous device is never applied to the new one. Active custom playback is
  /// stopped: it was streaming to the previous device.
  void onActiveDeviceChanged(String? deviceId) {
    // Confirmations belong to a specific device: a different (or lost) active
    // device makes the previous values unknown again.
    if (deviceId != _boundDeviceId) {
      _boundDeviceId = deviceId;
      _hasConfirmedState = false;
    }
    _effectEngine.bindDevice(deviceId);
    _customPlayer.invalidate();
    _customEffectId = null;
    _customPlaying = false;
  }

  /// Mirrors the router's exposed capabilities so the UI only renders controls
  /// that can actually be executed with the active profile.
  void _onRouterChanged() {
    final capabilities = _router.capabilities;
    if (setEquals(capabilities, _capabilities)) return;
    // The execution route changed: an in-flight effect request belongs to the
    // previous route and must not be applied.
    _effectEngine.invalidate();
    _customPlayer.invalidate();
    _customEffectId = null;
    _customPlaying = false;
    _capabilities = capabilities;
    add(CapabilitiesChanged());
  }

  Future<void> _onCapabilitiesChanged(
    CapabilitiesChanged event,
    Emitter<LightState> emit,
  ) async {
    AppLog.info(
      'LIGHT: capabilities → ${_capabilities.map((c) => c.name).join(',')}',
    );
    if (state is LightInitial) return;
    emit(_currentOnState());
  }

  @override
  Future<void> close() async {
    _router.removeListener(_onRouterChanged);
    _customPlayer
      ..onStopped = null
      ..stop();
    await _connectionSub?.cancel();
    await _stateUpdateSub?.cancel();
    await _profileStateSub?.cancel();
    return super.close();
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
    if (event is ChangeColor) {
      return 'rgb=${event.color.red},${event.color.green},${event.color.blue}';
    }
    if (event is ChangeBrightness) return 'brightness=${event.brightness}';
    if (event is SelectPreset) {
      return 'rgb=${event.red},${event.green},${event.blue}';
    }
    if (event is SavePreset) return 'id=${event.id} name="${event.name}"';
    if (event is DeletePreset) return 'id=${event.id}';
    return '';
  }

  void _onConnectionState(DeviceConnectionState state) {
    AppLog.debug('LIGHT: connection state: $state');
    final connected = state == DeviceConnectionState.connected;
    if (connected != _isConnected) {
      add(ConnectionChanged(connected));
    }
  }

  Future<void> _onConnectionChanged(
    ConnectionChanged event,
    Emitter<LightState> emit,
  ) async {
    _isConnected = event.isConnected;
    AppLog.info('LIGHT: isConnected → $_isConnected');
    if (!_isConnected) {
      // Nothing can be sent while disconnected; drop any in-flight effect work
      // so it cannot resurface as a stale "applied" state, and stop streaming.
      _effectEngine.invalidate();
      _customPlayer.invalidate();
      _customEffectId = null;
      _customPlaying = false;
      // Whatever was confirmed on the previous session says nothing about the
      // device's state after a reconnect.
      _hasConfirmedState = false;
    }
    final current = state;
    if (current is LightInitial) return;
    // Re-emit so controllers rebuild with the new connection flag.
    emit(_currentOnState());
  }

  Future<void> _onChangeColor(
    ChangeColor event,
    Emitter<LightState> emit,
  ) async {
    AppLog.info(
      'LIGHT event: ChangeColor rgb=(${event.color.red},'
      '${event.color.green},${event.color.blue})',
    );
    _stopCustomPlayback();

    try {
      await _router.send(
        DeviceCommand(
          type: 'color',
          parameters: {
            'red': event.color.red,
            'green': event.color.green,
            'blue': event.color.blue,
          },
        ),
      );
    } catch (e) {
      AppLog.error('LIGHT: failed to send color command', e);
      emit(LightError(e.toString()));
      return;
    }

    _currentColor = event.color;
    _isOn = true;
    _hasConfirmedState = true;
    emit(_currentOnState());
  }

  LightState _currentOnState() {
    if (_customEffectId != null) return _effectChangedState();
    if (_isOn) {
      return LightOn(
        color: _currentColor,
        brightness: _currentBrightness,
        presets: List.of(_presets),
        isConnected: _isConnected,
        effect: _currentEffect,
        speed: _currentSpeed,
        capabilities: _capabilities,
      );
    }
    return LightOff(
      brightness: _currentBrightness,
      presets: List.of(_presets),
      isConnected: _isConnected,
      effect: _currentEffect,
      speed: _currentSpeed,
      capabilities: _capabilities,
    );
  }

  /// Builds the [EffectChanged] state after a confirmed effect/speed write or a
  /// custom-effect playback change.
  LightState _effectChangedState() => EffectChanged(
    color: _currentColor,
    brightness: _currentBrightness,
    presets: List.of(_presets),
    isOn: _isOn,
    isConnected: _isConnected,
    effect: _currentEffect,
    speed: _currentSpeed,
    customEffectId: _customEffectId,
    customPlaying: _customPlaying,
    customSpeed: _customSpeed,
    customIntensity: _customIntensity,
    customPaletteId: _customPaletteId,
    capabilities: _capabilities,
  );

  /// Stops any active custom playback and clears its bookkeeping. Used when a
  /// manual control (colour/brightness/power/preset) takes over.
  void _stopCustomPlayback() {
    if (_customEffectId == null && !_customPlayer.isPlaying) return;
    _customPlayer.stop();
    _customEffectId = null;
    _customPlaying = false;
  }

  /// Selects a device-native effect through the shared effect engine, which
  /// resolves the definition's canonical protocol command and dispatches it via
  /// the same route as colour/power (verified custom profile executor or
  /// built-in MR Star encoder) — never a side channel.
  ///
  /// The selection is only recorded once the transport accepted the write; an
  /// unknown effect, an unsupported route, a rejection or a failure surfaces as
  /// [LightError] instead of pretending the effect was accepted. A stale result
  /// (device changed mid-flight) is dropped silently.
  Future<void> _onChangeEffect(
    ChangeEffect event,
    Emitter<LightState> emit,
  ) async {
    AppLog.info('LIGHT event: ChangeEffect name=${event.name}');
    final effect = effectByCommandName(event.name);
    if (effect == null) {
      AppLog.warn('LIGHT: unknown effect "${event.name}"');
      emit(const LightError('That effect is not available.'));
      return;
    }

    // Selecting a device pattern takes over from any custom playback.
    _stopCustomPlayback();

    final result = await _effectEngine.apply(effect);
    switch (result.outcome) {
      case EffectOutcome.sent:
        _currentEffect = effect.commandName;
        _isOn = true;
        _hasConfirmedState = true;
        emit(_effectChangedState());
      case EffectOutcome.stale:
        AppLog.info(
          'LIGHT: dropping stale effect result for ${effect.commandName}',
        );
      default:
        AppLog.error(
          'LIGHT: effect command rejected (${result.code}): ${result.message}',
        );
        emit(LightError(result.message ?? 'Could not send the effect.'));
    }
  }

  /// Sets the device-native effect speed through the shared effect engine,
  /// which validates the app-level range before dispatching.
  Future<void> _onChangeSpeed(
    ChangeSpeed event,
    Emitter<LightState> emit,
  ) async {
    AppLog.info('LIGHT event: ChangeSpeed value=${event.value}');
    _stopCustomPlayback();
    final result = await _effectEngine.setSpeed(event.value);
    switch (result.outcome) {
      case EffectOutcome.sent:
        _currentSpeed = event.value;
        _hasConfirmedState = true;
        emit(_effectChangedState());
      case EffectOutcome.stale:
        AppLog.info('LIGHT: dropping stale speed result');
      default:
        AppLog.error('LIGHT: failed to send speed command: ${result.code}');
        emit(LightError(result.message ?? 'Could not set the effect speed.'));
    }
  }

  /// Starts a StarLight custom effect through the shared player. The player
  /// validates the capability and parameters and streams bounded global colours
  /// through the router; the selection is only recorded once the first frame was
  /// accepted, never before.
  Future<void> _onPlayCustomEffect(
    PlayCustomEffect event,
    Emitter<LightState> emit,
  ) async {
    AppLog.info('LIGHT event: PlayCustomEffect id=${event.effectId}');
    final effect = effectById(event.effectId);
    if (effect == null) {
      emit(const LightError('That effect is not available.'));
      return;
    }

    final result = await _customPlayer.start(
      effect,
      speed: _customSpeed,
      intensity: _customIntensity,
      paletteId: _customPaletteId ?? effect.defaultPaletteId,
    );
    switch (result.outcome) {
      case EffectOutcome.sent:
        _customEffectId = effect.id;
        _customPlaying = true;
        _customPaletteId = _customPaletteId ?? effect.defaultPaletteId;
        // Streaming colours replaces any selected device pattern.
        _currentEffect = null;
        _isOn = true;
        _hasConfirmedState = true;
        emit(_effectChangedState());
      case EffectOutcome.stale:
        AppLog.info('LIGHT: dropping stale custom-effect result');
      default:
        AppLog.error(
          'LIGHT: custom effect rejected (${result.code}): ${result.message}',
        );
        emit(LightError(result.message ?? 'Could not play the effect.'));
    }
  }

  Future<void> _onStopCustomEffect(
    StopCustomEffect event,
    Emitter<LightState> emit,
  ) async {
    AppLog.info('LIGHT event: StopCustomEffect');
    _stopCustomPlayback();
    if (state is! LightInitial) emit(_currentOnState());
  }

  /// Stores the custom-effect rendering parameters and applies them live when a
  /// custom effect is active. Emits nothing unless playback is active, so
  /// browsing parameters does not churn the light state.
  Future<void> _onConfigureCustomEffect(
    ConfigureCustomEffect event,
    Emitter<LightState> emit,
  ) async {
    if (event.speed != null) _customSpeed = event.speed!;
    if (event.intensity != null) _customIntensity = event.intensity!;
    if (event.paletteId != null) _customPaletteId = event.paletteId;
    _customPlayer.updateParameters(
      speed: event.speed,
      intensity: event.intensity,
      paletteId: event.paletteId,
    );
    if (_customEffectId != null && state is! LightInitial) {
      emit(_effectChangedState());
    }
  }

  /// The player stopped on its own (a frame write failed or the link dropped).
  /// Reflect the stopped state and surface the real reason.
  Future<void> _onCustomEffectStopped(
    CustomEffectStopped event,
    Emitter<LightState> emit,
  ) async {
    AppLog.warn('LIGHT: custom playback stopped: ${event.result.code}');
    _customPlaying = false;
    _customEffectId = null;
    if (state is! LightInitial) {
      emit(LightError(event.result.message ?? 'Effect playback stopped.'));
    }
  }

  Future<void> _onTogglePower(
    TogglePower event,
    Emitter<LightState> emit,
  ) async {
    AppLog.info('LIGHT event: TogglePower on=${event.on}');
    _stopCustomPlayback();
    try {
      await _router.send(
        DeviceCommand(type: 'power', parameters: {'on': event.on}),
      );
    } catch (e) {
      AppLog.error('LIGHT: failed to send power command', e);
      emit(LightError(e.toString()));
      return;
    }
    _isOn = event.on;
    _hasConfirmedState = true;
    emit(_currentOnState());
  }

  Future<void> _onChangeBrightness(
    ChangeBrightness event,
    Emitter<LightState> emit,
  ) async {
    AppLog.info('LIGHT event: ChangeBrightness ${event.brightness}');
    _stopCustomPlayback();
    try {
      await _router.send(
        DeviceCommand(
          type: 'brightness',
          parameters: {'value': event.brightness},
        ),
      );
    } catch (e) {
      AppLog.error('LIGHT: failed to send brightness command', e);
      emit(LightError(e.toString()));
      return;
    }
    _currentBrightness = event.brightness;
    _hasConfirmedState = true;
    emit(_currentOnState());
  }

  Future<void> _onSelectPreset(
    SelectPreset event,
    Emitter<LightState> emit,
  ) async {
    AppLog.info(
      'LIGHT event: SelectPreset rgb=(${event.red},${event.green},${event.blue})',
    );
    _stopCustomPlayback();
    try {
      await _router.send(
        DeviceCommand(
          type: 'color',
          parameters: {
            'red': event.red,
            'green': event.green,
            'blue': event.blue,
          },
        ),
      );
    } catch (e) {
      AppLog.error('LIGHT: failed to send preset color command', e);
      emit(LightError(e.toString()));
      return;
    }
    _currentColor = RGBColor(event.red, event.green, event.blue);
    _isOn = true;
    _hasConfirmedState = true;
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
    emit(
      PresetsLoaded(
        color: _currentColor,
        brightness: _currentBrightness,
        presets: List.of(_presets),
        isOn: _isOn,
        isConnected: _isConnected,
        capabilities: _capabilities,
      ),
    );
  }

  Future<void> _onSavePreset(SavePreset event, Emitter<LightState> emit) async {
    AppLog.info(
      'LIGHT event: SavePreset id=${event.id} name="${event.name}" '
      'rgb=(${event.red},${event.green},${event.blue})',
    );
    try {
      await _savePreset(
        Preset(
          id: event.id,
          name: event.name,
          red: event.red,
          green: event.green,
          blue: event.blue,
        ),
      );
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

  Future<void> _onDeviceStateReceived(
    DeviceStateReceived event,
    Emitter<LightState> emit,
  ) async {
    AppLog.info('LIGHT: device state update type=${event.type}');
    switch (event.type) {
      case StateUpdateType.power:
        final value = event.value;
        if (value is bool) {
          _isOn = value;
        }
      case StateUpdateType.color:
        final value = event.value;
        if (value is Map) {
          final r = value['red'];
          final g = value['green'];
          final b = value['blue'];
          if (r is int && g is int && b is int) {
            _currentColor = RGBColor(r, g, b);
          }
        }
      case StateUpdateType.brightness:
        final value = event.value;
        if (value is int) {
          _currentBrightness = value;
        }
      case StateUpdateType.mic:
      case StateUpdateType.unknown:
        // No UI representation yet; ignore.
        return;
    }
    // A state notification is the device's own report: it confirms the
    // current values even when they match what we already believed.
    _hasConfirmedState = true;
    if (state is! LightInitial) {
      emit(_currentOnState());
    }
  }
}
