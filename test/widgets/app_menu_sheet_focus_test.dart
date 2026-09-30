import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/focus/input_mode_tracker.dart';
import 'package:plezy/services/settings_service.dart' show AppThemeVariant;
import 'package:plezy/theme/mono_theme.dart';
import 'package:plezy/widgets/app_menu.dart';
import 'package:plezy/widgets/overlay_sheet.dart';

import '../test_helpers/prefs.dart';

/// A chooser opened from a destination must land on the entry that is already
/// on. The menu asked for that itself and it still opened at the top: inside a
/// hosted sheet the host gives focus to the first thing it can traverse to, a
/// frame after the list has asked — so the list has to tell the host which
/// node to use, not merely request focus.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(resetSharedPreferencesForTest);

  bool focusedRowIs(WidgetTester tester, String label) {
    final rows = find.ancestor(of: find.text(label), matching: find.byType(Focus));
    // Primary focus, not `hasFocus`: an ancestor scope reports focus for every
    // row inside it, which would make any row look like the chosen one.
    return tester.widgetList<Focus>(rows).any((focus) => focus.focusNode?.hasPrimaryFocus ?? false);
  }

  testWidgets('a hosted chooser opens on the entry that is on', (tester) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    late BuildContext hostContext;
    await tester.pumpWidget(
      InputModeTracker(
        child: MaterialApp(
          theme: monoTheme(dark: true, variant: AppThemeVariant.glas),
          home: OverlaySheetHost(
            child: Builder(
              builder: (context) {
                hostContext = context;
                return const Scaffold(body: SizedBox.expand());
              },
            ),
          ),
        ),
      ),
    );

    // The host only hands focus to a descendant where there is a cursor to
    // hand it to — a remote or a keyboard, not a finger.
    InputModeTracker.reportNonPointerInput();
    await tester.pump();

    unawaited(
      showAdaptiveAppMenu<String>(
        hostContext,
        title: 'Sendergruppen',
        focusFirstItem: true,
        entries: const [
          AppMenuItem<String>(value: 'all', label: 'Alle Sender'),
          AppMenuItem<String>(value: 'free', label: 'FreeTV', selected: true),
          AppMenuItem<String>(value: 'doku', label: 'Doku'),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(focusedRowIs(tester, 'FreeTV'), isTrue, reason: 'the group the guide is narrowed to');
    expect(focusedRowIs(tester, 'Alle Sender'), isFalse, reason: 'not merely the top of the list');
  });
}
