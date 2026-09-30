import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:plezy/i18n/strings.g.dart';
import 'package:plezy/screens/settings/about_screen.dart';
import 'package:plezy/services/settings_service.dart';
import 'package:plezy/theme/mono_theme.dart';
import 'package:plezy/utils/fork_identity.dart';

import '../../test_helpers/prefs.dart';

/// The About page is where the app says whose it is and on what terms: the
/// fork's name rather than Plezy's, the GPL notices, and TMDB's attribution.
void main() {
  setUpAll(() {
    LocaleSettings.setLocaleSync(AppLocale.en);
    registerForkLicense();
  });

  setUp(() async {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    await SettingsService.getInstance();
    PackageInfo.setMockInitialValues(
      appName: 'Plebz',
      packageName: 'app.plebz',
      version: '1.0.0',
      buildNumber: '549',
      buildSignature: '',
    );
  });

  tearDown(SettingsService.resetForTesting);

  Future<void> pumpAbout(WidgetTester tester) async {
    await tester.pumpWidget(
      TranslationProvider(
        child: MaterialApp(
          theme: monoTheme(dark: true).copyWith(platform: TargetPlatform.android),
          home: const AboutScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets("names the fork, not Plezy, and shows no Plezy logo", (tester) async {
    await pumpAbout(tester);

    expect(find.text(forkAppName), findsOneWidget);
    expect(find.text('Plezy'), findsNothing);
    // Its own version, and the Plezy release it is built on beside it.
    expect(find.text(t.about.versionLabel(version: '1.0.0')), findsOneWidget);
    expect(find.text(t.about.basedOnUpstream(version: upstreamBaseVersion)), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (w) => w is Image && w.image is AssetImage && (w.image as AssetImage).assetName.contains('plezy'),
      ),
      findsNothing,
    );
  });

  testWidgets('carries the GPL notices: copyright, no warranty, the licence and where to read it', (tester) async {
    await pumpAbout(tester);

    final notice = t.about.appLicenseNotice(app: forkAppName);
    expect(find.text(t.about.appLicense), findsOneWidget);
    expect(find.text(notice), findsOneWidget);
    expect(notice, contains('Copyright'));
    expect(notice, contains('NO WARRANTY'));
    expect(notice, contains('GNU General Public License, version 3'));
  });

  testWidgets('the licence tile opens the GPL text itself', (tester) async {
    await pumpAbout(tester);

    await tester.tap(find.text(t.about.appLicense));
    await tester.pumpAndSettle();

    expect(find.textContaining('GNU GENERAL PUBLIC LICENSE'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets("shows TMDB's logo and its attribution sentence word for word", (tester) async {
    await pumpAbout(tester);

    expect(find.text('This product uses the TMDB API but is not endorsed or certified by TMDB.'), findsOneWidget);
    expect(find.byType(SvgPicture), findsOneWidget);
  });
}
