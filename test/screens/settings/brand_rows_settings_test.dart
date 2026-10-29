import 'package:flutter/material.dart' hide ThemeMode;
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/i18n/strings.g.dart';
import 'package:plezy/screens/settings/brand_rows_settings.dart';
import 'package:plezy/services/brand_rows_service.dart' show brandRowsLayout;
import 'package:plezy/services/settings_service.dart';
import 'package:plezy/services/streaming_brands.dart';
import 'package:plezy/theme/mono_theme.dart';

import '../../test_helpers/prefs.dart';

void main() {
  setUp(() async {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    await SettingsService.getInstance();
    LocaleSettings.setLocaleSync(AppLocale.en);
  });

  Future<void> pump(WidgetTester tester, Widget child, {AppThemeVariant variant = AppThemeVariant.standard}) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1000, 2000);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      MaterialApp(
        theme: monoTheme(MonoPalette.dark, variant: variant),
        home: Scaffold(body: child),
      ),
    );
    // A theme swap animates.
    await tester.pumpAndSettle(const Duration(seconds: 1));
  }

  for (final variant in AppThemeVariant.values) {
    testWidgets('the services and the place are asked only while the switch is on (${variant.name})', (tester) async {
      await pump(tester, ListView(children: brandRowsSettingsRows()), variant: variant);
      expect(find.text(t.settings.showBrandRows), findsOneWidget);
      expect(find.text(t.settings.brandRowsPick), findsNothing);
      expect(find.text(t.settings.brandRowsPosition), findsNothing);

      await SettingsService.instance.write(PlebzPrefs.showBrandRows, true);
      await tester.pumpAndSettle();
      expect(find.text(t.settings.brandRowsPick), findsOneWidget);
      expect(find.text('Netflix, Prime Video, Disney+, HBO Max, Apple TV'), findsOneWidget);
      expect(find.text(t.settings.brandRowsPosition), findsOneWidget);
      expect(find.text(t.settings.brandRowsPositionAfterRecommendations), findsOneWidget);
    });
  }

  testWidgets('the list shows every service and switches one on', (tester) async {
    await pump(tester, const BrandRowsManagementList(isDialog: false));
    for (final brand in StreamingBrand.values) {
      expect(find.text(brand.displayName), findsOneWidget, reason: brand.displayName);
    }

    // Paramount+ is the first one off by default.
    await tester.tap(find.byTooltip(t.settings.brandRowsShow).first);
    await tester.pumpAndSettle();
    expect(brandRowsLayout().isHidden(StreamingBrand.paramount), isFalse);

    await tester.tap(find.byTooltip(t.settings.brandRowsHide).first);
    await tester.pumpAndSettle();
    expect(brandRowsLayout().isHidden(StreamingBrand.netflix), isTrue);
  });
}
