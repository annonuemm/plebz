import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../utils/app_logger.dart';

/// Stations' logos from the public "tv-logos" collection on GitHub
/// (github.com/tv-logo/tv-logos), for IPTV channels whose own logo and whose
/// guide's both fail to load — providers' logo hosts come and go, and when
/// one lapses every channel that pointed there loses its picture at once.
///
/// Opt in only ([SettingsService.iptvPublicLogoFallback]): asking a stranger's
/// server for a logo tells it which one was wanted. The collection's file list
/// is read at most once a week and kept on disk, and only when a channel has
/// reached the point of needing it; a logo is then one plain file from
/// GitHub's raw host, cached like any other image.
///
/// Exact names only. "Spiegel TV" is not "Spiegel TV Wissen", and no logo is
/// better than the wrong one.
class PublicLogoIndex {
  PublicLogoIndex({this._client, Future<Directory> Function()? directory, DateTime Function()? now})
    : _directory = directory ?? getApplicationSupportDirectory,
      _now = now ?? DateTime.now;

  static final PublicLogoIndex instance = PublicLogoIndex();

  final http.Client? _client;
  final Future<Directory> Function() _directory;
  final DateTime Function() _now;

  static const _treeUrl = 'https://api.github.com/repos/tv-logo/tv-logos/git/trees/main?recursive=1';
  static const rawBase = 'https://raw.githubusercontent.com/tv-logo/tv-logos/main/';

  /// Searched in this order; the first country holding the name wins.
  static const countries = ['germany', 'austria', 'switzerland', 'international'];

  /// How long a stored file list stands before it is read again.
  static const maxAge = Duration(days: 7);

  /// Names a channel is commonly listed under that the collection files under
  /// another. Kept short on purpose, and grown only by cases that turned up.
  static const aliases = {'natgeo': 'nationalgeographic', 'discovery': 'discoverychannel'};

  /// Sky's sports channels were renamed "Sky Sport …" in 2021; playlists and
  /// guides still list many by the old name ("Sky Bundesliga 2"), the
  /// collection by the new.
  static String _aliased(String key) {
    if (aliases[key] case final alias?) return alias;
    if (key.startsWith('skybundesliga')) return 'skysport${key.substring('sky'.length)}';
    return key;
  }

  /// True once a file list is in memory; widgets waiting on it listen.
  final ValueNotifier<bool> ready = ValueNotifier(false);

  Map<String, List<_Logo>> _byName = const {};
  Future<void>? _loading;

  /// Starts reading the file list, from disk or from GitHub, once.
  Future<void> ensureLoaded() => _loading ??= _load();

  /// Uses [paths] as the collection's file list, for a test with no network.
  @visibleForTesting
  void debugUse(List<String> paths) {
    _byName = _index(paths);
    _loading = Future<void>.value();
    ready.value = true;
  }

  /// Forgets the file list, for a test.
  @visibleForTesting
  void debugReset() {
    _byName = const {};
    _loading = null;
    ready.value = false;
  }

  /// The collection's logo for a channel listed as [name], or null.
  String? logoFor(String? name) {
    if (name == null || name.trim().isEmpty) return null;
    final (:key, :hd) = channelKey(name);
    final logos = _byName[_aliased(key)];
    if (logos == null || logos.isEmpty) return null;
    final ranked = [...logos]
      ..sort((a, b) {
        final byCountry = a.country.compareTo(b.country);
        if (byCountry != 0) return byCountry;
        // The collection keeps retired marks in "old" folders.
        final byAge = (a.old ? 1 : 0).compareTo(b.old ? 1 : 0);
        if (byAge != 0) return byAge;
        final byHd = (a.hd == hd ? 0 : 1).compareTo(b.hd == hd ? 0 : 1);
        if (byHd != 0) return byHd;
        return (a.alt ? 1 : 0).compareTo(b.alt ? 1 : 0);
      });
    return '$rawBase${ranked.first.path}';
  }

  static final _countryPrefix = RegExp(r'^\s*[A-Za-z]{2,3}\s*[:|•]\s*');
  static final _quality = RegExp(r'^(?:fullhd|hevc|h26[45]|fhd|uhd|shd|hd|sd|4k|raw)+$');
  static const _folded = {'ä': 'a', 'ö': 'o', 'ü': 'u', 'ß': 'ss', 'é': 'e', 'è': 'e', 'à': 'a'};

