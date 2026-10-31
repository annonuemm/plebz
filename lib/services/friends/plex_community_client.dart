import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../utils/app_logger.dart';
import '../../utils/json_utils.dart';
import '../plex_discover_client.dart';

/// A Plex friend as the account's friend list names them (Plebz).
class PlexFriend {
  const PlexFriend({required this.id, required this.name, this.avatarUrl});

  /// The friend's plex.tv user id, the one their activity is filed under.
  final String id;
  final String name;
  final String? avatarUrl;

  /// The first letter of [name], for a round picture without one.
  String get initial => name.isEmpty ? '?' : String.fromCharCode(name.runes.first).toUpperCase();
}

/// One "watched" entry from Plex's activity feed: who, when, and what — in
/// Discover's ids, so the title opens as Explore opens it.
class PlexWatchActivity {
  const PlexWatchActivity({
    required this.userId,
    required this.at,
    required this.metadataId,
    required this.type,
    required this.title,
    this.showId,
    this.showTitle,
    this.season,
    this.episode,
  });

  final String userId;
  final DateTime at;

  /// Discover's id of what was watched: a film, or an episode.
  final String metadataId;

  /// Discover's own word for it: `movie`, `episode`, …
  final String type;
  final String title;

  /// For an episode, its show — the title a row shows and a page opens.
  final String? showId;
  final String? showTitle;
  final int? season;
  final int? episode;

  /// The id of the title as a whole: the show for an episode.
  String get titleId => showId ?? metadataId;
}

/// Plex's community service (`community.plex.tv/api`), the GraphQL endpoint
/// Plex Web reads a friend's activity from (Plebz).
///
/// Undocumented. Only fields other tools have been seen to read are asked
/// for — a field the schema lacks fails the whole query — and every answer
/// is read defensively: an entry without what a row needs is dropped, never
/// guessed at. Plex applies the friends' own privacy choices; a friend who
/// shares nothing simply never appears.
class PlexCommunityClient {
  PlexCommunityClient(this.session, {http.Client? httpClient, this.requestTimeout = const Duration(seconds: 20)})
    : _http = httpClient ?? http.Client();

  static final Uri endpoint = Uri.parse('https://community.plex.tv/api');

  final PlexDiscoverSession session;
  final http.Client _http;
  final Duration requestTimeout;

  static const _friendsQuery = '''
query PlebzFriends {
  allFriendsV2 {
    user { id username displayName avatar }
  }
}''';

  static const _entryFields = '''
nodes {
  ... on ActivityWatchHistory {
    id
    date
    metadataItem {
      id type title index
      parent { id type title index }
      grandparent { id type title index }
    }
    userV2 { id }
  }
}
pageInfo { endCursor hasNextPage }''';

  static const _feedQuery =
      '''
query PlebzFriendsActivity(\$first: PaginationInt!, \$after: String) {
  activityFeed(first: \$first, after: \$after, types: [WATCH_HISTORY]) {
    $_entryFields
  }
}''';

  static const _titleQuery =
      '''
query PlebzTitleActivity(\$first: PaginationInt!, \$metadataID: ID) {
  activityFeed(first: \$first, metadataID: \$metadataID, types: [WATCH_HISTORY], includeDescendants: true) {
    $_entryFields
  }
}''';

  /// The account's friends, in the order Plex lists them.
  Future<List<PlexFriend>> friends() async {
    final data = await _query(_friendsQuery, const {}, 'PlebzFriends');
    final friends = <PlexFriend>[];
    for (final entry in flexibleMapList(data['allFriendsV2'])) {
      final user = firstFlexibleMap(entry['user']);
      final id = _string(user?['id']);
      final name = _string(user?['displayName']) ?? _string(user?['username']);
      if (id == null || name == null) continue;
      friends.add(PlexFriend(id: id, name: name, avatarUrl: _httpsUrl(user?['avatar'])));
    }
    return friends;
  }

