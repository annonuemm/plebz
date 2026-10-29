part of '../../jellyfin_client.dart';

/// A library's studios, and its titles by studio — for the home screen's
/// brand rows (fork addition; see [StudioBrowseClient]).
mixin _JellyfinStudioMethods on _JellyfinClientInternals implements StudioBrowseClient {
  @override
  Future<List<ServerStudio>> fetchLibraryStudios(String libraryId) async {
    final response = await _http.get(
      '/Studios',
      queryParameters: {
        'userId': connection.userId,
        'ParentId': libraryId,
        'IncludeItemTypes': 'Movie,Series',
        'EnableImages': 'false',
        'EnableUserData': 'false',
      },
    );
    throwIfHttpError(response);
    return [
      for (final row in _itemsArray(response.data))
        if ((row['Id'], row['Name']) case (final String id, final String name) when id.isNotEmpty && name.isNotEmpty)
          (id: id, name: name),
    ];
  }

  @override
  Future<LibraryPage<MediaItem>> fetchStudioTitles(
    String libraryId, {
    required List<String> studioIds,
    List<MediaKind> kinds = const [MediaKind.movie, MediaKind.show],
    int offset = 0,
    int limit = 50,
    bool random = false,
  }) async {
    final query = LibraryQuery(
      includeKinds: kinds,
      offset: offset,
      limit: limit,
      sort: random
          ? const LibrarySort(field: 'random')
          : const LibrarySort(field: 'title', direction: LibrarySortDirection.ascending),
    );
    final params = JellyfinLibraryQueryTranslator(
      userId: connection.userId,
      parentId: libraryId,
      fields: _browseFields,
    ).toQueryParameters(query);
    params['StudioIds'] = studioIds.join('|');
    final response = await _http.get('/Items', queryParameters: params);
    throwIfHttpError(response);
    return _pagedItems(response.data, offset: offset, map: _mapItems, requestedSize: limit);
  }
}
