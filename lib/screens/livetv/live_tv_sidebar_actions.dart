import 'package:flutter/foundation.dart';

/// What the sidebar can do to the Live TV screen on its behalf.
///
/// The channel arrangement, the favourites filter and the reload used to sit
/// in the screen's own app bar. On a television that bar costs a whole row for
/// three icons, and the sidebar already has room — so the screen offers them
/// here and the rail calls them, the way it reaches any other screen it must
/// speak to.
abstract interface class LiveTvSidebarActions {
  /// Fires when any of the answers below change, so the rail can redraw the
  /// rows. Without it the star would keep the shape it had when the sidebar
  /// was last built for another reason.
  Listenable get sidebarRevision;

  /// Whether an arrangement can be edited at all: it needs loaded channels and
  /// somewhere to store the order.
  bool get canManageChannels;

  /// Whether the guide is currently showing favourites only.
  bool get showsFavoritesOnly;

  /// Whether reordering is on offer: only with favourites shown and more than
  /// one of them.
  bool get canReorderFavorites;

  void openChannelManagement();
  void toggleFavoritesFilter();
  void reorderFavorites();
  void reloadLiveTv();
}
