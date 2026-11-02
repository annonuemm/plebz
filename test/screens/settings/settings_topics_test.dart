import 'package:flutter/material.dart' hide ThemeMode;
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/i18n/strings.g.dart';
import 'package:plezy/providers/theme_provider.dart';
import 'package:plezy/screens/settings/appearance_settings_screen.dart';
import 'package:plezy/screens/settings/playback_settings_screen.dart';
import 'package:plezy/services/settings_service.dart';
import 'package:plezy/services/supporter/supporter_mode.dart';
import 'package:plezy/services/supporter/supporter_service.dart';
import 'package:plezy/theme/mono_theme.dart';
import 'package:plezy/widgets/settings_section.dart';
import 'package:provider/provider.dart';

import '../../test_helpers/prefs.dart';

/// The long pages stand under topics of their own: every group on exactly one
/// page, so splitting them lost none.
void main() {
  setUp(() async {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    await SettingsService.getInstance();
    LocaleSettings.setLocaleSync(AppLocale.en);
  });

  void tall(WidgetTester tester) {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1000, 9000);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
  }

  Future<List<String?>> groupsOn(WidgetTester tester, Widget page) async {
    final supporter = SupporterService.forTesting(availability: SupporterAvailability.hidden);
    addTearDown(supporter.dispose);
    final theme = ThemeProvider(supporter: supporter);
    addTearDown(theme.dispose);
    await tester.pumpWidget(
      ChangeNotifierProvider<ThemeProvider>.value(
        value: theme,
        child: MaterialApp(theme: monoTheme(MonoPalette.dark), home: page),
      ),
    );
    await tester.pumpAndSettle();
    return [for (final group in tester.widgetList<SettingsGroup>(find.byType(SettingsGroup))) group.title];
  }

  testWidgets('the appearance topics share out its groups', (tester) async {
    tall(tester);

    expect(await groupsOn(tester, const AppearanceSettingsScreen(topic: AppearanceTopic.look)), [
      t.settings.display,
      t.settings.navigation,
    ]);
    expect(await groupsOn(tester, const AppearanceSettingsScreen(topic: AppearanceTopic.cards)), [
      t.settings.libraryAndCards,
      t.settings.detailPages,
    ]);
    expect(await groupsOn(tester, const AppearanceSettingsScreen(topic: AppearanceTopic.home)), [
      null,
    ], reason: 'the page is called what its one group would be');
    expect(find.text(t.settings.homeScreen), findsOneWidget);
  });

  testWidgets('the playback topics share out its groups, what few change last', (tester) async {
    tall(tester);

    expect(await groupsOn(tester, const PlaybackSettingsScreen(topic: PlaybackTopic.player)), [
      null,
      t.settings.videoAndDisplay,
      t.settings.quality,
      t.settings.advanced,
    ]);
    expect(find.text(t.settings.hardwareDecoding), findsOneWidget);

    expect(await groupsOn(tester, const PlaybackSettingsScreen(topic: PlaybackTopic.soundAndSubtitles)), [
      t.settings.audio,
      t.settings.subtitles,
    ]);
    expect(find.text(t.settings.hardwareDecoding), findsNothing);

    final handling = await groupsOn(tester, const PlaybackSettingsScreen(topic: PlaybackTopic.handling));
    expect(handling, containsAll([t.settings.seekAndTiming, t.settings.autoPlayAndSkip, t.settings.behavior]));
    expect(handling, contains(t.settings.rememberPlayerChanges));
  });
}
