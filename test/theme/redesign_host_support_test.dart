import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/providers/theme_provider.dart';
import 'package:plezy/services/settings_service.dart' as settings;
import 'package:plezy/theme/mono_theme.dart';
import 'package:plezy/theme/mono_tokens.dart';

import '../test_helpers/prefs.dart';

/// The redesign is a television interface, and the macOS build is a window
/// with a mouse. It is left out there — not merely hidden from the list: a
/// value that reaches a Mac some other way (a restored backup, a copied
/// preference file) has to settle on the standard theme too, or the Mac paints
/// a remote-driven interface nobody can drive.
void main() {
  setUp(resetSharedPreferencesForTest);
  tearDown(() => debugRedesignOfferedHere = null);

  group('where the redesign is offered', () {
    test('every variant is on the list', () {
      debugRedesignOfferedHere = true;

      expect(offeredAppThemeVariants, settings.AppThemeVariant.values);
      for (final variant in settings.AppThemeVariant.values) {
        expect(supportedAppThemeVariant(variant), variant);
      }
    });
  });

  group('where it is not', () {
    setUp(() => debugRedesignOfferedHere = false);

    test('only the two variants that are not the redesign can be chosen', () {
      expect(offeredAppThemeVariants, [settings.AppThemeVariant.standard, settings.AppThemeVariant.klar]);
    });

    test('a redesign palette carried in from elsewhere reads as standard', () {
      expect(supportedAppThemeVariant(settings.AppThemeVariant.glas), settings.AppThemeVariant.standard);
      expect(supportedAppThemeVariant(settings.AppThemeVariant.glas), settings.AppThemeVariant.standard);
      expect(supportedAppThemeVariant(settings.AppThemeVariant.glas), settings.AppThemeVariant.standard);
    });

    test('the two that remain are untouched', () {
      expect(supportedAppThemeVariant(settings.AppThemeVariant.klar), settings.AppThemeVariant.klar);
      expect(supportedAppThemeVariant(settings.AppThemeVariant.standard), settings.AppThemeVariant.standard);
    });

    test('a stored redesign variant is drawn as the standard theme', () async {
      final service = await settings.SettingsService.getInstance();
      await service.write(settings.SettingsService.appThemeVariant, settings.AppThemeVariant.glas);

      final provider = ThemeProvider();
      await Future.delayed(Duration.zero);

      expect(provider.variant, settings.AppThemeVariant.standard);
      // And the theme really is the plain one — the redesign changes where
      // navigation lives, so a half-applied answer would be worse than none.
      expect(provider.darkTheme.extension<MonoTokens>()?.redesignLayout, isNot(true));
      // The stored value is deliberately left alone: the same profile still
      // opens in the redesign on the television it was set from.
      expect(service.read(settings.SettingsService.appThemeVariant), settings.AppThemeVariant.glas);

      provider.dispose();
    });
  });
}
