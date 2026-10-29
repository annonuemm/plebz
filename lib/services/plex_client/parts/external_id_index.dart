part of '../../plex_client.dart';

/// What a tracker-led profile asks of a Plex server (fork addition; see
/// [ExternalIdIndexClient] and [TrackerEpisodeListClient]): the ids of every
/// film and series, and a series' episodes without their tracks.
mixin _PlexExternalIdIndexMethods on _PlexClientInternals implements ExternalIdIndexClient, TrackerEpisodeListClient {
  /// How many titles one request asks for. A large library read in one
  /// listing ran past the receive timeout on a slow server and was asked
  /// again and again; pages keep every request short.
  static const int externalIdIndexPageSize = 500;

  /// How many pages one library is read in at most.
  static const int _externalIdIndexPageLimit = 100;

  /// How far before the last read's newest title a read of what was added
  /// since starts: a title added in the same second is read twice rather
  /// than missed.
  static const int _addedSinceOverlap = 60;

  /// How many episodes one series' list holds at most.
  static const int trackerEpisodeListSize = 2000;

  @override
  Future<ExternalIdIndexRead> fetchExternalIdIndex({int? addedSince}) async {
    if (addedSince != null) {
      final added = await _readExternalIdIndex(addedSince: addedSince - _addedSinceOverlap);
      if (added != null) return added;
      appLogger.i('Plex id index: the server cannot list what was added since, reading it whole');
    }
    return (await _readExternalIdIndex())!;
  }

  /// Every film and series library in pages, or with [addedSince] only the
  /// titles added after it. Null when [addedSince] was asked and the server
  /// did not keep to it.
  Future<ExternalIdIndexRead?> _readExternalIdIndex({int? addedSince}) async {
    final index = <String, ExternalIds>{};
    int? newest;
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
        final MediaServerResponse response;
        try {
          response = await _getWithFailover(
            path,
            queryParameters: {
              'type': type,
              'includeGuids': 1,
              // Plex's "added after": the operator rides in the key.
              'addedAt>>': ?addedSince,
              ..._buildPaginationParams(start, externalIdIndexPageSize),
            },
          );
        } on MediaServerHttpException catch (error) {
          final status = error.statusCode ?? 0;
          if (addedSince != null && status >= 400 && status < 500) return null;
          rethrow;
        }
        final container = _getMediaContainer(response);
        final rows = container?['Metadata'];
        if (rows is! List) break;
        for (final row in rows) {
          if (row is! Map) continue;
          final added = flexibleInt(row['addedAt']);
          // A title from before the cut: the server ignored the filter and is
          // listing the library whole.
          if (addedSince != null && added != null && added < addedSince) return null;
          if (added != null && (newest == null || added > newest)) newest = added;
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
    return ExternalIdIndexRead(index, complete: addedSince == null, newest: newest);
  }

  @override
  Future<List<MediaItem>> fetchEpisodesWithoutStreams(String seriesId) async {
    final response = await _getWithFailover(
      '/library/metadata/$seriesId/grandchildren',
      queryParameters: _buildPaginationParams(0, trackerEpisodeListSize),
    );
    final container = _getMediaContainer(response);
    final rows = container?['Metadata'];
    if (rows is! List) return const [];
    final sectionId = flexibleInt(container?['librarySectionID']);
    final sectionTitle = container?['librarySectionTitle'];
    return [
      for (final row in rows)
        if (row is Map<String, dynamic>)
          PlexMappers.mediaItem(
            _createTaggedMetadataWithLibrary(
              row,
              librarySectionID: sectionId,
              librarySectionTitle: sectionTitle is String ? sectionTitle : null,
            ),
          ),
    ];
  }
}
