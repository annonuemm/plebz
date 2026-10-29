import '../../utils/external_ids.dart';

/// A server that can name the IMDb/TMDB/TVDB ids of every film and series it
/// holds in one go (fork addition).
///
/// A tracker knows titles only by those ids, and a server's lists do not carry
/// them: asking item by item would cost a request per poster. Plex and
/// Jellyfin/Emby answer a whole library at once instead.
abstract interface class ExternalIdIndexClient {
  /// The server's films and series by item id, each with the ids it knows.
  /// Titles without any of the three ids are left out.
  ///
  /// With [addedSince] — the [ExternalIdIndexRead.newest] of an earlier
  /// read — only the titles added after it, where the server can list those;
  /// [ExternalIdIndexRead.complete] says which of the two the answer is.
  Future<ExternalIdIndexRead> fetchExternalIdIndex({int? addedSince});
}

/// One answer of [ExternalIdIndexClient.fetchExternalIdIndex] (fork addition).
class ExternalIdIndexRead {
  const ExternalIdIndexRead(this.ids, {required this.complete, this.newest});

  final Map<String, ExternalIds> ids;

  /// Whether [ids] is the server's whole index; false when it holds only what
  /// was added since, to be laid over the index already known.
  final bool complete;

  /// When the newest title read was added, in the server's own clock (Unix
  /// seconds): what the next read asks for additions since. Null when the
  /// server named no such time.
  final int? newest;
}
