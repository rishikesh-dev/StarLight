import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starlight/domain/entities/rgb_color.dart';
import 'package:starlight/presentation/theme/app_theme.dart';
import 'package:starlight/presentation/widgets/color_picker_dialog.dart';

/// The picker only reports a colour when the user confirms it, so a dismissed
/// dialog never results in a device command.
void main() {
  Future<void> pumpLauncher(
    WidgetTester tester,
    void Function(RGBColor?) onResult,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  final result = await ColorPickerDialog.show(
                    context,
                    const RGBColor(0, 0, 0),
                  );
                  onResult(result);
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('applies an adjusted colour when confirmed', (tester) async {
    RGBColor? result;
    var completed = false;
    await pumpLauncher(tester, (value) {
      result = value;
      completed = true;
    });

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Custom colour'), findsOneWidget);
    expect(find.byType(Slider), findsNWidgets(3));

    await tester.drag(find.byType(Slider).first, const Offset(160, 0));
    await tester.pump();

    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();

    expect(completed, isTrue);
    expect(result, isNotNull);
    expect(result!.red, greaterThan(0));
  });

  testWidgets('returns null when cancelled', (tester) async {
    var completed = false;
    RGBColor? result;
    await pumpLauncher(tester, (value) {
      result = value;
      completed = true;
    });

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(completed, isTrue);
    expect(result, isNull);
  });
}
