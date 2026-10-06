import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/i18n/strings.g.dart';
import 'package:plezy/providers/iptv_sources_provider.dart';
import 'package:plezy/providers/trackers_provider.dart';
import 'package:plezy/screens/setup_wizard/setup_wizard.dart';
import 'package:plezy/services/iptv/iptv_source.dart';
import 'package:plezy/services/settings_service.dart';
import 'package:plezy/theme/mono_theme.dart';
import 'package:provider/provider.dart';

import '../test_helpers/prefs.dart';

/// Plebz's first-run setup: where an empty start goes, and the pages that
/// walk a new install through look, sources and services.
void main() {
  setUpAll(() => LocaleSettings.setLocaleSync(AppLocale.en));

  setUp(() async {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    await SettingsService.getInstance();
  });

  tearDown(SettingsService.resetForTesting);

  group('a start with no server connection', () {
    test('goes through the setup the first time', () {
      expect(routeForEmptyStart(onboardingCompleted: false, activeProfileHasIptv: false), EmptyStartRoute.setup);
    });

    test('goes to sign-in once the setup is behind it', () {
      expect(routeForEmptyStart(onboardingCompleted: true, activeProfileHasIptv: false), EmptyStartRoute.signIn);
    });

    test('carries on into the session for an IPTV-only profile', () {
      for (final completed in [true, false]) {
        expect(
          routeForEmptyStart(onboardingCompleted: completed, activeProfileHasIptv: true),
          EmptyStartRoute.iptvSession,
        );
      }
    });
  });

  test('a profile has IPTV only when a source is stored for it', () async {
    final settings = SettingsService.instance;
    expect(profileHasIptvSources('p'), isFalse);
    expect(profileHasIptvSources(null), isFalse);

    await settings.write(SettingsService.iptvSourcesForProfile('p'), '[]');
    expect(profileHasIptvSources('p'), isFalse);

    await settings.write(SettingsService.iptvSourcesForProfile('p'), 'not json');
    expect(profileHasIptvSources('p'), isFalse);

    await settings.write(SettingsService.iptvSourcesForProfile('p'), '[{"id":"src"}]');
    expect(profileHasIptvSources('p'), isTrue);
    expect(profileHasIptvSources('someone-else'), isFalse);
  });

  test('the setup is not yet done on a fresh install', () {
    expect(SettingsService.instance.read(SettingsService.onboardingCompleted), isFalse);
  });

  Future<void> pump(WidgetTester tester, Widget home, {IptvSourcesProvider? iptv}) async {
    tester.view.physicalSize = const Size(1280, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final trackers = TrackersProvider();
    addTearDown(trackers.dispose);
    await tester.pumpWidget(
      TranslationProvider(
        child: MultiProvider(
          providers: [
            ChangeNotifierProvider<TrackersProvider>.value(value: trackers),
            if (iptv != null) ChangeNotifierProvider<IptvSourcesProvider>.value(value: iptv),
          ],
          child: MaterialApp(theme: monoTheme(dark: true), home: home),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('welcome leads on to the look', (tester) async {
    await pump(tester, const SetupWelcomeScreen());
    expect(find.text(t.plebz.welcomeTitle), findsOneWidget);

    await tester.tap(find.text(t.plebz.getStarted));
    await tester.pumpAndSettle();

    expect(find.text(t.plebz.lookTitle), findsOneWidget);
    expect(find.text(t.settings.appThemeVariant), findsOneWidget);
    expect(find.text(t.settings.theme), findsOneWidget);
  });

  testWidgets('run again, the look leads on to the extras', (tester) async {
    await pump(tester, const SetupLookScreen(firstRun: false));

    await tester.tap(find.text(t.plebz.next));
    await tester.pumpAndSettle();

    expect(find.text(t.plebz.extrasTitle), findsOneWidget);
    expect(find.text(t.plebz.sourcesGroup), findsOneWidget);
    expect(find.text(t.settings.showSportTab), findsOneWidget);
  });

  testWidgets('the extras cannot be finished without a source to watch from', (tester) async {
    await pump(tester, const SetupExtrasScreen());

    expect(find.text(t.plebz.addSourceFirst), findsOneWidget);
    final done = tester.widget<FilledButton>(find.widgetWithText(FilledButton, t.plebz.finish));
    expect(done.onPressed, isNull);
    expect(SettingsService.instance.read(SettingsService.onboardingCompleted), isFalse);
  });

  testWidgets('the extras say how several viewers keep their own progress', (tester) async {
    await pump(tester, const SetupExtrasScreen());

    expect(find.text(t.plebz.profilesGroup), findsOneWidget);
    expect(find.text(t.plebz.profilesHint), findsOneWidget);
    // Without Simkl connected there is no switch yet, only the way to it.
    expect(find.text(t.plebz.profilesHintConnectFirst), findsOneWidget);
    expect(find.text(t.services.ownProgress), findsNothing);
  });

  testWidgets('with a playlist in place, "Done" finishes the setup', (tester) async {
    final iptv = IptvSourcesProvider(profileId: 'p', buildSource: (_) => throw UnimplementedError());
    addTearDown(iptv.dispose);
    // Saving seals the playlist address with the vault, which works on real
    // time rather than the test's clock.
    await tester.runAsync(
      () => iptv.save(
        const IptvSource(
          id: 'src',
          name: 'Playlist',
          kind: IptvSourceKind.m3u,
          playlistUrl: 'http://provider/list.m3u',
        ),
      ),
    );

    await pump(
      tester,
      Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () =>
                Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const SetupExtrasScreen())),
            child: const Text('open'),
          ),
        ),
      ),
      iptv: iptv,
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text(t.plebz.addSourceFirst), findsNothing);

    await tester.tap(find.widgetWithText(FilledButton, t.plebz.finish));
    await tester.pumpAndSettle();

    expect(SettingsService.instance.read(SettingsService.onboardingCompleted), isTrue);
    expect(find.text(t.plebz.extrasTitle), findsNothing);
  });
}
