import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/i18n/strings.g.dart';
import 'package:plezy/screens/settings/settings_utils.dart';
import 'package:plezy/services/settings_service.dart' show AppThemeVariant;
import 'package:plezy/theme/mono_theme.dart';
import 'package:plezy/widgets/app_menu.dart';
import 'package:plezy/utils/platform_detector.dart';
import 'package:plezy/widgets/dialog_action_button.dart';

void main() {
  group('showSelectionDialog', _selectionTests);

  tearDown(() {
    TvDetectionService.debugSetAppleTVOverride(null);
  });

  testWidgets('settings text input survives TV keyboard back dismissal', (tester) async {
    TvDetectionService.debugSetAppleTVOverride(true);
    await tester.binding.setSurfaceSize(const Size(1280, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    late BuildContext hostContext;
    final saved = <String>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              hostContext = context;
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );

    showRegexInputDialog(
      context: hostContext,
      title: 'Regex',
      currentValue: 'abc',
      defaultValue: '.*',
      onSave: (value) async => saved.add(value),
    );
    await tester.pumpAndSettle();
    final fieldFinder = find.byType(TextField);

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.byKey(const Key('tv_virtual_keyboard_dialog')), findsNothing);
    expect(tester.widget<TextField>(fieldFinder).readOnly, isFalse);
    await tester.showKeyboard(fieldFinder);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.escape);
    await tester.pump();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(tester.widget<TextField>(fieldFinder).readOnly, isTrue);

    await tester.sendKeyUpEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('tv_virtual_keyboard_dialog')), findsNothing);
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(tester.widget<TextField>(fieldFinder).readOnly, isTrue);
    expect(tester.takeException(), isNull);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(saved, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('settings save helper reports platform failures and remains retryable', (tester) async {
    final context = await _pumpHost(tester);

    showRegexInputDialog(
      context: context,
      title: 'Regex',
      currentValue: 'abc',
      defaultValue: '.*',
      onSave: (_) async => throw PlatformException(code: 'write_failed'),
    );
    await tester.pumpAndSettle();
    await tester.tap(_saveButton());
    await tester.pump();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text(t.settings.saveFailed), findsOneWidget);
  });

  testWidgets('settings save helper reports filesystem failures and remains retryable', (tester) async {
    final context = await _pumpHost(tester);

    showRegexInputDialog(
      context: context,
      title: 'Regex',
      currentValue: 'abc',
      defaultValue: '.*',
      onSave: (_) async => throw const FileSystemException('write failed'),
    );
    await tester.pumpAndSettle();
    await tester.tap(_saveButton());
    await tester.pump();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text(t.settings.saveFailed), findsOneWidget);
  });

  testWidgets('settings save helper closes only after a successful save', (tester) async {
    final context = await _pumpHost(tester);
    var saved = false;

    showRegexInputDialog(
      context: context,
      title: 'Regex',
      currentValue: 'abc',
      defaultValue: '.*',
      onSave: (_) async => saved = true,
    );
    await tester.pumpAndSettle();
    await tester.tap(_saveButton());
    await tester.pumpAndSettle();

    expect(saved, isTrue);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('disposed settings save context does not present late feedback', (tester) async {
    final context = await _pumpHost(tester);
    final saveGate = Completer<void>();

    showRegexInputDialog(
      context: context,
      title: 'Regex',
      currentValue: 'abc',
      defaultValue: '.*',
      onSave: (_) async {
        await saveGate.future;
        throw PlatformException(code: 'late_write_failure');
      },
    );
    await tester.pumpAndSettle();
    await tester.tap(_saveButton());
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    saveGate.complete();
    await tester.pump();

    expect(find.text(t.settings.saveFailed), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('pre-persisted blank pattern is rejected at save instead of round-tripping', (tester) async {
    final context = await _pumpHost(tester);
    final saved = <String>[];

    showRegexInputDialog(
      context: context,
      title: 'Regex',
      currentValue: '',
      defaultValue: '.*',
      onSave: (value) async => saved.add(value),
    );
    await tester.pumpAndSettle();
    await tester.tap(_saveButton());
    await tester.pumpAndSettle();

    expect(saved, isEmpty);
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text(t.settings.invalidRegex), findsOneWidget);
  });

  testWidgets('whitespace-only pattern is flagged while typing and rejected at save', (tester) async {
    final context = await _pumpHost(tester);
    final saved = <String>[];

    showRegexInputDialog(
      context: context,
      title: 'Regex',
      currentValue: 'abc',
      defaultValue: '.*',
      onSave: (value) async => saved.add(value),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '   ');
    await tester.pump();

    expect(find.text(t.settings.invalidRegex), findsOneWidget);

    await tester.tap(_saveButton());
    await tester.pumpAndSettle();

    expect(saved, isEmpty);
    expect(find.byType(AlertDialog), findsOneWidget);
  });

  testWidgets('non-blank pattern is persisted verbatim without trimming', (tester) async {
    final context = await _pumpHost(tester);
    final saved = <String>[];

    showRegexInputDialog(
      context: context,
      title: 'Regex',
      currentValue: 'abc',
      defaultValue: '.*',
      onSave: (value) async => saved.add(value),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), r' credits\s*roll ');
    await tester.pump();
    await tester.tap(_saveButton());
    await tester.pumpAndSettle();

    expect(saved, [r' credits\s*roll ']);
    expect(find.byType(AlertDialog), findsNothing);
  });
}

Future<BuildContext> _pumpHost(WidgetTester tester) async {
  late BuildContext context;
  await tester.pumpWidget(
    TranslationProvider(
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (hostContext) {
              context = hostContext;
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    ),
  );
  return context;
}

Finder _saveButton() => find.widgetWithText(DialogActionButton, t.common.save);

void _selectionTests() {
  Future<Future<DialogOption<String?>?>> open(WidgetTester tester, AppThemeVariant variant) async {
    late BuildContext host;
    await tester.pumpWidget(
      MaterialApp(
        theme: monoTheme(dark: true, variant: variant),
        home: Scaffold(
          body: Builder(
            builder: (context) {
              host = context;
              return const SizedBox.expand();
            },
          ),
        ),
      ),
    );
    final result = showSelectionDialog<String?>(
      context: host,
      title: 'Sprache',
      options: const [
        DialogOption(value: null, title: 'Systemsprache'),
        DialogOption(value: 'de', title: 'Deutsch'),
        DialogOption(value: 'en', title: 'English'),
      ],
      currentValue: 'de',
    );
    await tester.pumpAndSettle();
    return result;
  }

  testWidgets('the redesign asks with its own chooser, the chosen entry marked', (tester) async {
    final result = await open(tester, AppThemeVariant.glas);

    expect(find.byType(AppMenuSheet<int>), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    final entries = tester.widget<AppMenuSheet<int>>(find.byType(AppMenuSheet<int>)).entries;
    expect(entries.whereType<AppMenuItem<int>>().where((e) => e.selected).single.label, 'Deutsch');

    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();
    expect((await result)?.value, 'en');
  });

  testWidgets('a picked option whose value is null still reads as picked', (tester) async {
    final result = await open(tester, AppThemeVariant.glas);

    await tester.tap(find.text('Systemsprache'));
    await tester.pumpAndSettle();
    final picked = await result;
    expect(picked, isNotNull);
    expect(picked!.value, isNull);
  });

  testWidgets('the other themes keep the dialog', (tester) async {
    await open(tester, AppThemeVariant.standard);

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.byType(AppMenuSheet<int>), findsNothing);
  });
}
