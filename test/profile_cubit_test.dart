import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:starlight/data/datasources/profile_datasource.dart';
import 'package:starlight/data/models/device_profile_model.dart';
import 'package:starlight/data/repositories/device_profile_repository_impl.dart';
import 'package:starlight/data/repositories/profile_assignment_repository_impl.dart';
import 'package:starlight/domain/entities/device_capability.dart';
import 'package:starlight/domain/entities/device_profile.dart';
import 'package:starlight/domain/entities/profile_command.dart';
import 'package:starlight/domain/entities/profile_verification.dart';
import 'package:starlight/domain/repositories/ble_repository.dart';
import 'package:starlight/domain/repositories/device_profile_repository.dart';
import 'package:starlight/domain/repositories/profile_assignment_repository.dart';
import 'package:starlight/domain/services/command_router.dart';
import 'package:starlight/presentation/bloc/profile/profile_cubit.dart';

import 'support/fake_profile_executor.dart';

class MockBleRepository extends Mock implements BleRepository {}

class MockDeviceProfileRepository extends Mock
    implements DeviceProfileRepository {}

class MockProfileAssignmentRepository extends Mock
    implements ProfileAssignmentRepository {}

CommandTemplate _t(String source) => CommandTemplate.parse(source).template!;

DeviceProfile _validProfile({String id = 'p1', String name = 'Desk strip'}) {
  return DeviceProfile(
    id: id,
    name: name,
    serviceUuid: 'fff0',
    writeCharacteristicUuid: 'fff3',
    capabilities: const {DeviceCapability.power, DeviceCapability.brightness},
    commands: GattCommandSet(
      powerOn: _t('A1'),
      powerOff: _t('A0'),
      brightness: _t('B0 {brightness}'),
    ),
  );
}

