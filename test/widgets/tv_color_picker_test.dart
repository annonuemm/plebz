import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/i18n/strings.g.dart';
import 'package:plezy/utils/platform_detector.dart';
import 'package:plezy/widgets/tv_color_picker.dart';

void main() {
  setUp(() async {
    await TvDetectionService.getInstance(forceTv: true);
    TvDetectionService.setForceTVSync(true);
  });
  tearDown(() => TvDetectionService.setForceTVSync(false));

  testWidgets('passing over the colour code with the D-pad raises no keyboard', (tester) async {
    await tester.pumpWidget(
      TranslationProvider(
        child: MaterialApp(
          home: Scaffold(
            body: TvColorPicker(initialColor: const Color(0xFFA866EE), onColorChanged: (_) {}, onConfirm: () {}),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    bool readOnly() => tester.widget<TextField>(find.byType(TextField)).readOnly;
    final hex = tester.widget<TextField>(find.byType(TextField)).focusNode!;
    for (var i = 0; i < 6 && !hex.hasFocus; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
    }
    expect(hex.hasFocus, isTrue, reason: 'the D-pad reached the field');
    expect(readOnly(), isTrue, reason: 'focus alone must not open text input');
    expect(tester.testTextInput.log.map((call) => call.method), isNot(contains('TextInput.show')));
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));
}
