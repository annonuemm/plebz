part of '../../plex_client.dart';

/// The ids of every film and series on the server, for a tracker-led profile
/// (fork addition; see [ExternalIdIndexClient]).
mixin _PlexExternalIdIndexMethods on _PlexClientInternals implements ExternalIdIndexClient {
  /// How many titles one request asks for. A large library read in one
  /// listing ran past the receive timeout on a slow server and was asked
  /// again and again; pages keep every request short.
  static const int externalIdIndexPageSize = 500;

  /// How many pages one library is read in at most.
  static const int _externalIdIndexPageLimit = 100;

  @override
  Future<Map<String, ExternalIds>> fetchExternalIdIndex() async {
    final index = <String, ExternalIds>{};
    for (final library in await fetchLibraries()) {
      final type = switch (library.kind) {
        MediaKind.movie => 1,
        MediaKind.show => 2,
        _ => null,
      };
      if (type == null) continue;
      // One listing per library, in pages; `includeGuids` adds the `Guid`
      // array, and a legacy-agent library names its ids in the scalar `guid`
      // instead.
      final path = library.id == 'shared' ? '/library/shared/all' : '/library/sections/${library.id}/all';
      var start = 0;
      for (var page = 0; page < _externalIdIndexPageLimit; page++) {
        final response = await _getWithFailover(
          path,
          queryParameters: {'type': type, 'includeGuids': 1, ..._buildPaginationParams(start, externalIdIndexPageSize)},
        );
        final container = _getMediaContainer(response);
        final rows = container?['Metadata'];
        if (rows is! List) break;
        for (final row in rows) {
          if (row is! Map) continue;
          final key = row['ratingKey']?.toString();
          if (key == null || key.isEmpty) continue;
          final guids = row['Guid'];
          final ids = (guids is List ? ExternalIds.fromGuids(guids) : const ExternalIds()).fillFrom(
            ExternalIds.fromLegacyPlexGuid(row['guid']),
          );
          if (ids.hasCatalogIds) index[key] = ids;
        }
        start += rows.length;
        final total = flexibleInt(container?['totalSize']);
        // A short page is the last; a longer one means the server ignored
        // the paging and answered whole.
        if (rows.length != externalIdIndexPageSize || (total != null && start >= total)) break;
      }
    }
    return index;
  }
}
