import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/services/settings_service.dart';

import '../test_helpers/prefs.dart';

void main() {
  setUp(resetSharedPreferencesForTest);

  test('Continue Watching follows the app-wide picture until it gets its own', () async {
    final settings = await SettingsService.getInstance();
    expect(settings.read(PlebzPrefs.continueWatchingPosterMode), ContinueWatchingPosterMode.sameAsEverywhere);

    for (final everywhere in EpisodePosterMode.values) {
      await settings.write(SettingsService.episodePosterMode, everywhere);
      expect(PlebzPrefs.continueWatchingEpisodePosterMode(settings), everywhere);
    }
  });

  test('its own choice wins over the app-wide one, and leaves that one alone', () async {
    final settings = await SettingsService.getInstance();
    await settings.write(SettingsService.episodePosterMode, EpisodePosterMode.seriesPoster);

    const expected = {
      ContinueWatchingPosterMode.seriesPoster: EpisodePosterMode.seriesPoster,
      ContinueWatchingPosterMode.seasonPoster: EpisodePosterMode.seasonPoster,
      ContinueWatchingPosterMode.episodeThumbnail: EpisodePosterMode.episodeThumbnail,
    };
    for (final MapEntry(key: own, value: mode) in expected.entries) {
      await settings.write(PlebzPrefs.continueWatchingPosterMode, own);
      expect(PlebzPrefs.continueWatchingEpisodePosterMode(settings), mode);
      expect(settings.read(SettingsService.episodePosterMode), EpisodePosterMode.seriesPoster);
    }
  });

  test('the choice travels with the settings backup', () {
    expect(PlebzPrefs.resetAndPortable, contains(PlebzPrefs.continueWatchingPosterMode));
  });
}
