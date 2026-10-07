import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/i18n/strings.g.dart';
import 'package:plezy/providers/theme_provider.dart';
import 'package:plezy/screens/settings/appearance_settings_screen.dart';
import 'package:plezy/services/settings_service.dart';
import 'package:plezy/theme/mono_theme.dart';
import 'package:plezy/utils/platform_detector.dart';
import 'package:provider/provider.dart';

import '../../test_helpers/prefs.dart';

void main() {
  setUp(() async {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    await SettingsService.getInstance();
    LocaleSettings.setLocaleSync(AppLocale.en);
  });

  testWidgets('appearance screen renders every reorganized group', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1000, 3000);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final theme = ThemeProvider();
    addTearDown(theme.dispose);
    await tester.pumpWidget(
      ChangeNotifierProvider<ThemeProvider>.value(
        value: theme,
        child: MaterialApp(theme: monoTheme(dark: true), home: const AppearanceSettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    for (final group in [
      t.settings.display,
      t.settings.libraryAndCards,
      t.settings.homeScreen,
      t.settings.navigation,
    ]) {
      expect(find.text(group), findsOneWidget, reason: 'group $group missing');
    }
    final scrollable = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(find.text(t.settings.liveTv), 500, scrollable: scrollable);
    expect(find.text(t.settings.liveTvDefaultFavorites), findsOneWidget);
    // Moved away: profile prompt and performance overlay no longer live here.
    expect(find.text(t.settings.requireProfileSelectionOnOpen), findsNothing);
    expect(find.text(t.settings.autoHidePerformanceOverlay), findsNothing);
  });

  testWidgets('the accent colour is asked only while glass is the theme', (tester) async {
    // A television: the glass focus's own switches are asked only where
    // something is ever focused.
    TvDetectionService.debugSetAppleTVOverride(true);
    addTearDown(() => TvDetectionService.debugSetAppleTVOverride(null));
    // A television starts in glass; this one starts in the original look.
    await SettingsService.instanceOrNull!.write(SettingsService.appThemeVariant, AppThemeVariant.standard);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1000, 3000);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    debugRedesignOfferedHere = true;
    addTearDown(() => debugRedesignOfferedHere = null);

    final theme = ThemeProvider();
    addTearDown(theme.dispose);
    await tester.pumpWidget(
      ChangeNotifierProvider<ThemeProvider>.value(
        value: theme,
        child: MaterialApp(theme: monoTheme(dark: true), home: const AppearanceSettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text(t.settings.glasAccent), findsNothing);
    expect(find.text(t.settings.glasSmoothFocus), findsNothing);

    await SettingsService.instanceOrNull!.write(SettingsService.appThemeVariant, AppThemeVariant.glas);
    await tester.pumpAndSettle();
    expect(find.text(t.settings.glasAccent), findsOneWidget);
    expect(find.text(t.settings.glasAccentEisblau), findsOneWidget, reason: 'the accent on show by default');
    expect(find.text(t.settings.glasSmoothFocus), findsOneWidget, reason: 'the glide, apart from the effects');
  });

  testWidgets('glass on a television leaves out the rows it has nothing to steer with', (tester) async {
    TvDetectionService.debugSetAppleTVOverride(true);
    addTearDown(() => TvDetectionService.debugSetAppleTVOverride(null));
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1000, 4000);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    Future<void> pumpWith(AppThemeVariant variant) async {
      final theme = ThemeProvider();
      addTearDown(theme.dispose);
      await tester.pumpWidget(
        ChangeNotifierProvider<ThemeProvider>.value(
          value: theme,
          child: MaterialApp(
            theme: monoTheme(dark: true, variant: variant),
            home: const AppearanceSettingsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    final deadUnderGlas = [
      t.settings.viewMode,
      t.settings.libraryDensity,
      t.settings.gridSpacing,
      t.settings.showEpisodeNumberOnCards,
      t.settings.focusGlow,
      t.settings.alwaysKeepSidebarOpen,
      t.settings.groupLibrariesByServer,
    ];

    await pumpWith(AppThemeVariant.glas);
    for (final title in deadUnderGlas) {
      expect(find.text(title), findsNothing, reason: title);
    }
    expect(find.text(t.settings.episodePosterMode), findsOneWidget, reason: 'the glass posters follow this one');

    await pumpWith(AppThemeVariant.standard);
    for (final title in deadUnderGlas) {
      expect(find.text(title), findsOneWidget, reason: title);
    }
  });

  testWidgets('on a phone glass is offered with its accent, but not the focus switches', (tester) async {
    tester.view.devicePixelRatio = 1;
    // Wide, so the test face's box glyphs fit; what makes this a phone is the
    // platform, not the width.
    tester.view.physicalSize = const Size(1000, 3000);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    debugRedesignOfferedHere = true;
    addTearDown(() => debugRedesignOfferedHere = null);
    await SettingsService.instanceOrNull!.write(SettingsService.appThemeVariant, AppThemeVariant.glas);

    final theme = ThemeProvider();
    addTearDown(theme.dispose);
    await tester.pumpWidget(
      ChangeNotifierProvider<ThemeProvider>.value(
        value: theme,
        child: MaterialApp(theme: monoTheme(dark: true), home: const AppearanceSettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(t.settings.glasAccent), findsOneWidget);
    expect(find.text(t.settings.glasSmoothFocus), findsNothing, reason: 'a finger never puts focus anywhere');
    expect(find.text(t.settings.glasSpinningFocus), findsNothing);
  });
}
