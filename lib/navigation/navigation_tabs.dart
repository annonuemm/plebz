import 'package:flutter/material.dart';
import 'package:plezy/widgets/app_icon.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../i18n/strings.g.dart';
import '../utils/platform_detector.dart';

/// Navigation tab identifiers
enum NavigationTabId { discover, watchlist, explore, sport, libraries, liveTv, search, downloads, settings }

/// How navigation draws its icons, wherever it is drawn — the side rail, the
/// mobile rail and the bottom bar all read these.
///
/// Outlines only, at the font's regular weight rather than the app-wide bold:
/// a rail of solid 700 glyphs turns into a column of blobs at a television's
/// viewing distance, and the shape is the only thing that says which
/// destination this is. Selection is carried by colour and the active
/// indicator, not by a second, filled glyph.
const double navIconFill = 0;
const double navIconWeight = 400;

/// Represents a navigation tab with its configuration
class NavigationTab {
  final NavigationTabId id;
  final bool onlineOnly;
  final IconData icon;
  final String Function() getLabel;

  const NavigationTab({required this.id, required this.onlineOnly, required this.icon, required this.getLabel});

  /// A bottom-bar destination whose label is pinned to one line.
  ///
  /// [NavigationDestination] paints a bare [Text] that fills the destination's
  /// share of the bar with no horizontal padding, so a long localized label or
  /// an enlarged system font wraps and the wrapped destination's icon rides up
  /// out of line with its siblings (#2316, #2281). The clamp has to sit here,
  /// on the destination: [NavigationBar]'s own [Material] reinstalls the
  /// ambient text style, so a [DefaultTextStyle] wrapped around the whole bar
  /// never reaches the labels. [NavigationLabelScale] shrinks the text so the
  /// full word usually still fits before this ellipsis applies.
  Widget toDestination() {
    final glyph = AppIcon(icon, fill: navIconFill, weight: navIconWeight);
    return DefaultTextStyle.merge(
      maxLines: 1,
      softWrap: false,
      overflow: TextOverflow.ellipsis,
      child: NavigationDestination(icon: glyph, selectedIcon: glyph, label: getLabel()),
    );
  }

  /// The glyph for [id], so every navigation surface draws the same set.
  static IconData iconFor(NavigationTabId id) => allNavigationTabs.firstWhere((tab) => tab.id == id).icon;

  /// Get tabs filtered by offline mode and feature availability
  static List<NavigationTab> getVisibleTabs({
    required bool isOffline,
    bool hasLiveTv = false,
    bool hasExplore = false,
    bool hasWatchlist = false,
    bool showDownloads = true,
    bool showSport = false,
  }) {
    return allNavigationTabs.where((tab) {
      if (isOffline && tab.onlineOnly) return false;
      if (tab.id == NavigationTabId.liveTv && !hasLiveTv) return false;
      if (tab.id == NavigationTabId.explore && !hasExplore) return false;
      if (tab.id == NavigationTabId.watchlist && !hasWatchlist) return false;
      if (tab.id == NavigationTabId.sport && !showSport) return false;
      // Switched off, the section goes with the buttons — except offline,
      // where downloads are the only thing left to watch and hiding them
      // would leave the app with nothing to show.
      if (tab.id == NavigationTabId.downloads && !showDownloads && !isOffline) return false;
      if (tab.id == NavigationTabId.downloads && PlatformDetector.isAppleTV()) return false;
      return true;
    }).toList();
  }

  /// Resolve which tab the app should open to on launch.
  ///
  /// Offline mode prefers Downloads when available. Online, honours the user's
  /// [preferredStartup] section when it is currently visible, otherwise falls
  /// back to the first visible tab (Home).
  static NavigationTabId resolveDefaultTab({
    required bool isOffline,
    required bool hasLiveTv,
    bool hasExplore = false,
    bool hasWatchlist = false,
    bool showDownloads = true,
    bool showSport = false,
    required NavigationTabId? preferredStartup,
  }) {
    final tabs = getVisibleTabs(
      isOffline: isOffline,
      hasLiveTv: hasLiveTv,
      hasExplore: hasExplore,
      hasWatchlist: hasWatchlist,
      showDownloads: showDownloads,
      showSport: showSport,
    );
    if (isOffline && tabs.any((t) => t.id == NavigationTabId.downloads)) {
      return NavigationTabId.downloads;
    }
    if (preferredStartup != null && tabs.any((t) => t.id == preferredStartup)) {
      return preferredStartup;
    }
    return tabs.first.id;
  }
}

// Label getters (must be top-level for const constructor)
String _getHomeLabel() => t.common.home;
String _getWatchlistLabel() => t.explore.rows.watchlist;
String _getExploreLabel() => t.navigation.explore;
String _getSportLabel() => t.navigation.sport;
String _getLibrariesLabel() => t.navigation.libraries;
String _getLiveTvLabel() => t.navigation.liveTv;
String _getSearchLabel() => t.common.search;
String _getDownloadsLabel() => t.navigation.downloads;
String _getSettingsLabel() => t.common.settings;

/// All navigation tabs in display order
const allNavigationTabs = [
  NavigationTab(id: NavigationTabId.discover, onlineOnly: true, icon: Symbols.home_rounded, getLabel: _getHomeLabel),
  NavigationTab(
    id: NavigationTabId.watchlist,
    onlineOnly: true,
    icon: Symbols.bookmark_rounded,
    getLabel: _getWatchlistLabel,
  ),
  NavigationTab(
    id: NavigationTabId.libraries,
    onlineOnly: true,
    // A grid, not the video-library stack: the libraries hold music and
    // photos too, and the stack-with-a-play-triangle was the same silhouette
    // as Live TV's screen one row below it.
    icon: Symbols.grid_view_rounded,
    getLabel: _getLibrariesLabel,
  ),
  // Explore before Live TV: the viewer's own titles, then the ones found
  // elsewhere, then what is on air (the user's order).
  NavigationTab(
    id: NavigationTabId.explore,
    onlineOnly: true,
    icon: Symbols.explore_rounded,
    getLabel: _getExploreLabel,
  ),
  NavigationTab(id: NavigationTabId.liveTv, onlineOnly: true, icon: Symbols.live_tv_rounded, getLabel: _getLiveTvLabel),
  // Straight after Live TV, in both the rail and the header: its matches are
  // live broadcasts, and the match window leads to the channels showing them.
  NavigationTab(
    id: NavigationTabId.sport,
    onlineOnly: true,
    icon: Symbols.sports_soccer_rounded,
    getLabel: _getSportLabel,
  ),
  NavigationTab(id: NavigationTabId.search, onlineOnly: true, icon: Symbols.search_rounded, getLabel: _getSearchLabel),
  NavigationTab(
    id: NavigationTabId.downloads,
    onlineOnly: false,
    icon: Symbols.download_rounded,
    getLabel: _getDownloadsLabel,
  ),
  NavigationTab(
    id: NavigationTabId.settings,
    onlineOnly: false,
    icon: Symbols.settings_rounded,
    getLabel: _getSettingsLabel,
  ),
];
