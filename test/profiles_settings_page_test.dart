import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:starlight/domain/entities/device_capability.dart';
import 'package:starlight/domain/entities/device_profile.dart';
import 'package:starlight/domain/entities/profile_command.dart';
import 'package:starlight/domain/repositories/ble_repository.dart';
import 'package:starlight/domain/repositories/device_profile_repository.dart';
import 'package:starlight/domain/repositories/profile_assignment_repository.dart';
import 'package:starlight/domain/services/command_router.dart';
import 'package:starlight/presentation/bloc/profile/profile_cubit.dart';
import 'package:starlight/presentation/pages/settings/profile_editor_page.dart';
import 'package:starlight/presentation/pages/settings/profiles_settings_page.dart';
import 'package:starlight/presentation/theme/app_theme.dart';

import 'support/fake_profile_executor.dart';

class MockBleRepository extends Mock implements BleRepository {}

class MockDeviceProfileRepository extends Mock
    implements DeviceProfileRepository {}

class MockProfileAssignmentRepository extends Mock
    implements ProfileAssignmentRepository {}

CommandTemplate _t(String source) => CommandTemplate.parse(source).template!;

DeviceProfile _custom() => DeviceProfile(
  id: 'p1',
  name: 'Desk strip',
  serviceUuid: 'fff0',
  writeCharacteristicUuid: 'fff3',
  capabilities: const {DeviceCapability.power},
  commands: GattCommandSet(powerOn: _t('A1'), powerOff: _t('A0')),
);

/// Profile list + editor coverage: the built-in profile is read-only, custom
/// profiles can be created/deleted, and the editor refuses an unusable profile.
void main() {
  late MockDeviceProfileRepository profileRepository;
  late MockProfileAssignmentRepository assignmentRepository;
  late FakeProfileExecutor executor;
  late ProfileCubit cubit;

  setUpAll(() {
    registerFallbackValue(DeviceProfile.mrStar);
  });

  setUp(() {
    profileRepository = MockDeviceProfileRepository();
    assignmentRepository = MockProfileAssignmentRepository();
    executor = FakeProfileExecutor();
    final router = CommandRouter(MockBleRepository(), executor: executor);
    cubit = ProfileCubit(
      repository: profileRepository,
      assignments: assignmentRepository,
      executor: executor,
      router: router,
    );
    addTearDown(cubit.close);
    addTearDown(executor.dispose);
    addTearDown(router.dispose);

    when(() => profileRepository.loadProfiles())
        .thenAnswer((_) async => [DeviceProfile.mrStar, _custom()]);
    when(() => profileRepository.saveProfile(any())).thenAnswer((_) async {});
    when(() => profileRepository.deleteProfile(any())).thenAnswer((_) async {});
    when(() => assignmentRepository.loadAssignments())
        .thenAnswer((_) async => <String, String>{});
    when(() => assignmentRepository.assign(any(), any()))
        .thenAnswer((_) async {});
    when(() => assignmentRepository.unassign(any())).thenAnswer((_) async {});
  });

  Future<void> pumpList(WidgetTester tester) async {
    tester.view.physicalSize = const Size(500, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await cubit.load();
    await tester.pumpWidget(
      BlocProvider<ProfileCubit>.value(
        value: cubit,
        child: MaterialApp(
          theme: buildAppTheme(),
          home: const ProfilesSettingsPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openEditor(WidgetTester tester) async {
    await pumpList(tester);
    await tester.tap(find.text('New profile'));
    await tester.pumpAndSettle();
  }

  /// Fills a valid single-capability (power) profile into the open editor.
  Future<void> fillPowerProfile(WidgetTester tester, String name) async {
    await tester.enterText(
      find.widgetWithText(TextField, 'Profile name'),
      name,
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Service UUID'),
      'fff0',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Write characteristic UUID'),
      'fff3',
    );
    await tester.tap(find.text('Power'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Power ON command'),
      'A1',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Power OFF command'),
      'A0',
    );
  }

  testWidgets('lists the built-in profile and the custom profiles', (
    tester,
  ) async {
    await pumpList(tester);

    expect(find.text(DeviceProfile.mrStar.name), findsOneWidget);
    expect(find.text('Built-in'), findsOneWidget);
    expect(find.text('Desk strip'), findsOneWidget);
    // Only the custom profile can be edited or deleted.
    expect(find.text('Edit'), findsOneWidget);
    expect(find.byTooltip('Delete'), findsOneWidget);
  });

  testWidgets('opens the editor for a new profile', (tester) async {
    await openEditor(tester);

    expect(find.byType(ProfileEditorPage), findsOneWidget);
    expect(find.text('Profile name'), findsOneWidget);
    expect(find.text('Service UUID'), findsOneWidget);
  });

  testWidgets('deletes a custom profile after confirmation', (tester) async {
    await pumpList(tester);

    await tester.tap(find.byTooltip('Delete'));
    await tester.pumpAndSettle();
    expect(find.text('Delete profile?'), findsOneWidget);

    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    verify(() => profileRepository.deleteProfile('p1')).called(1);
  });

  testWidgets('refuses to save an unusable profile', (tester) async {
    await openEditor(tester);

    await tester.tap(find.text('Save profile'));
    await tester.pumpAndSettle();

    expect(find.text('Name is required.'), findsOneWidget);
    expect(find.text('Select at least one capability.'), findsOneWidget);
    // The editor stays open and nothing unusable is persisted.
    expect(find.byType(ProfileEditorPage), findsOneWidget);
    verifyNever(() => profileRepository.saveProfile(any()));
  });

  testWidgets('saves a valid power profile', (tester) async {
    await openEditor(tester);
    await fillPowerProfile(tester, 'Desk v2');

    await tester.tap(find.text('Save profile'));
    await tester.pumpAndSettle();

    verify(
      () => profileRepository.saveProfile(
        any(
          that: isA<DeviceProfile>()
              .having((p) => p.name, 'name', 'Desk v2')
              .having((p) => p.capabilities, 'capabilities', {
                DeviceCapability.power,
              })
              .having((p) => p.serviceUuid, 'service', 'fff0'),
        ),
      ),
    ).called(1);
    // A successful save closes the editor.
    expect(find.byType(ProfileEditorPage), findsNothing);
  });
}
