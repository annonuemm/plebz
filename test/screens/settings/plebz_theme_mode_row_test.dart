import 'package:flutter/material.dart' hide ThemeMode;
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/i18n/strings.g.dart';
import 'package:plezy/screens/settings/plebz_settings_rows.dart';
import 'package:plezy/services/settings_service.dart';
import 'package:plezy/theme/mono_theme.dart';

import '../../test_helpers/prefs.dart';

/// "Hell oder dunkel" means something in the other designs and nothing in the
/// redesign, which has no light half. There the same row chooses the ground
/// instead: the palette's own, or black for an OLED screen.
void main() {
  setUpAll(() => LocaleSettings.setLocaleSync(AppLocale.en));

  setUp(() async {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    await SettingsService.getInstance();
    debugRedesignOfferedHere = true;
  });

  tearDown(() {
    debugRedesignOfferedHere = null;
    SettingsService.resetForTesting();
  });

  Future<void> pumpRow(WidgetTester tester) async {
    await tester.pumpWidget(
      TranslationProvider(
        child: MaterialApp(home: Scaffold(body: plebzThemeModeRow())),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> pick(WidgetTester tester, String option) async {
    await tester.tap(find.text(t.settings.glasGround));
    await tester.pumpAndSettle();
    await tester.tap(find.text(option).last);
    await tester.pumpAndSettle();
  }

  ThemeMode stored() => SettingsService.instance.read(SettingsService.themeMode);

  testWidgets('the other designs keep light, dark, OLED and system', (tester) async {
    await SettingsService.instance.write(SettingsService.appThemeVariant, AppThemeVariant.standard);
    await pumpRow(tester);

    expect(find.text(t.settings.theme), findsOneWidget);
    expect(find.text(t.settings.glasGround), findsNothing);

    await tester.tap(find.text(t.settings.theme));
    await tester.pumpAndSettle();
    for (final label in [t.settings.systemTheme, t.settings.lightTheme, t.settings.darkTheme, t.settings.oledTheme]) {
      expect(find.text(label), findsWidgets);
    }
  });

  testWidgets('the redesign offers its own ground or black, and OLED is the one stored choice', (tester) async {
    await SettingsService.instance.write(SettingsService.appThemeVariant, AppThemeVariant.glas);
    await SettingsService.instance.write(SettingsService.themeMode, ThemeMode.system);
    await pumpRow(tester);

    expect(find.text(t.settings.theme), findsNothing);
    expect(find.text(t.settings.glasGroundAccent), findsOneWidget, reason: 'not OLED, so the palette\'s own');

    await pick(tester, t.settings.glasGroundAccent);
    expect(stored(), ThemeMode.system, reason: 'choosing what is already on changes nothing');

    await pick(tester, t.settings.glasGroundOled);
    expect(stored(), ThemeMode.oled);
    expect(find.text(t.settings.glasGroundOled), findsOneWidget);

    await pick(tester, t.settings.glasGroundAccent);
    expect(stored(), ThemeMode.dark, reason: 'leaving OLED settles on dark');
  });

  testWidgets('a viewer who already has OLED sees it named under the redesign', (tester) async {
    await SettingsService.instance.write(SettingsService.appThemeVariant, AppThemeVariant.glas);
    await SettingsService.instance.write(SettingsService.themeMode, ThemeMode.oled);
    await pumpRow(tester);

    expect(find.text(t.settings.glasGroundOled), findsOneWidget);
    expect(find.text(t.settings.glasGroundAccent), findsNothing);
  });
}