  /// A channel name as the collection files it: lowercase letters and digits
  /// only, a provider's country prefix ("DE: ") and its quality words ("HD",
  /// "FHD", "HDraw") left off — and whether one of those said HD, which
  /// prefers the collection's HD variant.
  @visibleForTesting
  static ({String key, bool hd}) channelKey(String name) {
    var folded = name.replaceFirst(_countryPrefix, '').toLowerCase();
    _folded.forEach((from, to) => folded = folded.replaceAll(from, to));
    final words = folded.split(RegExp(r'[^a-z0-9]+')).where((word) => word.isNotEmpty).toList();
    var hd = false;
    while (words.length > 1 && _quality.hasMatch(words.last)) {
      final dropped = words.removeLast();
      if (dropped.contains('hd') || dropped == '4k') hd = true;
    }
    return (key: words.join(), hd: hd);
  }

  static Map<String, List<_Logo>> _index(List<String> paths) {
    final byName = <String, List<_Logo>>{};
    for (final path in paths) {
      final parts = path.split('/');
      if (parts.length < 3 || parts.first != 'countries' || !path.endsWith('.png')) continue;
      final country = countries.indexOf(parts[1]);
      if (country < 0) continue;
      final tokens = parts.last.substring(0, parts.last.length - 4).split('-');
      // The country code ends every name: "dmax-hd-de".
      if (tokens.length > 1) tokens.removeLast();
      var hd = false;
      var alt = false;
      while (tokens.length > 1 && (tokens.last == 'hd' || tokens.last == 'alt')) {
        if (tokens.removeLast() == 'hd') {
          hd = true;
        } else {
          alt = true;
        }
      }
      final key = tokens.join();
      if (key.isEmpty) continue;
      (byName[key] ??= []).add(_Logo(path: path, country: country, hd: hd, alt: alt, old: parts.contains('old')));
    }
    return byName;
  }

  Future<File> _file() async => File(p.join((await _directory()).path, 'iptv_public_logos.json'));

  Future<void> _load() async {
    List<String>? stored;
    DateTime? storedAt;
    try {
      final file = await _file();
      if (await file.exists()) {
        final decoded = jsonDecode(await file.readAsString());
        if (decoded case {'fetchedAt': final int at, 'paths': final List<dynamic> paths}) {
          storedAt = DateTime.fromMillisecondsSinceEpoch(at);
          stored = paths.whereType<String>().toList();
        }
      }
    } catch (e) {
      appLogger.d('Public logos: the stored file list could not be read', error: e);
    }

    if (stored != null && storedAt != null && _now().difference(storedAt) < maxAge) {
      _use(stored);
      return;
    }

    final fetched = await _fetch();
    if (fetched != null) {
      _use(fetched);
      try {
        await (await _file()).writeAsString(jsonEncode({'fetchedAt': _now().millisecondsSinceEpoch, 'paths': fetched}));
      } catch (e) {
        appLogger.d('Public logos: the file list could not be stored', error: e);
      }
    } else if (stored != null) {
      // Out of date beats nothing: GitHub may simply be unreachable today.
      _use(stored);
    } else {
      // Nothing to go on; the next channel that needs it asks again.
      _loading = null;
    }
  }

  void _use(List<String> paths) {
    _byName = _index(paths);
    ready.value = true;
  }

  Future<List<String>?> _fetch() async {
    final client = _client ?? http.Client();
    try {
      final response = await client
          .get(Uri.parse(_treeUrl), headers: const {'User-Agent': 'Plezy', 'Accept': 'application/vnd.github+json'})
          .timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) {
        appLogger.w('Public logos: GitHub answered ${response.statusCode}');
        return null;
      }
      final paths = await compute(_pathsIn, response.body);
      appLogger.i('Public logos: ${paths.length} logos in the collection');
      return paths;
    } catch (e) {
      appLogger.w('Public logos: the file list could not be fetched', error: e);
      return null;
    } finally {
      if (_client == null) client.close();
    }
  }
}

/// The logo files of the countries searched, out of GitHub's tree listing.
List<String> _pathsIn(String body) {
  final decoded = jsonDecode(body);
  if (decoded is! Map<String, dynamic> || decoded['tree'] is! List) return const [];
  return [
    for (final entry in decoded['tree'] as List)
      if (entry case {
        'type': 'blob',
        'path': final String path,
      } when path.endsWith('.png') && PublicLogoIndex.countries.any((c) => path.startsWith('countries/$c/')))
        path,
  ];
}

class _Logo {
  const _Logo({required this.path, required this.country, required this.hd, required this.alt, required this.old});

  final String path;

  /// Position in [PublicLogoIndex.countries]: lower wins.
  final int country;
  final bool hd;
  final bool alt;

  /// Filed among the collection's retired marks.
  final bool old;
}
