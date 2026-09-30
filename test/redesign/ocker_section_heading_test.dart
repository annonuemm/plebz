import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/redesign/ocker_section_heading.dart';
import 'package:plezy/services/settings_service.dart' show AppThemeVariant, GlasAccent;
import 'package:plezy/theme/mono_theme.dart';

import '../test_helpers/prefs.dart';

/// Every shelf on the page draws the same heading: mono name, counter, and a
/// hairline out to the right edge. The resume row draws its rule in the accent
/// instead — the one row whose items are positions rather than titles, and the
/// only row that may have it, because the accent's three jobs are progress,
/// the now-line, and the destination on show.
///
/// It is also the *only* accent in that row: the bars on the posters below are
/// ink, so the colour says "this row" once rather than once per tile.
/// The redesign's accent in its default palette.
final _accent = glasPalette(GlasAccent.eisblau).accent;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(resetSharedPreferencesForTest);

  Future<List<Color>> rulesOf(
    WidgetTester tester, {
    required bool inProgress,
    bool trailing = false,
    AppThemeVariant variant = AppThemeVariant.glas,
  }) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: monoTheme(dark: true, variant: variant),
        home: Scaffold(
          body: OckerSectionHeading(title: 'Weiterschauen', count: 9, trailing: trailing, inProgress: inProgress),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return tester
        .widgetList<Container>(find.byType(Container))
        .map((c) => c.color)
        .whereType<Color>()
        .where((c) => c.a > 0)
        .toList();
  }

  testWidgets('draws nothing beside an ordinary shelf\'s name', (tester) async {
    // There was a hairline out to the right edge of every heading. Over a page
    // of shelves that was a dozen faint rules pointing at nothing.
    expect(await rulesOf(tester, inProgress: false), isEmpty);
  });

  testWidgets('draws the resume row in the accent', (tester) async {
    expect(await rulesOf(tester, inProgress: true), contains(_accent));
  });

  testWidgets('dims it further down the page, like the words beside it', (tester) async {
    final rules = await rulesOf(tester, inProgress: true, trailing: true);

    expect(rules, isNot(contains(_accent)), reason: 'the accent, but not at full strength');
    expect(rules.map((c) => Color(c.toARGB32()).withValues(alpha: 1)), contains(_accent));
  });
}
