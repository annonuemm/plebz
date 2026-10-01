import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/i18n/strings.g.dart';
import 'package:plezy/utils/dialogs.dart';
import 'package:plezy/widgets/dialog_action_button.dart';

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

  group('a question — the update dialog', () {
    Future<void> openConfirm(WidgetTester tester, {required String text}) async {
      await tester.pumpWidget(
        TranslationProvider(
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => showFullTextConfirmDialog(
                    context,
                    title: 'Update verfügbar',
                    span: TextSpan(text: text),
                    confirmText: 'Jetzt aktualisieren',
                    cancelText: 'Später',
                  ),
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

    bool confirmHasFocus(WidgetTester tester) {
      final focused = FocusManager.instance.primaryFocus?.context;
      if (focused == null) return false;
      final button =
          focused.findAncestorWidgetOfExactType<DialogActionButton>() ??
          (focused.widget is DialogActionButton ? focused.widget as DialogActionButton : null);
      return button?.label == 'Jetzt aktualisieren';
    }

    testWidgets('opens on the confirm button, so OK answers it at once', (tester) async {
      await openConfirm(tester, text: 'Plebz 1.4.2 ist bereit zur Installation.');

      expect(confirmHasFocus(tester), isTrue);
    });

    testWidgets('up still reaches a long text and scrolls it', (tester) async {
      await openConfirm(tester, text: longText);
      expect(confirmHasFocus(tester), isTrue);

      for (var i = 0; i < 3; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
        await tester.pumpAndSettle();
      }
      expect(confirmHasFocus(tester), isFalse, reason: 'the cursor went up into the text');

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(scrollOffset(tester), greaterThan(0));
    });
  });
}
