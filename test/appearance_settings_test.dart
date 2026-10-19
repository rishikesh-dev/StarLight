import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:starlight/data/datasources/theme_preferences.dart';
import 'package:starlight/presentation/bloc/theme/theme_cubit.dart';
import 'package:starlight/presentation/bloc/theme/theme_state.dart';
import 'package:starlight/presentation/pages/settings/appearance_settings.dart';
import 'package:starlight/presentation/theme/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ThemeData appTheme(WidgetTester tester) =>
      tester.widget<MaterialApp>(find.byType(MaterialApp)).theme!;

  Finder accentSwatch(Color color) => find.byWidgetPredicate(
    (w) =>
        w is Container &&
        w.decoration is BoxDecoration &&
        (w.decoration as BoxDecoration).color == color,
  );

  testWidgets('lists every built-in theme and the accent controls', (
    tester,
  ) async {
    await pumpApp(tester, await cubitWith({}));

    for (final option in kAppThemes) {
      expect(find.text(option.name), findsOneWidget, reason: option.id);
    }
    expect(find.text('Accent colour'), findsOneWidget);
    expect(find.text('Reset to default'), findsOneWidget);
    expect(find.byType(FilledButton), findsWidgets);
    expect(find.byType(Slider), findsWidgets);
  });

  testWidgets('selecting a theme applies it immediately', (tester) async {
    final cubit = await cubitWith({});
    await pumpApp(tester, cubit);
    expect(appTheme(tester).extension<AppTokens>(), AppTokens.graphite);

    await tester.tap(find.text('Forest'));
    await tester.pumpAndSettle();

    expect(cubit.state.theme.id, 'forest');
    expect(appTheme(tester).extension<AppTokens>(), AppTokens.forest);
  });

  testWidgets('selecting a theme resets a custom accent', (tester) async {
    final cubit = await cubitWith({});
    await pumpApp(tester, cubit);

    await tester.tap(accentSwatch(const Color(0xFF26A69A)));
    await tester.pumpAndSettle();
    expect(cubit.state.customAccent, const Color(0xFF26A69A));
    expect(appTheme(tester).colorScheme.primary, const Color(0xFF26A69A));

    await tester.tap(find.text('Graphite + Purple'));
    await tester.pumpAndSettle();
    expect(cubit.state.hasCustomAccent, isFalse);
    expect(appTheme(tester).colorScheme.primary, AppTokens.graphite.primary);
  });

  testWidgets('a preset accent applies immediately', (tester) async {
    final cubit = await cubitWith({});
    await pumpApp(tester, cubit);

    await tester.tap(accentSwatch(const Color(0xFFFF7043)));
    await tester.pumpAndSettle();

    expect(cubit.state.customAccent, const Color(0xFFFF7043));
    expect(appTheme(tester).colorScheme.primary, const Color(0xFFFF7043));
  });

  testWidgets('the custom accent dialog applies a colour', (tester) async {
    final cubit = await cubitWith({});
    await pumpApp(tester, cubit);

    await tester.tap(find.text('Custom'));
    await tester.pumpAndSettle();
    expect(find.text('Custom accent'), findsOneWidget);

    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();

    expect(cubit.state.hasCustomAccent, isTrue);
  });

  testWidgets('Reset to default returns to Graphite with no accent', (
    tester,
  ) async {
    final cubit = await cubitWith({
      ThemePreferences.themeIdKey: 'amber',
      ThemePreferences.accentKey: 0xFF123456,
    });
    await pumpApp(tester, cubit);
    expect(cubit.state.theme.id, 'amber');

    await tester.tap(find.text('Reset to default'));
    await tester.pumpAndSettle();

    expect(cubit.state.theme.id, 'graphite');
    expect(cubit.state.hasCustomAccent, isFalse);
    expect(appTheme(tester).extension<AppTokens>(), AppTokens.graphite);
  });

  testWidgets('stays overflow-free on a narrow screen with large text', (
    tester,
  ) async {
    final cubit = await cubitWith({ThemePreferences.themeIdKey: 'light'});
    await pumpApp(
      tester,
      cubit,
      width: 320,
      textScaler: const TextScaler.linear(2.0),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Accent colour'), findsOneWidget);
    expect(find.byType(FilledButton), findsWidgets);
  });
}

/// Creates a [ThemeCubit] seeded from persisted [values].
Future<ThemeCubit> cubitWith(Map<String, Object> values) async {
  SharedPreferences.setMockInitialValues(values);
  final prefs = await SharedPreferences.getInstance();
  return ThemeCubit(ThemePreferences(prefs));
}

/// Pumps the appearance section inside a theme-reactive app. The viewport is
/// generous by default so every control can be tapped without scrolling.
Future<void> pumpApp(
  WidgetTester tester,
  ThemeCubit cubit, {
  double width = 500,
  TextScaler textScaler = TextScaler.noScaling,
}) async {
  tester.view.physicalSize = Size(width, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    BlocProvider<ThemeCubit>.value(
      value: cubit,
      child: BlocBuilder<ThemeCubit, ThemeState>(
        builder: (context, state) {
          return MaterialApp(
            theme: buildAppTheme(
              option: state.theme,
              accentOverride: state.customAccent,
            ),
            home: Builder(
              builder: (context) {
                final media = MediaQuery.of(context);
                return MediaQuery(
                  data: media.copyWith(textScaler: textScaler),
                  child: const Scaffold(
                    body: SingleChildScrollView(
                      padding: EdgeInsets.all(16),
                      child: AppearanceSettings(),
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    ),
  );
  await tester.pumpAndSettle();
}
