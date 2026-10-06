part of '../../jellyfin_client.dart';

/// The ids of every film and series on the server, for a tracker-led profile
/// (fork addition; see [ExternalIdIndexClient]).
mixin _JellyfinExternalIdIndexMethods on _JellyfinClientInternals implements ExternalIdIndexClient {
  @override
  Future<Map<String, ExternalIds>> fetchExternalIdIndex() async {
    final response = await _http.get(
      '/Items',
      queryParameters: {
        'userId': connection.userId,
        'IncludeItemTypes': 'Movie,Series',
        'Recursive': 'true',
        'Fields': 'ProviderIds',
        'EnableImages': 'false',
        'EnableUserData': 'false',
      },
    );
    throwIfHttpError(response);
    final data = response.data;
    final rows = data is Map ? data['Items'] : null;
    final index = <String, ExternalIds>{};
    if (rows is! List) return index;
    for (final row in rows) {
      if (row is! Map) continue;
      final id = row['Id'];
      final providerIds = row['ProviderIds'];
      if (id is! String || id.isEmpty || providerIds is! Map<String, dynamic>) continue;
      final ids = ExternalIds.fromJellyfinProviderIds(providerIds);
      if (ids.hasCatalogIds) index[id] = ids;
    }
    return index;
  }
}
