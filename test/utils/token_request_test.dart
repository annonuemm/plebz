import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plezy/utils/token_request.dart';

/// An account token in `X-Plex-Token` goes along with every redirect the
/// platform client follows; it may only follow one that stays on plex.tv.
void main() {
  final seen = <(String, Uri, String?)>[];

  http.Client serving(Map<String, http.Response Function()> byUrl) => MockClient((request) async {
    seen.add((request.method, request.url, request.headers['X-Plex-Token']));
    final answer = byUrl[request.url.toString()];
    return answer == null ? http.Response('missing', 404) : answer();
  });

  http.Response redirect(int status, String to) => http.Response('', status, headers: {'location': to});

  setUp(seen.clear);

  test('follows a redirect that stays on plex.tv, token included', () async {
    final client = serving({
      'https://discover.provider.plex.tv/a': () => redirect(301, 'https://metadata.provider.plex.tv/b'),
      'https://metadata.provider.plex.tv/b': () => http.Response('{}', 200),
    });

    final response = await sendTokenRequest(
      client,
      'GET',
      Uri.parse('https://discover.provider.plex.tv/a'),
      headers: {'X-Plex-Token': 'secret'},
      home: 'plex.tv',
    );

    expect(response.statusCode, 200);
    expect(seen.map((s) => s.$3), ['secret', 'secret']);
  });

  test('does not follow one to another host or to plain http', () async {
    for (final to in ['https://elsewhere.example/b', 'http://discover.provider.plex.tv/b', 'https://evilplex.tv/b']) {
      seen.clear();
      final client = serving({'https://community.plex.tv/api': () => redirect(307, to)});

      final response = await sendTokenRequest(
        client,
        'POST',
        Uri.parse('https://community.plex.tv/api'),
        headers: {'X-Plex-Token': 'secret'},
        body: '{}',
        home: 'plex.tv',
      );

      expect(response.statusCode, 307, reason: to);
      expect(seen, hasLength(1), reason: to);
    }
  });

  test('a 303 after a POST asks for the new address by GET', () async {
    final client = serving({
      'https://community.plex.tv/api': () => redirect(303, '/done'),
      'https://community.plex.tv/done': () => http.Response('ok', 200),
    });

    final response = await sendTokenRequest(
      client,
      'POST',
      Uri.parse('https://community.plex.tv/api'),
      headers: {'X-Plex-Token': 'secret'},
      body: '{}',
      home: 'plex.tv',
    );

    expect(response.body, 'ok');
    expect(seen.last.$1, 'GET');
  });

  test('stops after the last allowed hop', () async {
    final client = serving({'https://plex.tv/loop': () => redirect(302, 'https://plex.tv/loop')});

    final response = await sendTokenRequest(
      client,
      'GET',
      Uri.parse('https://plex.tv/loop'),
      headers: const {},
      home: 'plex.tv',
      maxRedirects: 3,
    );

    expect(response.statusCode, 302);
    expect(seen, hasLength(4));
  });
}
