import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/services/settings_service.dart' show AppThemeVariant, GlasAccent;
import 'package:plezy/redesign/ocker_skin.dart';
import 'package:plezy/theme/mono_theme.dart';
import 'package:plezy/widgets/app_menu.dart';
import 'package:plezy/widgets/app_icon.dart';

import '../test_helpers/prefs.dart';

/// Every chooser in the app comes out of [AppMenuSheet] — the channel groups in
/// the live player, the profile menu, every popup. They were the last surface
/// still speaking Material: a centred bold title, a filled plate under the
/// focused row, a tick and a bold beside the chosen one. The redesign says the
/// same three things with a heading in mono, a hairline, and one accent rule.
/// The redesign's accent in its default palette.
final _accent = glasPalette(GlasAccent.eisblau).accent;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(resetSharedPreferencesForTest);

  Future<void> pumpSheet(WidgetTester tester, AppThemeVariant variant, {bool focusFirstItem = false}) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: monoTheme(dark: true, variant: variant),
        home: Scaffold(
          body: AppMenuSheet<String>(
            title: 'Sendergruppen',
            entries: const [
              AppMenuItem<String>(value: 'all', label: 'Alle Sender'),
              AppMenuItem<String>(value: 'free', label: 'FreeTV', selected: true),
              AppMenuItem<String>(value: 'doku', label: 'Doku'),
            ],
            focusFirstItem: focusFirstItem,
            onSelected: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  List<Color> fillsIn(WidgetTester tester) =>
      tester.widgetList<Container>(find.byType(Container)).map((c) => c.color).whereType<Color>().toList();

  testWidgets('sets the sheet title as a heading of this design', (tester) async {
    await pumpSheet(tester, AppThemeVariant.glas);

    expect(find.text('SENDERGRUPPEN'), findsOneWidget);
    expect(find.text('Sendergruppen'), findsNothing);
  });

  testWidgets('marks the chosen entry with the accent and nothing else', (tester) async {
    await pumpSheet(tester, AppThemeVariant.glas);

    // Under glass: a pane washed with the accent behind the chosen row.
    expect(
      tester.widgetList<OckerGlassFocusFill>(find.byType(OckerGlassFocusFill)).where((fill) => fill.tint == 1),
      hasLength(1),
    );
    // No tick: the rule under the word already says which one this is, and the
    // accent has three jobs of which this is one.
    expect(find.byType(AppIcon), findsNothing);
  });

  testWidgets('leaves Standard the chooser it had', (tester) async {
    await pumpSheet(tester, AppThemeVariant.standard);

    expect(find.text('Sendergruppen'), findsOneWidget);
    expect(find.byType(AppIcon), findsOneWidget, reason: 'the tick beside the chosen entry');
    expect(fillsIn(tester), isNot(contains(_accent)));
  });

  testWidgets('opens on the entry that is already on, not the first one', (tester) async {
    // A chooser opened from a destination asks "which one", and the answer it
    // already has is where the remote should start. Landing at the top of
    // fifteen libraries means scrolling back to where you were.
    await pumpSheet(tester, AppThemeVariant.glas, focusFirstItem: true);

    // Primary focus, not `hasFocus`: an ancestor scope reports focus for every
    // row inside it, which would make any row look like the chosen one.
    bool rowHasCursor(String label) => tester
        .widgetList<Focus>(find.ancestor(of: find.text(label), matching: find.byType(Focus)))
        .any((focus) => focus.focusNode?.hasPrimaryFocus ?? false);

    expect(rowHasCursor('FreeTV'), isTrue, reason: 'FreeTV is the entry that is on');
    expect(rowHasCursor('Alle Sender'), isFalse, reason: 'not merely the top of the list');
  });
}
