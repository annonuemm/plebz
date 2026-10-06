part of '../../plex_client.dart';

/// The ids of every film and series on the server, for a tracker-led profile
/// (fork addition; see [ExternalIdIndexClient]).
mixin _PlexExternalIdIndexMethods on _PlexClientInternals implements ExternalIdIndexClient {
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
      // One listing per library; `includeGuids` adds the `Guid` array, and a
      // legacy-agent library names its ids in the scalar `guid` instead.
      final path = library.id == 'shared' ? '/library/shared/all' : '/library/sections/${library.id}/all';
      final response = await _getWithFailover(path, queryParameters: {'type': type, 'includeGuids': 1});
      final rows = _getMediaContainer(response)?['Metadata'];
      if (rows is! List) continue;
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
    }
    return index;
  }
}
