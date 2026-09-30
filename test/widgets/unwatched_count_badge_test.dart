import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/theme/mono_theme.dart';
import 'package:plezy/widgets/unwatched_count_badge.dart';

void main() {
  Future<void> pumpBadge(WidgetTester tester, int count) {
    return tester.pumpWidget(
      MaterialApp(
        theme: monoTheme(dark: true),
        home: Scaffold(
          body: Center(child: UnwatchedCountBadge(count: count)),
        ),
      ),
    );
  }

  testWidgets('single digit keeps circular footprint', (tester) async {
    await pumpBadge(tester, 5);
    expect(find.text('5'), findsOneWidget);
    expect(
      tester.getSize(find.byType(UnwatchedCountBadge)),
      const Size(UnwatchedCountBadge.defaultSize, UnwatchedCountBadge.defaultSize),
    );
  });

  testWidgets('counts above 999 cap at 999+ on a single line', (tester) async {
    await pumpBadge(tester, 1200);
    expect(find.text('999+'), findsOneWidget);

    final badge = tester.getSize(find.byType(UnwatchedCountBadge));
    expect(badge.height, UnwatchedCountBadge.defaultSize);
    expect(badge.width, greaterThan(UnwatchedCountBadge.defaultSize));
    // Wide labels widen the pill instead of wrapping (#1310): the text stays
    // one line tall and inside the badge.
    expect(tester.getSize(find.text('999+')).height, lessThanOrEqualTo(UnwatchedCountBadge.defaultSize));
    expect(tester.takeException(), isNull);
  });

  testWidgets('the count is one size on every surface', (tester) async {
    // Poster corners, episode cards, folder rows and playlist items all read
    // this element together; per-surface sizes drifted apart once already.
    await pumpBadge(tester, 5);
    final text = tester.widget<Text>(find.text('5'));
    expect(text.style?.fontSize, UnwatchedCountBadge.defaultFontSize);
  });

  testWidgets('999 renders uncapped', (tester) async {
    await pumpBadge(tester, 999);
    expect(find.text('999'), findsOneWidget);
  });
}
