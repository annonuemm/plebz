import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../utils/abortable_http_request.dart';
import '../../utils/app_logger.dart';
import '../../utils/platform_http_client_stub.dart'
    if (dart.library.io) '../../utils/platform_http_client_io.dart'
    as platform;
import 'sport_models.dart';

/// Read-only client for OpenLigaDB, the community-kept football database.
///
/// Free, keyless, and it carries exactly the three leagues the Sport
/// destination shows. Nothing about the viewer travels with a request: every
/// URL is a league shortcut, a season and a matchday number, and no request
/// carries a header beyond `Accept`.
///
/// Every method answers null when the provider could not be reached or said
/// something unreadable. A null is "unknown", never "empty" — callers keep
/// what they had rather than wiping it.
class OpenLigaDbClient {
  static const String apiBase = 'https://api.openligadb.de';

  static const Duration _timeout = Duration(seconds: 15);

  final http.Client _http;
  final bool _ownsClient;

  OpenLigaDbClient({http.Client? httpClient})
    : _http = httpClient ?? platform.createPlatformClient(),
      _ownsClient = httpClient == null;

  void dispose() {
    if (_ownsClient) _http.close();
  }

  /// The matchday the provider currently calls current, with its fixtures.
  /// Its fixtures also say which season that is.
  Future<List<SportMatch>?> fetchCurrentMatchday(SportLeague league) =>
      _matches('/getmatchdata/${league.shortcut}', operation: 'OpenLigaDB current ${league.shortcut}');

  Future<List<SportMatch>?> fetchMatchday(SportLeague league, {required int season, required int matchday}) => _matches(
    '/getmatchdata/${league.shortcut}/$season/$matchday',
    operation: 'OpenLigaDB ${league.shortcut} $season/$matchday',
  );

  /// Every matchday of [season], in order. Thirty-four in the two Bundesligen,
  /// thirty-eight in the 3. Liga.
  Future<List<SportMatchday>?> fetchMatchdays(SportLeague league, {required int season}) async {
    final decoded = await _getJson(
      '/getavailablegroups/${league.shortcut}/$season',
      operation: 'OpenLigaDB matchdays ${league.shortcut} $season',
    );
    if (decoded is! List) return null;
    return [
      for (final entry in decoded)
        if (SportMatchday.fromJson(entry) case final SportMatchday day) day,
    ]..sort((a, b) => a.order.compareTo(b.order));
  }

  Future<List<SportTableRow>?> fetchTable(SportLeague league, {required int season}) async {
    final decoded = await _getJson(
      '/getbltable/${league.shortcut}/$season',
      operation: 'OpenLigaDB table ${league.shortcut} $season',
    );
    if (decoded is! List) return null;
    return SportTableRow.listFromJson(decoded);
  }

  Future<List<SportMatch>?> _matches(String path, {required String operation}) async {
    final decoded = await _getJson(path, operation: operation);
    if (decoded is! List) return null;
    return [
      for (final entry in decoded)
        if (SportMatch.fromJson(entry) case final SportMatch match) match,
    ]..sort((a, b) => a.kickoff.compareTo(b.kickoff));
  }

  Future<Object?> _getJson(String path, {required String operation}) async {
    try {
      final response = await sendAbortableHttpRequest(
        _http,
        'GET',
        Uri.parse('$apiBase$path'),
        headers: const {'Accept': 'application/json'},
        timeout: _timeout,
        operation: operation,
      );
      if (response.statusCode != 200) {
        appLogger.d('$operation -> ${response.statusCode}');
        return null;
      }
      return jsonDecode(utf8.decode(response.bodyBytes));
    } catch (e) {
      appLogger.d('$operation failed', error: e);
      return null;
    }
  }
}
