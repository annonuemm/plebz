import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/focus/input_mode_tracker.dart';
import 'package:plezy/i18n/strings.g.dart';
import 'package:plezy/navigation/profile_navigation_scope.dart';
import 'package:plezy/redesign/ocker_skin.dart';
import 'package:plezy/services/settings_service.dart' show AppThemeVariant;
import 'package:plezy/theme/mono_theme.dart';
import 'package:plezy/widgets/detail_home_button.dart';

void main() {
  setUpAll(() => LocaleSettings.setLocaleSync(AppLocale.en));

  /// A profile navigator with a root and two detail pages over it, the top
  /// one carrying [top]. Registered as the app's profile navigator for the
  /// test, with a home that counts its calls.
  Future<({GlobalKey<NavigatorState> key, List<int> homeShown})> pumpRun(
    WidgetTester tester, {
    required Widget top,
    AppThemeVariant variant = AppThemeVariant.standard,
    bool registerHome = true,
  }) async {
    final key = GlobalKey<NavigatorState>();
    final homeShown = <int>[];
    await tester.pumpWidget(
      InputModeTracker(
        child: MaterialApp(
          theme: monoTheme(dark: true, variant: variant),
          home: Navigator(
            key: key,
            onGenerateRoute: (_) => MaterialPageRoute<void>(builder: (_) => const Text('root')),
          ),
        ),
      ),
    );
    profileNavigationRegistry.attachNavigator(key);
    addTearDown(() => profileNavigationRegistry.detachNavigator(key));
    if (registerHome) {
      void showHome() => homeShown.add(1);
      profileNavigationRegistry.attachHome(showHome);
      addTearDown(() => profileNavigationRegistry.detachHome(showHome));
    }
    unawaited(key.currentState!.push(MaterialPageRoute<void>(builder: (_) => const Text('first detail'))));
    await tester.pumpAndSettle();
    unawaited(
      key.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => Scaffold(body: Column(children: [const Text('second detail'), top])),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return (key: key, homeShown: homeShown);
  }

  testWidgets('the TV button leaves every detail page for the home tab', (tester) async {
    final run = await pumpRun(tester, top: const DetailHomeButton());

    await tester.tap(find.byType(DetailHomeButton));
    await tester.pumpAndSettle();

    expect(find.text('second detail'), findsNothing);
    expect(find.text('first detail'), findsNothing);
    expect(find.text('root'), findsOneWidget);
    expect(run.homeShown, hasLength(1));
  });

  testWidgets('the one beside the back arrow does the same', (tester) async {
    final run = await pumpRun(tester, top: const DetailHomeBesideBack());

    await tester.tap(find.byType(DetailHomeBesideBack));
    await tester.pumpAndSettle();

    expect(find.text('first detail'), findsNothing);
    expect(find.text('root'), findsOneWidget);
    expect(run.homeShown, hasLength(1));
  });

  testWidgets('with no main screen to return to it leaves only its own page', (tester) async {
    await pumpRun(tester, top: const DetailHomeButton(), registerHome: false);

    await tester.tap(find.byType(DetailHomeButton));
    await tester.pumpAndSettle();

    expect(find.text('second detail'), findsNothing);
    expect(find.text('first detail'), findsOneWidget);
  });

  testWidgets('down goes back to the action row; the other arrows keep it', (tester) async {
    final node = FocusNode(debugLabel: 'home');
    addTearDown(node.dispose);
    var down = 0;
    await pumpRun(
      tester,
      top: DetailHomeButton(focusNode: node, onNavigateDown: () => down++),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown); // keyboard mode
    node.requestFocus();
    await tester.pump();

    for (final key in [LogicalKeyboardKey.arrowUp, LogicalKeyboardKey.arrowLeft, LogicalKeyboardKey.arrowRight]) {
      await tester.sendKeyEvent(key);
      await tester.pump();
      expect(node.hasFocus, isTrue, reason: '$key');
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(down, 1);
  });

  testWidgets('under Glas a quiet pane of glass, lit while focused', (tester) async {
    final node = FocusNode(debugLabel: 'home');
    addTearDown(node.dispose);
    await pumpRun(
      tester,
      top: DetailHomeButton(focusNode: node),
      variant: AppThemeVariant.glas,
    );

    OckerGlassFocusFill fill() => tester.widget<OckerGlassFocusFill>(
      find.descendant(of: find.byType(DetailHomeButton), matching: find.byType(OckerGlassFocusFill)),
    );
    expect(fill().bright, isFalse);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown); // keyboard mode
    node.requestFocus();
    await tester.pumpAndSettle();
    expect(fill().bright, isTrue);
  });

  testWidgets('elsewhere a dark disc, and no glass', (tester) async {
    await pumpRun(tester, top: const DetailHomeButton());

    expect(
      find.descendant(of: find.byType(DetailHomeButton), matching: find.byType(OckerGlassFocusFill)),
      findsNothing,
    );
  });
}