  /// The latest watched entries the account may see, newest first. Up to
  /// [pages] pages of [pageSize].
  Future<List<PlexWatchActivity>> recentActivity({int pageSize = 50, int pages = 2}) async {
    final entries = <PlexWatchActivity>[];
    String? after;
    for (var page = 0; page < pages; page++) {
      final data = await _query(_feedQuery, {'first': pageSize, 'after': ?after}, 'PlebzFriendsActivity');
      final feed = firstFlexibleMap(data['activityFeed']);
      entries.addAll(_entries(feed));
      final info = firstFlexibleMap(feed?['pageInfo']);
      after = _string(info?['endCursor']);
      if (info?['hasNextPage'] != true || after == null) break;
    }
    return entries;
  }

  /// Who watched [metadataId] — a film, or a show with its episodes.
  Future<List<PlexWatchActivity>> activityFor(String metadataId, {int first = 50}) async {
    final data = await _query(_titleQuery, {'first': first, 'metadataID': metadataId}, 'PlebzTitleActivity');
    return _entries(firstFlexibleMap(data['activityFeed']));
  }

  static List<PlexWatchActivity> _entries(Map<String, dynamic>? feed) {
    final entries = <PlexWatchActivity>[];
    for (final node in flexibleMapList(feed?['nodes'])) {
      final userId = _string(firstFlexibleMap(node['userV2'])?['id']);
      final at = DateTime.tryParse(_string(node['date']) ?? '');
      final item = firstFlexibleMap(node['metadataItem']);
      final id = _string(item?['id']);
      final type = _string(item?['type'])?.toLowerCase();
      final title = _string(item?['title']);
      if (userId == null || at == null || id == null || type == null || title == null) continue;
      final parent = firstFlexibleMap(item?['parent']);
      final grandparent = firstFlexibleMap(item?['grandparent']);
      final isEpisode = type == 'episode';
      final show = isEpisode ? grandparent : (type == 'season' ? parent : null);
      final showId = _string(show?['id']);
      if ((isEpisode || type == 'season') && showId == null) continue;
      entries.add(
        PlexWatchActivity(
          userId: userId,
          at: at.toLocal(),
          metadataId: id,
          type: type,
          title: title,
          showId: showId,
          showTitle: _string(show?['title']),
          season: isEpisode ? flexibleInt(parent?['index']) : (type == 'season' ? flexibleInt(item?['index']) : null),
          episode: isEpisode ? flexibleInt(item?['index']) : null,
        ),
      );
    }
    return entries;
  }

  Future<Map<String, dynamic>> _query(String query, Map<String, Object?> variables, String operation) async {
    final stopwatch = Stopwatch()..start();
    final response = await _http
        .post(
          endpoint,
          headers: {
            'Accept': 'application/json',
            'Content-Type': 'application/json',
            'X-Plex-Token': session.accessToken,
            'X-Plex-Client-Identifier': session.clientIdentifier,
            'X-Plex-Product': 'Plezy',
            'X-Plex-Version': '2',
          },
          body: jsonEncode({'query': query, 'variables': variables, 'operationName': operation}),
        )
        .timeout(requestTimeout);
    appLogger.d('Community $operation → ${response.statusCode} (${stopwatch.elapsedMilliseconds}ms)');
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw PlexCommunityException(response.statusCode, 'HTTP ${response.statusCode}');
    }
    final decoded = jsonDecode(response.body);
    final body = decoded is Map<String, dynamic> ? decoded : const <String, dynamic>{};
    final data = firstFlexibleMap(body['data']);
    if (data == null) {
      final errors = flexibleMapList(body['errors']);
      throw PlexCommunityException(response.statusCode, _string(errors.firstOrNull?['message']) ?? 'No data');
    }
    return data;
  }

  static String? _string(Object? value) {
    final string = value?.toString().trim();
    return string == null || string.isEmpty ? null : string;
  }

  /// Only an absolute https address is drawn: the picture loads without any
  /// server, and nothing else is fetched on a friend's say.
  static String? _httpsUrl(Object? value) {
    final url = _string(value);
    final uri = url == null ? null : Uri.tryParse(url);
    return uri != null && uri.scheme == 'https' && uri.host.isNotEmpty ? url : null;
  }

  void dispose() => _http.close();
}

class PlexCommunityException implements Exception {
  const PlexCommunityException(this.statusCode, this.message);

  final int statusCode;
  final String message;

  @override
  String toString() => 'PlexCommunityException($statusCode): $message';
}
