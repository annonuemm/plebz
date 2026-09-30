import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/navigation/navigation_tabs.dart';

void main() {
  group('NavigationTab.resolveDefaultTab', () {
    test('offline prefers Downloads when available', () {
      expect(
        NavigationTab.resolveDefaultTab(isOffline: true, hasLiveTv: false, preferredStartup: null),
        NavigationTabId.downloads,
      );
    });

    test('offline ignores an online-only preferred section', () {
      expect(
        NavigationTab.resolveDefaultTab(isOffline: true, hasLiveTv: true, preferredStartup: NavigationTabId.liveTv),
        NavigationTabId.downloads,
      );
    });

    test('online honours the preferred section when it is visible', () {
      expect(
        NavigationTab.resolveDefaultTab(isOffline: false, hasLiveTv: true, preferredStartup: NavigationTabId.liveTv),
        NavigationTabId.liveTv,
      );
      expect(
        NavigationTab.resolveDefaultTab(isOffline: false, hasLiveTv: false, preferredStartup: NavigationTabId.search),
        NavigationTabId.search,
      );
    });

    test('online falls back to Home when preferred Live TV is unavailable', () {
      expect(
        NavigationTab.resolveDefaultTab(isOffline: false, hasLiveTv: false, preferredStartup: NavigationTabId.liveTv),
        NavigationTabId.discover,
      );
    });

    test('online defaults to Home when no preference is set', () {
      expect(
        NavigationTab.resolveDefaultTab(isOffline: false, hasLiveTv: true, preferredStartup: null),
        NavigationTabId.discover,
      );
    });

    test('online falls back to Home when preferred Explore is unavailable', () {
      expect(
        NavigationTab.resolveDefaultTab(isOffline: false, hasLiveTv: false, preferredStartup: NavigationTabId.explore),
        NavigationTabId.discover,
      );
      expect(
        NavigationTab.resolveDefaultTab(
          isOffline: false,
          hasLiveTv: false,
          hasExplore: true,
          preferredStartup: NavigationTabId.explore,
        ),
        NavigationTabId.explore,
      );
    });
  });

  group('NavigationTab.getVisibleTabs', () {
    test('hides Explore until a catalog source is connected', () {
      final without = NavigationTab.getVisibleTabs(isOffline: false);
      expect(without.map((tab) => tab.id), isNot(contains(NavigationTabId.explore)));

      final with_ = NavigationTab.getVisibleTabs(isOffline: false, hasExplore: true, hasLiveTv: true);
      final ids = with_.map((tab) => tab.id).toList();
      expect(ids, contains(NavigationTabId.explore));
      // Explore sits right after the libraries, directly before Live TV.
      expect(ids.indexOf(NavigationTabId.explore), ids.indexOf(NavigationTabId.libraries) + 1);
      expect(ids.indexOf(NavigationTabId.explore), ids.indexOf(NavigationTabId.liveTv) - 1);
    });

    test('Explore is online-only', () {
      final offline = NavigationTab.getVisibleTabs(isOffline: true, hasExplore: true);
      expect(offline.map((tab) => tab.id), isNot(contains(NavigationTabId.explore)));
    });

    test('the download switch takes the Downloads section with it', () {
      expect(
        NavigationTab.getVisibleTabs(isOffline: false, showDownloads: false).map((tab) => tab.id),
        isNot(contains(NavigationTabId.downloads)),
      );
      expect(NavigationTab.getVisibleTabs(isOffline: false).map((tab) => tab.id), contains(NavigationTabId.downloads));
    });

    test('offline keeps Downloads whatever the switch says', () {
      // Offline it is the only thing left to watch; hiding it would leave the
      // app with nothing to show.
      expect(
        NavigationTab.getVisibleTabs(isOffline: true, showDownloads: false).map((tab) => tab.id),
        contains(NavigationTabId.downloads),
      );
      expect(
        NavigationTab.resolveDefaultTab(
          isOffline: true,
          hasLiveTv: false,
          showDownloads: false,
          preferredStartup: null,
        ),
        NavigationTabId.downloads,
      );
    });

    test('hides Watchlist until a source with a watchlist is connected', () {
      final without = NavigationTab.getVisibleTabs(isOffline: false);
      expect(without.map((tab) => tab.id), isNot(contains(NavigationTabId.watchlist)));

      final with_ = NavigationTab.getVisibleTabs(isOffline: false, hasWatchlist: true);
      expect(with_.map((tab) => tab.id), contains(NavigationTabId.watchlist));
    });

    test('Watchlist sits directly under Home', () {
      final ids = NavigationTab.getVisibleTabs(
        isOffline: false,
        hasWatchlist: true,
        hasExplore: true,
        hasLiveTv: true,
      ).map((tab) => tab.id).toList();

      expect(ids.indexOf(NavigationTabId.watchlist), ids.indexOf(NavigationTabId.discover) + 1);
    });

    test('Watchlist does not depend on the Explore tab being shown', () {
      final ids = NavigationTab.getVisibleTabs(isOffline: false, hasWatchlist: true).map((tab) => tab.id).toList();

      expect(ids, contains(NavigationTabId.watchlist));
      expect(ids, isNot(contains(NavigationTabId.explore)));
    });

    test('Watchlist is online-only', () {
      final offline = NavigationTab.getVisibleTabs(isOffline: true, hasWatchlist: true);
      expect(offline.map((tab) => tab.id), isNot(contains(NavigationTabId.watchlist)));
    });

    test('Sport is shown only when switched on', () {
      expect(
        NavigationTab.getVisibleTabs(isOffline: false, hasExplore: true).map((tab) => tab.id),
        isNot(contains(NavigationTabId.sport)),
      );
      expect(
        NavigationTab.getVisibleTabs(isOffline: false, showSport: true).map((tab) => tab.id),
        contains(NavigationTabId.sport),
        reason: 'it needs no server or catalog source — only the switch',
      );
    });

    test('Sport sits directly after Live TV', () {
      final ids = NavigationTab.getVisibleTabs(
        isOffline: false,
        hasExplore: true,
        hasLiveTv: true,
        hasWatchlist: true,
        showSport: true,
      ).map((tab) => tab.id).toList();

      expect(ids.indexOf(NavigationTabId.sport), ids.indexOf(NavigationTabId.liveTv) + 1);
    });

    test('Sport is online-only', () {
      expect(
        NavigationTab.getVisibleTabs(isOffline: true, showSport: true).map((tab) => tab.id),
        isNot(contains(NavigationTabId.sport)),
      );
    });
  });

  group('icons', () {
    test('every destination has a glyph, and no two share one', () {
      final icons = {for (final id in NavigationTabId.values) id: NavigationTab.iconFor(id)};

      expect(icons.length, NavigationTabId.values.length);
      expect(
        icons.values.toSet().length,
        NavigationTabId.values.length,
        reason: 'a rail of destinations is read by silhouette; two the same is a bug',
      );
    });
  });
}