const _verified = ProfileVerification(
  status: ProfileVerificationStatus.verified,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences prefs;
  late DeviceProfileRepositoryImpl repository;
  late ProfileAssignmentRepositoryImpl assignments;
  late FakeProfileExecutor executor;
  late CommandRouter router;
  late ProfileCubit cubit;

  setUpAll(() {
    registerFallbackValue(DeviceProfile.mrStar);
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    repository = DeviceProfileRepositoryImpl(ProfileDataSource(prefs));
    assignments = ProfileAssignmentRepositoryImpl(prefs);
    executor = FakeProfileExecutor();
    router = CommandRouter(MockBleRepository(), executor: executor);
    cubit = ProfileCubit(
      repository: repository,
      assignments: assignments,
      executor: executor,
      router: router,
      idGenerator: () => 'profile_fixed',
    );
    addTearDown(cubit.close);
    addTearDown(executor.dispose);
    addTearDown(router.dispose);
  });

  group('load', () {
    test('starts with only the built-in profile', () async {
      await cubit.load();
      expect(cubit.state.loading, isFalse);
      expect(cubit.state.profiles, [DeviceProfile.mrStar]);
      expect(cubit.state.customProfiles, isEmpty);
    });

    test('restores stored custom profiles after the built-in one', () async {
      SharedPreferences.setMockInitialValues({
        ProfileDataSource.profilesKey: jsonEncode([
          DeviceProfileModel.toJson(
            _validProfile(id: 'stored', name: 'Stored'),
          ),
        ]),
      });
      prefs = await SharedPreferences.getInstance();
      repository = DeviceProfileRepositoryImpl(ProfileDataSource(prefs));
      cubit = ProfileCubit(
        repository: repository,
        assignments: ProfileAssignmentRepositoryImpl(prefs),
        executor: executor,
        router: router,
      );

      await cubit.load();
      expect(cubit.state.profiles.first.id, kMrStarProfileId);
      expect(cubit.state.customProfiles.single.name, 'Stored');
    });

    test('skips a malformed stored entry without losing the rest', () async {
      SharedPreferences.setMockInitialValues({
        ProfileDataSource.profilesKey: jsonEncode([
          {'schema': 999, 'id': 'broken'},
          {'not': 'a profile'},
          DeviceProfileModel.toJson(_validProfile(id: 'good', name: 'Good')),
        ]),
      });
      prefs = await SharedPreferences.getInstance();
      repository = DeviceProfileRepositoryImpl(ProfileDataSource(prefs));
      cubit = ProfileCubit(
        repository: repository,
        assignments: ProfileAssignmentRepositoryImpl(prefs),
        executor: executor,
        router: router,
      );

      await cubit.load();
      expect(cubit.state.customProfiles.map((p) => p.id), ['good']);
    });

    test('drops an assignment that points at a missing profile', () async {
      SharedPreferences.setMockInitialValues({
        ProfileAssignmentRepositoryImpl.assignmentsKey: jsonEncode({
          'dev1': 'ghost',
        }),
      });
      prefs = await SharedPreferences.getInstance();
      cubit = ProfileCubit(
        repository: DeviceProfileRepositoryImpl(ProfileDataSource(prefs)),
        assignments: ProfileAssignmentRepositoryImpl(prefs),
        executor: executor,
        router: router,
      );

      await cubit.load();
      expect(cubit.state.assignments, isEmpty);
    });

    test('keeps an assignment that points at a known profile', () async {
      SharedPreferences.setMockInitialValues({
        ProfileDataSource.profilesKey: jsonEncode([
          DeviceProfileModel.toJson(_validProfile(id: 'p1')),
        ]),
        ProfileAssignmentRepositoryImpl.assignmentsKey: jsonEncode({
          'dev1': 'p1',
        }),
      });
      prefs = await SharedPreferences.getInstance();
      cubit = ProfileCubit(
        repository: DeviceProfileRepositoryImpl(ProfileDataSource(prefs)),
        assignments: ProfileAssignmentRepositoryImpl(prefs),
        executor: executor,
        router: router,
      );

      await cubit.load();
      expect(cubit.state.assignments, {'dev1': 'p1'});
    });
  });

  group('saveProfile', () {
    test('persists a valid profile', () async {
      await cubit.load();
      final result = await cubit.saveProfile(_validProfile(name: 'Desk'));

      expect(result.isSaved, isTrue);
      expect(cubit.state.customProfiles.map((p) => p.name), ['Desk']);
    });

    test('refuses an invalid profile with field errors', () async {
      await cubit.load();
      final result = await cubit.saveProfile(_validProfile(name: '  '));

      expect(result.isSaved, isFalse);
      expect(result.fieldErrors['name'], isNotNull);
      expect(cubit.state.customProfiles, isEmpty);
      expect((await repository.loadProfiles()).length, 1);
    });

    test('assigns a generated id to a new profile', () async {
      await cubit.load();
      await cubit.saveProfile(_validProfile(id: '', name: 'New'));
      expect(cubit.state.customProfiles.single.id, 'profile_fixed');
    });

    test('marks the profile as non-built-in before persisting', () async {
      await cubit.load();
      await cubit.saveProfile(
        _validProfile(id: 'p1', name: 'X').copyWith(isBuiltIn: false),
      );
      final stored = await repository.loadProfiles();
      expect(stored.where((p) => p.isBuiltIn), hasLength(1));
    });

    test('reports a storage failure without a field error', () async {
      final mockRepository = MockDeviceProfileRepository();
      when(() => mockRepository.saveProfile(any()))
          .thenThrow(Exception('disk full'));
      final brokenCubit = ProfileCubit(
        repository: mockRepository,
        assignments: MockProfileAssignmentRepository(),
        executor: executor,
        router: router,
      );
      addTearDown(brokenCubit.close);

      final result = await brokenCubit.saveProfile(_validProfile());
      expect(result.isSaved, isFalse);
      expect(result.error, isNotNull);
      expect(result.fieldErrors, isEmpty);
    });
  });

  group('repository', () {
    test('never persists or deletes the built-in profile', () async {
      await repository.saveProfile(DeviceProfile.mrStar);
      expect((await repository.loadProfiles()).length, 1);

      await repository.deleteProfile(kMrStarProfileId);
      expect((await repository.loadProfiles()).length, 1);
    });

    test('replaces an existing profile by id', () async {
      await repository.saveProfile(_validProfile(id: 'p1', name: 'First'));
      await repository.saveProfile(_validProfile(id: 'p1', name: 'Second'));

      final stored = await repository.loadProfiles();
      expect(stored.where((p) => !p.isBuiltIn).length, 1);
      expect(stored.last.name, 'Second');
    });
  });

  group('assignment', () {
    test('assigning the built-in profile clears the assignment', () async {
      await cubit.load();
      await cubit.saveProfile(_validProfile(id: 'p1'));
      await cubit.assignProfile('dev1', 'p1');
      expect(cubit.state.assignments, {'dev1': 'p1'});

      await cubit.assignProfile('dev1', kMrStarProfileId);
      expect(cubit.state.assignments, isEmpty);
      expect(await assignments.assignedProfileId('dev1'), isNull);
    });
  });

  group('routing', () {
    test('an assigned-but-unverified profile exposes no controls', () async {
      executor.verification = const ProfileVerification.notConnected();
      await cubit.load();
      await cubit.saveProfile(_validProfile(id: 'p1'));
      await cubit.assignProfile('dev1', 'p1');
      await cubit.onActiveDeviceChanged('dev1');

      expect(router.activeProfile, isNull);
      expect(router.capabilities, isEmpty);
      expect(
        cubit.state.verificationFor('p1').status,
        ProfileVerificationStatus.notConnected,
      );
    });

    test('a verified assigned profile drives the router', () async {
      executor.verification = _verified;
      await cubit.load();
      final profile = _validProfile(id: 'p1');
      await cubit.saveProfile(profile);
      await cubit.assignProfile('dev1', 'p1');
      await cubit.onActiveDeviceChanged('dev1');

      expect(router.activeProfile?.id, 'p1');
      expect(router.capabilities, profile.capabilities);
    });

    test(
      'verifying on demand switches from no controls to the profile',
      () async {
        executor.verification = const ProfileVerification.notConnected();
        await cubit.load();
        await cubit.saveProfile(_validProfile(id: 'p1'));
        await cubit.assignProfile('dev1', 'p1');
        await cubit.onActiveDeviceChanged('dev1');
        expect(router.capabilities, isEmpty);

        executor.verification = _verified;
        await cubit.verifyProfile('p1');

        expect(router.activeProfile?.id, 'p1');
        expect(router.capabilities, isNotEmpty);
      },
    );

    test(
      'disconnecting clears verification and returns to the built-in path',
      () async {
        executor.verification = _verified;
        await cubit.load();
        await cubit.saveProfile(_validProfile(id: 'p1'));
        await cubit.assignProfile('dev1', 'p1');
        await cubit.onActiveDeviceChanged('dev1');
        expect(router.activeProfile, isNotNull);

        await cubit.onActiveDeviceChanged(null);
        expect(cubit.state.verifications, isEmpty);
        expect(router.activeProfile, isNull);
        expect(router.capabilities, isNotEmpty);
      },
    );
  });

  group('delete', () {
    test('detaches the profile from its device before deleting', () async {
      executor.verification = _verified;
      await cubit.load();
      await cubit.saveProfile(_validProfile(id: 'p1'));
      await cubit.assignProfile('dev1', 'p1');
      await cubit.onActiveDeviceChanged('dev1');
      expect(router.activeProfile?.id, 'p1');

      await cubit.deleteProfile('p1');

      expect(cubit.state.customProfiles, isEmpty);
      expect(cubit.state.assignments.containsKey('dev1'), isFalse);
      expect(await assignments.assignedProfileId('dev1'), isNull);
      expect(router.activeProfile, isNull);
    });
  });

  group('duplicate', () {
    test('creates a copy with a fresh id and a suffix', () async {
      await cubit.load();
      await cubit.saveProfile(_validProfile(id: 'p1', name: 'Desk'));
      final result = await cubit.duplicateProfile('p1');

      expect(result.isSaved, isTrue);
      final names = cubit.state.customProfiles.map((p) => p.name).toList();
      expect(names, containsAll(['Desk', 'Desk (copy)']));
    });
  });

  group('validation helper', () {
    test('verifyProfile reports a missing profile', () async {
      await cubit.load();
      final result = await cubit.verifyProfile('nope');
      expect(result.status, ProfileVerificationStatus.failed);
    });
  });
}
