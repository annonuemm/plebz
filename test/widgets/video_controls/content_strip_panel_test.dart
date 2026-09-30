import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:plezy/widgets/video_controls/widgets/content_strip_panel.dart';

/// The scrim under a strip over the picture. It is only as wide as the panel,
/// so behind the group list — half the screen, a pane of its own under glass —
/// it showed as a dark box with square corners round the pane.
void main() {
  Future<Decoration?> decorationOf(WidgetTester tester, {required bool scrim}) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ContentStripPanel(
            padding: EdgeInsets.zero,
            chevron: Symbols.keyboard_arrow_up_rounded,
            scrim: scrim,
            child: const SizedBox(width: 200, height: 100),
          ),
        ),
      ),
    );
    final panel = find.byType(ContentStripPanel);
    return tester.widget<Container>(find.descendant(of: panel, matching: find.byType(Container)).first).decoration;
  }

  testWidgets('draws its gradient by default', (tester) async {
    final decoration = await decorationOf(tester, scrim: true);

    expect(decoration, isA<BoxDecoration>());
    expect((decoration! as BoxDecoration).gradient, isNotNull);
  });

  testWidgets('draws nothing behind a strip that brings its own pane', (tester) async {
    expect(await decorationOf(tester, scrim: false), isNull);
  });
}
