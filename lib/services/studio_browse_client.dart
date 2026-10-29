import '../media/library_query.dart';
import '../media/media_item.dart';
import '../media/media_kind.dart';

/// A studio — for a series, the network it was made for — as a server lists
/// it under one library.
typedef ServerStudio = ({String id, String name});

/// A server that can list a library's studios and browse it by them (fork
/// addition, for the home screen's brand rows).
///
/// Jellyfin and Emby keep a series' network among its studios and filter by
/// studio id, which their library filters do not offer. Plex needs no such
/// seam: its `network` and `studio` fields list and filter through the
/// ordinary section routes.
abstract interface class StudioBrowseClient {
  /// The studios the films and series of [libraryId] name.
  Future<List<ServerStudio>> fetchLibraryStudios(String libraryId);

  /// The films and series of [libraryId] naming any of [studioIds].
  ///
  /// [random] reads them in the server's random order — a different handful
  /// each call; otherwise by title.
  Future<LibraryPage<MediaItem>> fetchStudioTitles(
    String libraryId, {
    required List<String> studioIds,
    List<MediaKind> kinds = const [MediaKind.movie, MediaKind.show],
    int offset = 0,
    int limit = 50,
    bool random = false,
  });
}
