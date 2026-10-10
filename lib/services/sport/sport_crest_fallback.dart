import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../utils/app_logger.dart';
import '../../utils/fork_identity.dart';
import 'sport_models.dart';

/// A crest for a club whose own link is dead (Plebz).
///
/// OpenLigaDB's crests are links its community keeps, and now and then one
/// points nowhere (Bayer 04 Leverkusen's, to a site that answers 404). The
/// German Wikipedia's article on the club carries the crest as its page image,
/// so that is asked for by the club's name — one request per club per run,
/// and only for a club whose own crest failed.
class SportCrestFallback {
  SportCrestFallback({http.Client? client}) : _client = client ?? http.Client();

  static final SportCrestFallback instance = SportCrestFallback();

  final http.Client _client;

  /// Lookups by club, the answered ones kept for the run; one that found
  /// nothing or failed is dropped, so a later failure may ask again.
  final Map<int, Future<String?>> _lookups = {};

  Future<String?> crestFor(SportTeam team) {
    final existing = _lookups[team.id];
    if (existing != null) return existing;
    final lookup = _lookUp(team.name);
    _lookups[team.id] = lookup;
    unawaited(
      lookup.then((url) {
        if (url == null) _lookups.remove(team.id);
      }),
    );
    return lookup;
  }

  Future<String?> _lookUp(String clubName) async {
    final uri = Uri.https('de.wikipedia.org', '/w/api.php', {
      'action': 'query',
      'format': 'json',
      'redirects': '1',
      'prop': 'pageimages',
      'piprop': 'thumbnail',
      'pithumbsize': '$crestThumbnailWidth',
      'titles': clubName,
    });
    try {
      final response = await _client
          .get(uri, headers: const {'User-Agent': wikimediaUserAgent})
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return null;
      final url = crestFromPageImages(jsonDecode(response.body));
      appLogger.d('Sport: crest for $clubName ${url == null ? 'not on Wikipedia' : 'taken from Wikipedia'}');
      return url;
    } catch (e) {
      appLogger.d('Sport: no crest for $clubName from Wikipedia', error: e);
      return null;
    }
  }

  /// The page image's thumbnail out of a `prop=pageimages` answer, without
  /// the tracking query Wikipedia hangs on it.
  @visibleForTesting
  static String? crestFromPageImages(Object? json) {
    if (json is! Map) return null;
    final pages = (json['query'] as Map?)?['pages'];
    if (pages is! Map) return null;
    for (final page in pages.values) {
      if (page is! Map) continue;
      final thumbnail = page['thumbnail'];
      final source = thumbnail is Map ? thumbnail['source'] : null;
      if (source is! String || source.isEmpty) continue;
      final uri = Uri.tryParse(source);
      if (uri == null || !uri.hasScheme) continue;
      return Uri(scheme: uri.scheme, host: uri.host, port: uri.hasPort ? uri.port : null, path: uri.path).toString();
    }
    return null;
  }
}
