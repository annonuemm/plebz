import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:plezy/focus/input_mode_tracker.dart';
import 'package:plezy/i18n/strings.g.dart';
import 'package:plezy/screens/settings/plebz_settings_shell.dart';
import 'package:plezy/services/settings_service.dart';
import 'package:plezy/theme/mono_theme.dart';
import 'package:plezy/widgets/focusable_list_tile.dart';
import 'package:plezy/widgets/setting_tile.dart';
import 'package:plezy/widgets/settings_page.dart';
import 'package:plezy/widgets/settings_section.dart';

import '../../test_helpers/prefs.dart';

/// A topic whose page holds two rows, the second opening a sub-page.
PlebzSettingsSection _section(String id, String group) => PlebzSettingsSection(
  id: id,
  group: group,
  icon: Symbols.settings_rounded,
  title: 'Topic $id',
  page: (_) => SettingsPage(
    title: Text('Page $id'),
    children: [
      SettingsGroup(
        children: [
          SettingNavigationTile(icon: Symbols.tune_rounded, title: 'First row of $id', onTap: () {}),
          SettingNavigationTile(
            icon: Symbols.tune_rounded,
            title: 'Deeper in $id',
            destinationBuilder: (_) => SettingsPage(
              title: Text('Sub-page of $id'),
              children: [
                SettingsGroup(
                  children: [SettingNavigationTile(icon: Symbols.tune_rounded, title: 'Sub row', onTap: () {})],
                ),
              ],
            ),
          ),
        ],
      ),
    ],
  ),
);

final _sections = [_section('a', 'Group one'), _section('b', 'Group one'), _section('c', 'Group two')];

FocusNode _rowNode(WidgetTester tester, String id) =>
    tester.widget<FocusableListTile>(find.byKey(PlebzSettingsShell.rowKey(id))).focusNode!;

FocusNode? get _focus => FocusManager.instance.primaryFocus;

bool _focusIsOnTile(WidgetTester tester, String title) {
  final tile = tester.widget<ListTile>(
    find.descendant(
      of: find.ancestor(of: find.text(title), matching: find.byType(FocusableListTile)),
      matching: find.byType(ListTile),
    ),
  );
  return tile.focusNode!.hasPrimaryFocus;
}

void main() {
  setUp(() async {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    await SettingsService.getInstance();
  });

  Future<GlobalKey<PlebzSettingsShellState>> pumpShell(
    WidgetTester tester, {
    Size size = const Size(1280, 720),
    VoidCallback? onExitLeft,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final key = GlobalKey<PlebzSettingsShellState>();
    await tester.pumpWidget(
      TranslationProvider(
        child: InputModeTracker(
          child: MaterialApp(
            theme: monoTheme(dark: true),
            home: Scaffold(
              body: PlebzSettingsShell(
                key: key,
                title: 'Settings',
                sections: _sections,
                onExitLeft: onExitLeft ?? () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return key;
  }

  /// A remote announces itself with its first arrow key; then the cursor is
  /// put on the column, as the tab does when the settings come forward.
  Future<void> enterWithRemote(WidgetTester tester, GlobalKey<PlebzSettingsShellState> key) async {
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    key.currentState!.focusColumn();
    await tester.pumpAndSettle();
  }

  testWidgets('walking the column shows each page beside it and keeps the cursor in the column', (tester) async {
    final key = await pumpShell(tester);
    await enterWithRemote(tester, key);
    expect(_focus, _rowNode(tester, 'a'));
    expect(find.text('Page a'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();

    expect(find.text('Page b'), findsOneWidget);
    expect(find.text('Page a'), findsNothing);
    expect(_focus, _rowNode(tester, 'b'), reason: 'a page shown must not pull the cursor across');

    // The last row stays the last.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(_focus, _rowNode(tester, 'c'));
    expect(find.text('Page c'), findsOneWidget);
  });

  testWidgets('RIGHT goes into the page and LEFT comes back to the topic', (tester) async {
    final key = await pumpShell(tester);
    await enterWithRemote(tester, key);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(_focusIsOnTile(tester, 'First row of a'), isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(_focusIsOnTile(tester, 'Deeper in a'), isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(_focus, _rowNode(tester, 'a'));

    // Back in, the cursor lands where it was.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(_focusIsOnTile(tester, 'Deeper in a'), isTrue);
  });

  testWidgets('a sub-page opens beside the column, and BACK steps out one level at a time', (tester) async {
    final key = await pumpShell(tester);
    await enterWithRemote(tester, key);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(find.text('Sub-page of a'), findsOneWidget);
    expect(find.byKey(PlebzSettingsShell.rowKey('b')), findsOneWidget, reason: 'the column stays in view');

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Sub-page of a'), findsNothing);
    expect(find.text('Page a'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(_focus, _rowNode(tester, 'a'));
  });

  testWidgets('another topic closes what the last one opened', (tester) async {
    final key = await pumpShell(tester);
    await enterWithRemote(tester, key);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('Sub-page of a'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();

    expect(find.text('Sub-page of a'), findsNothing);
    expect(find.text('Page b'), findsOneWidget);
  });

  testWidgets('LEFT off the column goes on to the navigation', (tester) async {
    var left = 0;
    final key = await pumpShell(tester, onExitLeft: () => left++);
    await enterWithRemote(tester, key);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(left, 1);
  });

  testWidgets('a click on a topic shows it without moving into it', (tester) async {
    await pumpShell(tester);
    await tester.tap(find.text('Topic c'));
    await tester.pumpAndSettle();

    expect(find.text('Page c'), findsOneWidget);
    await tester.tap(find.text('Deeper in c'));
    await tester.pumpAndSettle();
    expect(find.text('Sub-page of c'), findsOneWidget);
  });

  testWidgets('too narrow for two columns, the column is the page and a topic opens on its own', (tester) async {
    await pumpShell(tester, size: const Size(400, 800));

    expect(find.text('Group one'), findsOneWidget);
    expect(find.text('Group two'), findsOneWidget);
    expect(find.text('Page a'), findsNothing);

    await tester.tap(find.text('Topic b'));
    await tester.pumpAndSettle();
    expect(find.text('Page b'), findsOneWidget);
    expect(find.text('Topic a'), findsNothing);
  });

  testWidgets('LEFT in a field being typed in moves the caret, not the cursor', (tester) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final key = GlobalKey<PlebzSettingsShellState>();
    final field = FocusNode();
    addTearDown(field.dispose);
    await tester.pumpWidget(
      TranslationProvider(
        child: InputModeTracker(
          child: MaterialApp(
            theme: monoTheme(dark: true),
            home: Scaffold(
              body: PlebzSettingsShell(
                key: key,
                title: 'Settings',
                sections: [
                  PlebzSettingsSection(
                    id: 'form',
                    group: 'Group',
                    icon: Symbols.settings_rounded,
                    title: 'Form',
                    page: (_) => Scaffold(body: TextField(focusNode: field)),
                  ),
                ],
                onExitLeft: () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    key.currentState!.focusColumn();
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(field.hasPrimaryFocus, isTrue);

    await tester.enterText(find.byType(TextField), 'abc');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(field.hasPrimaryFocus, isTrue);
  });
}
