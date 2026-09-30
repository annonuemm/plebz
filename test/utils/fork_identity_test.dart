import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/i18n/strings.g.dart';
import 'package:plezy/providers/trackers_provider.dart';
import 'package:plezy/screens/settings/tracker_service_info.dart';
import 'package:plezy/services/base_shared_preferences_service.dart';
import 'package:plezy/services/trackers/tracker_account_store.dart';
import 'package:plezy/services/trackers/tracker_constants.dart';
import 'package:plezy/services/trackers/tracker_session.dart';
import 'package:plezy/utils/fork_identity.dart';

import '../test_helpers/prefs.dart';

/// Simkl, MyAnimeList and AniList sign in through Plezy's developer's OAuth
/// proxy and identify as Plezy's registered apps, so this fork leaves them out.
void main() {
  setUpAll(() => LocaleSettings.setLocaleSync(AppLocale.en));

  setUp(() {
    resetSharedPreferencesForTest();
    debugRemovedTrackersAvailable = false;
  });

  test('the three are out, Trakt and MDBList stay', () {
    expect(forkRemovedTrackers, {TrackerService.simkl, TrackerService.mal, TrackerService.anilist});
    for (final service in TrackerService.values) {
      expect(isTrackerAvailable(service), !forkRemovedTrackers.contains(service), reason: service.name);
    }
  });

  test('settings offer none of them', () {
    final offered = TrackerServiceInfo.all.map((info) => info.service).toSet();

    expect(offered.intersection(forkRemovedTrackers), isEmpty);
    expect(offered, containsAll({TrackerService.trakt, TrackerService.mdblist}));
  });

  test('a session stored before is not loaded, so nothing talks to them', () async {
    const uuid = 'profile-1';
    TrackerSession session(String name) => TrackerSession(
      accessToken: '$name-at',
      refreshToken: '$name-rt',
      expiresAt: 2000000000,
      createdAt: 1900000000,
      username: name,
    );
    await trackerAccountStore(TrackerService.simkl).save(uuid, session('simkl'));
    await trackerAccountStore(TrackerService.mal).save(uuid, session('mal'));
    await trackerAccountStore(TrackerService.anilist).save(uuid, session('anilist'));
    await trackerAccountStore(TrackerService.mdblist).save(uuid, session('mdblist'));
    BaseSharedPreferencesService.resetForTesting();

    final provider = TrackersProvider();
    addTearDown(provider.dispose);
    // Unbind the tracker singletons again before the provider goes away.
    addTearDown(() => provider.onActiveProfileChanged('teardown-profile'));
    await provider.onActiveProfileChanged(uuid);

    expect(provider.isSimklConnected, isFalse);
    expect(provider.isMalConnected, isFalse);
    expect(provider.isAnilistConnected, isFalse);
    expect(provider.simklCatalogClient, isNull);
    expect(provider.malCatalogClient, isNull);
    expect(provider.anilistCatalogClient, isNull);
    // The machinery itself still works for the services that stay.
    expect(provider.isMdblistConnected, isTrue);
    expect(provider.mdblistUsername, 'mdblist');
  });
}
