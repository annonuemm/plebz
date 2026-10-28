import 'package:flutter/foundation.dart';

/// A `plebz://` link a launcher's home-row tile opens (Plebz), beside the older
/// `plebz://play` and `plebz://live`:
///
/// * `plebz://open?content_id=plezy_<server>_<item>` — the title's page
/// * `plebz://watchlist` — the Merkliste
/// * `plebz://sport` — Sport
/// * `plebz://now?id=<entry>` — what the "Jetzt live" tile with that id does
///   on the start page: tune the channel, or the game's channel or window
/// * `plebz://reminder?key=<key>` — the channel of a guide reminder (the
///   screensaver's "Erinnerung gesetzt")
sealed class HomeLink {
  const HomeLink();

  static const scheme = 'plebz';

  /// [link] as one of these, or null for anything else — `play` and `live`
  /// included, which have handlers of their own.
  static HomeLink? tryParse(String link) {
    final uri = Uri.tryParse(link);
    if (uri == null || uri.scheme != scheme) return null;
    String? query(String name) {
      final value = uri.queryParameters[name]?.trim();
      return value == null || value.isEmpty ? null : value;
    }

    return switch (uri.host) {
      'open' => switch (query('content_id')) {
        final id? => PlebzOpenLink(id),
        null => null,
      },
      'watchlist' => const PlebzWatchlistLink(),
      'sport' => const PlebzSportLink(),
      'now' => switch (query('id')) {
        final id? => PlebzLiveNowLink(id),
        null => null,
      },
      'reminder' => switch (query('key')) {
        final key? => PlebzReminderLink(key),
        null => null,
      },
      _ => null,
    };
  }
}

final class PlebzOpenLink extends HomeLink {
  const PlebzOpenLink(this.contentId);

  final String contentId;
}

final class PlebzWatchlistLink extends HomeLink {
  const PlebzWatchlistLink();
}

final class PlebzSportLink extends HomeLink {
  const PlebzSportLink();
}

final class PlebzLiveNowLink extends HomeLink {
  const PlebzLiveNowLink(this.entryId);

  final String entryId;
}

final class PlebzReminderLink extends HomeLink {
  const PlebzReminderLink(this.key);

  /// [ProgramReminder.key].
  final String key;
}

/// The "Jetzt live" entry a link asked for, waiting for the start page to
/// open it: the main screen sets it, the start page takes it.
final ValueNotifier<String?> pendingLiveNowEntry = ValueNotifier<String?>(null);
