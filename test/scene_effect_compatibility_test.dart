import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:starlight/core/ble/protocol_encoder.dart';
import 'package:starlight/data/datasources/scene_datasource.dart';
import 'package:starlight/data/models/scene_model.dart';
import 'package:starlight/domain/entities/connection_state.dart';
import 'package:starlight/domain/entities/device.dart';
import 'package:starlight/domain/entities/device_capability.dart';
import 'package:starlight/domain/entities/device_state.dart';
import 'package:starlight/domain/entities/device_type.dart';
import 'package:starlight/domain/entities/effect.dart';
import 'package:starlight/domain/entities/execution_result.dart';
import 'package:starlight/domain/entities/light_command.dart';
import 'package:starlight/domain/entities/scene.dart';
import 'package:starlight/domain/repositories/ble_repository.dart';
import 'package:starlight/domain/services/command_router.dart';
import 'package:starlight/domain/services/device_command_dispatcher.dart';

class MockBleRepository extends Mock implements BleRepository {}

bool _sameBytes(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < b.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// The command names StarLight shipped before the effect catalogue was
/// rebuilt from the decompiled MR Star APK, and the controller mode id each
/// of them selected on the wire.
///
/// This is the recorded truth of the old catalogue (see the pre-rebuild
/// `lib/domain/entities/effect.dart` in git history) — not a guess: a legacy
/// name identifies the *mode it selected*, and that mode still exists, it
/// just has a different, honest label now.
const Map<String, int> _legacyCommandModeIds = <String, int>{
  'Solid': 0,
  'Fireworks': 1,
  'Rainbow': 2,
  'Breath': 3,
  'Scan': 4,
  'Flash': 5,
  'Police': 6,
  'Chase': 7,
  'Comet': 8,
  'Lava': 9,
  'Ocean': 10,
};

Device _device() => const Device(
  id: 'dev-1',
  name: 'Strip',
  type: DeviceType.other,
  transport: 'ble',
  address: 'aa:bb',
  capabilities: [DeviceCapability.effect],
  connectionState: DeviceConnectionState.connected,
  state: LightState(isOn: true, isConnected: true),
);

/// A scene exactly as the pre-rebuild app would have written it: an `effect`
/// action whose value is the old command name.
String _legacySceneJson(String commandName) => jsonEncode([
  {
    'id': 'scene-1',
    'name': 'Legacy scene',
    'iconName': 'bolt',
    'actions': [
      {
        'deviceId': 'dev-1',
        'groupId': null,
        'action': 'effect',
        'value': commandName,
      },
    ],
  },
]);

void main() {
  setUpAll(() {
    registerFallbackValue(const LightCommand(type: 'fallback', bytes: []));
  });

  group('legacy command names resolve to the mode they used to select', () {
    test('every legacy name maps to its recorded mode id', () {
      for (final entry in _legacyCommandModeIds.entries) {
        final effect = effectByCommandName(entry.key);
        expect(effect, isNotNull, reason: entry.key);
        expect(
          effect!.protocolModeId,
          entry.value,
          reason: '${entry.key} must still select mode ${entry.value}',
        );
      }
    });

    test('the legacy table covers exactly the pre-rebuild catalogue', () {
      // 'Solid' is still a canonical command name (mode 0) and therefore
      // resolves through the normal path; the other ten are the names the
      // rebuild dropped.
      expect(kLegacyEffectCommandModeIds.length, 10);
      expect(
        kLegacyEffectCommandModeIds.keys.toSet(),
        _legacyCommandModeIds.keys.map((name) => name.toLowerCase()).toSet()
          ..remove('solid'),
      );
      for (final modeId in kLegacyEffectCommandModeIds.values) {
        expect(effectByModeId(modeId), isNotNull, reason: 'mode $modeId');
      }
    });

    test('a legacy name resolves to the same wire bytes as before', () {
      for (final entry in _legacyCommandModeIds.entries) {
        final encoded = ProtocolEncoder.setMode(entry.value);
        expect(encoded[3], 0x00, reason: entry.key);
        expect(encoded[4], entry.value, reason: entry.key);
      }
    });

    test('legacy lookup is case-insensitive', () {
      expect(effectByCommandName('rainbow')?.protocolModeId, 2);
      expect(effectByCommandName('RAINBOW')?.protocolModeId, 2);
    });

    test('no legacy name shadows a canonical command name', () {
      final canonical = kMrStarEffects
          .map((e) => e.commandName)
          .toSet()
          .map((e) => e!.toLowerCase());
      for (final name in kLegacyEffectCommandModeIds.keys) {
        expect(
          canonical,
          isNot(contains(name)),
          reason: '$name would be ambiguous',
        );
      }
    });

    test('an unknown name still resolves to null (no guessing)', () {
      expect(effectByCommandName('Does not exist'), isNull);
      expect(effectByCommandName('cmode999'), isNull);
      expect(effectByLegacyCommandName('Does not exist'), isNull);
      expect(effectByLegacyCommandName(null), isNull);
    });

    test('canonical command names still resolve to themselves', () {
      for (final effect in kMrStarEffects) {
        expect(effectByCommandName(effect.commandName)?.id, effect.id);
      }
    });
  });

  group('legacy saved scene data still loads and executes', () {
    late MockBleRepository bleRepository;

    setUp(() {
      bleRepository = MockBleRepository();
      when(() => bleRepository.sendCommand(any())).thenAnswer((_) async {});
    });

    test('a stored legacy value survives the persistence round trip', () async {
      SharedPreferences.setMockInitialValues({
        SceneDataSource.scenesKey: _legacySceneJson('Rainbow'),
      });
      final prefs = await SharedPreferences.getInstance();
      final datasource = SceneDataSource(prefs);

      final scenes = await datasource.loadScenes();
      expect(scenes, hasLength(1));
      final action = scenes.single.actions.single;
      expect(action.action, 'effect');
      expect(
        action.value,
        'Rainbow',
        reason: 'the stored value must not be rewritten on load',
      );
    });

    test(
      'a stored legacy value executes as the mode it always selected',
      () async {
        SharedPreferences.setMockInitialValues({
          SceneDataSource.scenesKey: _legacySceneJson('Rainbow'),
        });
        final prefs = await SharedPreferences.getInstance();
        final datasource = SceneDataSource(prefs);
        final scene = (await datasource.loadScenes()).single;

        final router = CommandRouter(bleRepository);
        final dispatcher = DeviceCommandDispatcher(router);

        final result = await dispatcher.apply(
          device: _device(),
          action: scene.actions.single.action,
          value: scene.actions.single.value,
        );

        expect(result.outcome, ExecutionOutcome.success);
        final command =
            verify(() => bleRepository.sendCommand(captureAny()))
                    .captured
                    .single
                as LightCommand;
        expect(
          _sameBytes(command.bytes, ProtocolEncoder.setMode(2)),
          isTrue,
          reason: 'legacy "Rainbow" selected mode 2 and must still do so',
        );
      },
    );

    test('every legacy name executes as its recorded mode', () async {
      final router = CommandRouter(bleRepository);
      final dispatcher = DeviceCommandDispatcher(router);

      for (final entry in _legacyCommandModeIds.entries) {
        clearInteractions(bleRepository);
        final result = await dispatcher.apply(
          device: _device(),
          action: 'effect',
          value: entry.key,
        );
        expect(result.outcome, ExecutionOutcome.success, reason: entry.key);
        final command =
            verify(() => bleRepository.sendCommand(captureAny()))
                    .captured
                    .single
                as LightCommand;
        expect(
          _sameBytes(command.bytes, ProtocolEncoder.setMode(entry.value)),
          isTrue,
          reason: entry.key,
        );
      }
    });

    test('a canonical stored value executes as its own mode', () async {
      final router = CommandRouter(bleRepository);
      final dispatcher = DeviceCommandDispatcher(router);

      final result = await dispatcher.apply(
        device: _device(),
        action: 'effect',
        value: 'cmode65',
      );

      expect(result.outcome, ExecutionOutcome.success);
      final command =
          verify(() => bleRepository.sendCommand(captureAny())).captured.single
              as LightCommand;
      expect(_sameBytes(command.bytes, ProtocolEncoder.setMode(65)), isTrue);
    });

    test(
      'an unknown stored value is preserved and refused, not substituted',
      () async {
        final router = CommandRouter(bleRepository);
        final dispatcher = DeviceCommandDispatcher(router);

        final result = await dispatcher.apply(
          device: _device(),
          action: 'effect',
          value: 'Totally unknown effect',
        );

        expect(result.outcome, ExecutionOutcome.unsupported);
        verifyNever(() => bleRepository.sendCommand(any()));
        // The value is kept verbatim so nothing is silently lost.
        expect(
          resolveEffectCommandName('Totally unknown effect'),
          'Totally unknown effect',
        );
      },
    );
  });

  group('persisting an effect value', () {
    test('a legacy value is migrated to the canonical command name', () {
      expect(resolveEffectCommandName('Rainbow'), 'cmode2');
      expect(resolveEffectCommandName('Chase'), 'cmode7');
      expect(resolveEffectCommandName('Solid'), 'Solid');
    });

    test('a canonical value is kept as it is', () {
      expect(resolveEffectCommandName('cmode65'), 'cmode65');
      expect(resolveEffectCommandName('Solid'), 'Solid');
    });

    test('an unknown value is preserved verbatim', () {
      expect(
        resolveEffectCommandName('Totally unknown effect'),
        'Totally unknown effect',
      );
    });

    test('an empty value stays empty', () {
      expect(resolveEffectCommandName(null), isNull);
      expect(resolveEffectCommandName(''), isNull);
    });

    test(
      'a migrated value round-trips through the scene model unchanged',
      () async {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final datasource = SceneDataSource(prefs);

        final model = SceneModel.fromEntity(
          Scene(
            id: 'scene-2',
            name: 'Migrated',
            iconName: 'bolt',
            actions: const [
              SceneAction(deviceId: 'dev-1', action: 'effect', value: 'cmode2'),
            ],
          ),
        );
        await datasource.saveScene(model);

        final loaded = (await datasource.loadScenes()).single;
        expect(loaded.actions.single.value, 'cmode2');
      },
    );
  });
}
