import '../media/library_query.dart';
import '../media/media_filter.dart';
import '../media/media_item.dart';
import '../media/media_library.dart';
import '../media/media_server_client.dart';
import '../utils/app_logger.dart';

/// Resolves a server client for a library's server, or null when it is not
/// connected.
typedef ClientLookup = MediaServerClient? Function(String serverId);

/// The user's server-side favorites, collected across every connected server.
///
/// Jellyfin and Emby expose favorites as a per-library `Filters=IsFavorite`
/// query, so there is no single "all favorites" endpoint: the list is
/// assembled by asking each library and concatenating the answers.
///
/// Plex has no user favorites at all — its query translator silently ignores
/// [LibraryQuery.favoritesOnly], which would turn a favorites request into a
/// dump of the entire library. Libraries whose client does not advertise
/// `userFavorites` are therefore skipped outright; that capability check is
/// the guard keeping whole Plex libraries out of the Favorites tab, not an
/// optimization.
class ServerFavoritesService {
  /// Items per round trip.
  static const int pageSize = 200;

  const ServerFavoritesService();

  /// Whether any connected library can serve favorites at all — what decides
  /// if the Favorites tab is offered.
  static bool hasFavoritesCapableLibrary({required List<MediaLibrary> libraries, required ClientLookup clientFor}) {
    return libraries.any((library) {
      final serverId = library.serverId;
      if (serverId == null) return false;
      return clientFor(serverId)?.capabilities.userFavorites ?? false;
    });
  }

  /// Favorites from every library whose backend supports them, in library
  /// order. A library that fails is logged and skipped, so one unreachable
  /// server cannot empty the whole tab.
  Future<List<MediaItem>> fetchFavorites({
    required List<MediaLibrary> libraries,
    required ClientLookup clientFor,
  }) async {
    final favorites = <MediaItem>[];
    final seen = <String>{};

    for (final library in libraries) {
      final serverId = library.serverId;
      if (serverId == null) continue;
      final client = clientFor(serverId);
      if (client == null || !client.capabilities.userFavorites) continue;

      try {
        final items = await drainPages<MediaItem>(
          (start, size) => client.fetchLibraryPagedContent(
            library.id,
            // `favoritesOnly` was upstream's own named flag until 2.21, which
            // folded it into the clause list. Plex has no equivalent and its
            // translator ignores the clause, exactly as it ignored the flag.
            query: LibraryQuery(
              filters: const [
                LibraryFilter(field: MediaFilterField.favorite, values: ['1']),
              ],
              offset: start,
              limit: size,
            ),
            libraryKind: library.kind,
          ),
          pageSize: pageSize,
          // Jellyfin's total for a filtered query is authoritative, but Emby
          // has been seen to under-report it; stopping on a short page costs
          // nothing when the total is right.
          stopOnShortPage: true,
        );
        for (final item in items) {
          // One title can sit in two libraries (a shared library mounted on
          // two servers); key on server plus id so one entry wins.
          if (seen.add('$serverId:${item.id}')) favorites.add(item);
        }
      } catch (error, stackTrace) {
        appLogger.w('Favorites: library ${library.title} on $serverId failed', error: error, stackTrace: stackTrace);
      }
    }

    return favorites;
  }
}
