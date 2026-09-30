import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/i18n/strings.g.dart';
import 'package:plezy/utils/dialogs.dart';

/// The dialog exists for a remote: on TV a description is clamped to the room
/// beside the logo, and there is no other way to read the rest.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final longText = List.generate(60, (i) => 'Zeile $i des Beschreibungstextes.').join(' ');

  Future<void> openDialog(WidgetTester tester, {required String text}) async {
    await tester.pumpWidget(
      TranslationProvider(
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showFullTextDialog(context, title: 'Übersicht', text: text),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  double scrollOffset(WidgetTester tester) =>
      tester.widget<SingleChildScrollView>(find.byType(SingleChildScrollView)).controller!.offset;

  testWidgets('shows the whole text and a way out', (tester) async {
    await openDialog(tester, text: 'Kurz und vollständig.');

    expect(find.text('Übersicht'), findsOneWidget);
    expect(find.text('Kurz und vollständig.'), findsOneWidget);
    expect(find.text(t.common.close), findsOneWidget);
  });

  testWidgets('down scrolls the text rather than moving focus off it', (tester) async {
    await openDialog(tester, text: longText);
    expect(scrollOffset(tester), 0);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();

    expect(scrollOffset(tester), greaterThan(0));
  });

  testWidgets('at the bottom the key is handed on, so the close button is reachable', (tester) async {
    await openDialog(tester, text: longText);
    final focusedInText = FocusManager.instance.primaryFocus;

    // Walk past the end of the travel.
    for (var i = 0; i < 40; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
    }

    expect(
      FocusManager.instance.primaryFocus,
      isNot(focusedInText),
      reason: 'the dialog must hand the key on once there is nothing left to scroll',
    );
    expect(find.text(t.common.close), findsOneWidget);
  });

  testWidgets('a text that fits does not swallow the key', (tester) async {
    await openDialog(tester, text: 'Passt in eine Zeile.');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();

    expect(scrollOffset(tester), 0);
  });
}
