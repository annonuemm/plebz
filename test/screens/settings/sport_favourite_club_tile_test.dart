import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/i18n/strings.g.dart';
import 'package:plezy/screens/settings/sport_favourite_club_tile.dart';
import 'package:plezy/services/settings_service.dart';
import 'package:plezy/theme/mono_theme.dart';

import '../../test_helpers/prefs.dart';
import '../../test_helpers/sport_fixtures.dart';

void main() {
  setUp(() async {
    LocaleSettings.setLocaleSync(AppLocale.en);
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    await SettingsService.getInstance();
  });

  final dortmund = openLigaTeam(7, 'Borussia Dortmund', shortName: 'Dortmund');
  final bayern = openLigaTeam(40, 'FC Bayern München', shortName: 'Bayern');

  FakeOpenLigaDb provider() {
    final now = DateTime.now().toUtc();
    final api = FakeOpenLigaDb({
      '/getmatchdata/bl1': [
        openLigaMatch(id: 401, matchday: 4, kickoffUtc: now.add(const Duration(days: 1)), home: bayern, away: dortmund),
      ],
      // The real table names a club in full, as here.
      '/getbltable/bl1/2026': [
        openLigaTableRow(40, 'FC Bayern München', points: 12),
        openLigaTableRow(7, 'Borussia Dortmund', points: 9),
      ],
    });
    api.routes['/getmatchdata/bl1/2026/4'] = api.routes['/getmatchdata/bl1'];
    return api;
  }

  testWidgets('the favourite club is chosen from the league\'s clubs and named on its row', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: monoTheme(dark: true),
        home: Scaffold(body: SportFavouriteClubTile(repository: provider().repository())),
      ),
    );
    expect(find.text(t.settings.sportFavouriteClubDescription), findsOneWidget, reason: 'none chosen yet');

    await tester.tap(find.text(t.settings.sportFavouriteClub));
    await tester.pumpAndSettle();
    expect(find.text(t.sport.bundesliga1), findsOneWidget, reason: 'the clubs under their league');
    expect(find.text(t.settings.sportFavouriteClubNone), findsOneWidget);

    await tester.tap(find.text('Borussia Dortmund'));
    await tester.pumpAndSettle();

    expect(SettingsService.instance.read(PlebzPrefs.sportFavouriteClub), 7);
    expect(SettingsService.instance.read(PlebzPrefs.sportFavouriteClubName), 'Borussia Dortmund');
    expect(find.text('Borussia Dortmund'), findsOneWidget, reason: 'the row names the club now');
  });
}
