import 'package:flutter/foundation.dart';

import '../../media/media_item.dart';

/// Who keeps the active profile's watch state (fork addition).
enum ProgressSourceKind {
  /// The media server: what Plex, Jellyfin or Emby say is watched and where
  /// playback stopped. Every profile's default, and the app as upstream has it.
  server,

  /// A tracker account of the profile's own. The servers are only libraries
  /// then: their answers are overlaid with the tracker's state, and watched
  /// marks are not written to them, so several profiles can share one server
  /// account and still keep their own progress.
  tracker,
}

/// The watch state a tracker-led profile lays over what the servers say.
abstract interface class WatchStateOverlay {
  /// [item] as this profile has watched it; [item] itself where the tracker
  /// knows nothing about it. Must keep [item]'s runtime type.
  MediaItem apply(MediaItem item);
}

/// The one place that says where the active profile's watch state lives
/// (fork addition).
///
/// Read by the item mappers of every backend ([overlay]) and by the backends'
/// watched marks ([serverKeepsWatchState]). With the server in charge — the
/// default, and the only state until a profile chooses a tracker — both are
/// pass-throughs: [overlay] hands back the very item it was given, and the
/// marks go to the server as they always did.
class ProgressRouting {
  ProgressRouting._();

  static final ProgressRouting instance = ProgressRouting._();

  ProgressSourceKind _source = ProgressSourceKind.server;
  WatchStateOverlay? _overlay;

  ProgressSourceKind get source => _source;

  /// Whether watched marks and Continue Watching removals belong on the
  /// server. False while a tracker keeps the profile's progress: the server
  /// account may be shared, and another profile's state is not this one's to
  /// change.
  bool get serverKeepsWatchState => _source == ProgressSourceKind.server;

  /// Hand over to [source]; [overlay] is the tracker's state for a tracker
  /// source and ignored for the server.
  void activate(ProgressSourceKind source, {WatchStateOverlay? overlay}) {
    _source = source;
    _overlay = source == ProgressSourceKind.tracker ? overlay : null;
  }

  /// Told of each watch change made in this app — a mark, or where playback
  /// was left — while a tracker keeps the state, so the change shows before
  /// the tracker echoes it. Set by whoever keeps the tracker's state.
  void Function(MediaItem item, {bool? watched, int? offsetMs})? onLocalChange;

  /// Called by [WatchStateNotifier] for every watched mark and progress event.
  void noteLocalChange(MediaItem item, {bool? watched, int? offsetMs}) {
    if (_source != ProgressSourceKind.tracker) return;
    onLocalChange?.call(item, watched: watched, offsetMs: offsetMs);
  }

  /// [item] with the active profile's watch state: unchanged — the same
  /// object — while the server keeps it.
  static T overlay<T extends MediaItem>(T item) {
    final overlay = instance._overlay;
    if (overlay == null) return item;
    final applied = overlay.apply(item);
    return applied is T ? applied : item;
  }

  @visibleForTesting
  void debugReset() {
    activate(ProgressSourceKind.server);
    onLocalChange = null;
  }
}
