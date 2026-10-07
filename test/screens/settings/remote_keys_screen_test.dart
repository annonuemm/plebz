import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/i18n/strings.g.dart';
import 'package:plezy/screens/settings/remote_keys_screen.dart';
import 'package:plezy/services/settings_service.dart';
import 'package:plezy/theme/mono_theme.dart';

import '../../test_helpers/prefs.dart';

void main() {
  setUp(() async {
    LocaleSettings.setLocaleSync(AppLocale.en);
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    await SettingsService.getInstance();
  });

  testWidgets('the guide names every group, down to the receiver letters', (tester) async {
    tester.view.physicalSize = const Size(1280, 6000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      TranslationProvider(
        child: MaterialApp(theme: monoTheme(dark: true), home: const RemoteKeysScreen()),
      ),
    );
    await tester.pump();

    for (final text in [
      t.remoteKeys.playbackGroup,
      t.remoteKeys.liveGroup,
      t.remoteKeys.colourGroup,
      t.remoteKeys.receiverGroup,
      t.remoteKeys.doStop,
      t.remoteKeys.doDigits,
      t.remoteKeys.keyYellow,
      t.remoteKeys.functions.skipMarker,
      t.remoteKeys.doLetterX,
    ]) {
      expect(find.text(text), findsWidgets, reason: text);
    }
  });

  testWidgets('the remote walks down every row to the colour keys', (tester) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      TranslationProvider(
        child: MaterialApp(theme: monoTheme(dark: true), home: const RemoteKeysScreen()),
      ),
    );
    await tester.pumpAndSettle();

    bool onRed() {
      final tile = FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<ListTile>();
      final title = tile?.title;
      return title is Text && title.data == t.remoteKeys.keyRed;
    }

    var reached = false;
    for (var i = 0; i < 40 && !reached; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      reached = onRed();
    }
    expect(reached, isTrue, reason: 'the red key\'s row is reachable by D-pad');
    expect(find.text(t.remoteKeys.keyRed).hitTestable(), findsOneWidget, reason: 'and scrolled into view');
  });
}
