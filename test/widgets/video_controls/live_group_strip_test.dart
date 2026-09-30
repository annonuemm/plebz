import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/focus/focus_theme.dart';
import 'package:plezy/focus/focusable_wrapper.dart';
import 'package:plezy/redesign/ocker_skin.dart';
import 'package:plezy/services/settings_service.dart' show AppThemeVariant;
import 'package:plezy/theme/mono_theme.dart';
import 'package:plezy/widgets/video_controls/widgets/live_group_strip.dart';

import '../../test_helpers/prefs.dart';

/// The group list over a running channel. Under "Glas" it is the guide's own
/// group column in small: one pane of glass, the group in force a quiet pane
/// washed with the accent, focus a bright one, and no bar.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(resetSharedPreferencesForTest);

  const groups = <LiveChannelGroupOption>[
    (key: null, label: 'Alle Sender', count: 120),
    (key: 'doku', label: 'Doku', count: 12),
    (key: 'sport', label: 'Sport', count: 8),
  ];

  Future<GlobalKey<LiveGroupStripState>> pumpStrip(WidgetTester tester, AppThemeVariant variant) async {
    final key = GlobalKey<LiveGroupStripState>();
    await tester.pumpWidget(
      MaterialApp(
        theme: monoTheme(dark: true, variant: variant),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 420,
              child: LiveGroupStrip(key: key, groups: groups, selected: 'doku', onGroupSelected: (_) {}),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return key;
  }

  testWidgets('under glass the list lies on one pane, the group in force washed with the accent', (tester) async {
    final key = await pumpStrip(tester, AppThemeVariant.glas);

    expect(find.byType(OckerGlass), findsOneWidget);
    final chosen = tester.widgetList<OckerGlassFocusFill>(find.byType(OckerGlassFocusFill)).where((f) => f.tint == 1);
    expect(chosen, hasLength(1));
    expect(
      find.byWidgetPredicate((w) => w is Container && w.constraints?.maxWidth == 3),
      findsNothing,
      reason: 'no bar beside the group in force',
    );

    // Focus as a bright pane, and the list still walks with the D-pad.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    key.currentState!.requestInitialFocus();
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'live_group_1');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'live_group_2');
  });

  for (final variant in [AppThemeVariant.glas, AppThemeVariant.standard]) {
    testWidgets('${variant.name}: a focused row, grown by the focus scale, stays inside the list', (tester) async {
      final key = await pumpStrip(tester, variant);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      key.currentState!.requestInitialFocus();
      await tester.pumpAndSettle();

      final list = tester.getRect(find.byType(Scrollable));
      final row = tester.getRect(find.ancestor(of: find.text('Doku'), matching: find.byType(FocusableWrapper)).first);
      final growth = row.width * (FocusTheme.focusScale - 1) / 2;
      expect(row.left - growth, greaterThanOrEqualTo(list.left), reason: 'the list clips at its edges');
      expect(row.right + growth, lessThanOrEqualTo(list.right));
    });
  }

  testWidgets('the standard theme keeps its plates', (tester) async {
    await pumpStrip(tester, AppThemeVariant.standard);
    expect(find.byType(OckerGlass), findsNothing);
  });
}
