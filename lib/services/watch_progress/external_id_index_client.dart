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
  Future<Map<String, ExternalIds>> fetchExternalIdIndex();
}
