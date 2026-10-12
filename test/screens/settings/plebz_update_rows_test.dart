import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/i18n/strings.g.dart';
import 'package:plezy/screens/settings/plebz_updates.dart';
import 'package:plezy/services/plebz_update_service.dart';
import 'package:plezy/services/settings_service.dart';
import 'package:plezy/theme/mono_theme.dart';
import 'package:plezy/utils/fork_identity.dart';
import 'package:plezy/widgets/settings_builder.dart';

import '../../test_helpers/prefs.dart';

/// "Updates anbieten" (Plebz): how often the start-up check shows an update,
/// a row only while that check is on, in every look.
void main() {
  setUpAll(() => LocaleSettings.setLocaleSync(AppLocale.en));

  setUp(() async {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    await SettingsService.getInstance();
    debugPlebzUpdatesAvailable = true;
  });

  tearDown(() {
    debugPlebzUpdatesAvailable = null;
    SettingsService.resetForTesting();
  });

  Future<void> pumpRows(WidgetTester tester, AppThemeVariant variant) async {
    await tester.pumpWidget(
      TranslationProvider(
        child: MaterialApp(
          theme: monoTheme(dark: true, variant: variant),
          home: Scaffold(
            body: SettingsBuilder(
              prefs: const [SettingsService.autoCheckUpdatesOnStartup],
              builder: (context) => ListView(children: plebzUpdateRows(context)),
            ),
          ),
        ),
      ),
    );
    // A theme swap animates.
    await tester.pump(const Duration(seconds: 1));
  }

  for (final variant in AppThemeVariant.values) {
    testWidgets('${variant.name}: shown under the start-up check, gone when it is off', (tester) async {
      await pumpRows(tester, variant);

      expect(find.text(t.plebz.updateOffer), findsOneWidget);
      expect(
        find.text('${t.plebz.updateOfferWhenAvailable} · ${t.plebz.updateOfferDescription}'),
        findsOneWidget,
        reason: 'the default keeps today\'s behaviour',
      );

      await SettingsService.instance.write(SettingsService.autoCheckUpdatesOnStartup, false);
      await tester.pump();
      expect(find.text(t.plebz.updateOffer), findsNothing);
    });
  }

  testWidgets('offers the four spacings and keeps the pick', (tester) async {
    await pumpRows(tester, AppThemeVariant.glas);

    await tester.tap(find.text(t.plebz.updateOffer));
    await tester.pumpAndSettle();
    for (final label in [
      t.plebz.updateOfferWhenAvailable,
      t.plebz.updateOfferWeekly,
      t.plebz.updateOfferBiweekly,
      t.plebz.updateOfferMonthly,
    ]) {
      expect(find.text(label), findsWidgets);
    }

    await tester.tap(find.text(t.plebz.updateOfferMonthly).last);
    await tester.pumpAndSettle();
    expect(SettingsService.instance.read(PlebzPrefs.plebzUpdateOffer), PlebzUpdateOffer.monthly);
    expect(find.text('${t.plebz.updateOfferMonthly} · ${t.plebz.updateOfferDescription}'), findsOneWidget);
  });
}
