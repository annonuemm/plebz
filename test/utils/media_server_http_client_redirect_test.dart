import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:plezy/exceptions/media_server_exceptions.dart';
import 'package:plezy/utils/media_server_http_client.dart';

/// Answers each URL from [routes]; anything else is a 200 with `{}`. Records
/// every request it was sent, headers included.
class _RoutingClient extends http.BaseClient {
  _RoutingClient(this.routes);

  final Map<String, (int, Map<String, String>)> routes;
  final List<http.BaseRequest> sent = [];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    sent.add(request);
    await request.finalize().drain<void>();
    final (status, headers) = routes[request.url.toString()] ?? (200, const {'content-type': 'application/json'});
    return _ResponseWithUrl(
      Stream.value(utf8.encode(status == 200 ? '{}' : '')),
      status,
      headers: headers,
      url: request.url,
      request: request,
    );
  }
}

/// What dart:io's client answers with: the response knows its own URL.
class _ResponseWithUrl extends http.StreamedResponse implements http.BaseResponseWithUrl {
  _ResponseWithUrl(super.stream, super.statusCode, {super.headers, super.request, required this.url});

  @override
  final Uri url;
}

const _token = {'X-Plex-Token': 'secret', 'X-Emby-Token': 'secret', 'X-Plex-Client-Identifier': 'device'};

void main() {
  group('MediaServerHttpClient redirects', () {
    test('follows a same-origin redirect with the token', () async {
      final transport = _RoutingClient({
        'https://server.test/a': (302, {'location': '/b'}),
      });
      final client = MediaServerHttpClient(client: transport, baseUrl: 'https://server.test/', defaultHeaders: _token);

      final response = await client.get('a');

      expect(response.statusCode, 200);
      expect(response.effectiveUri, Uri.parse('https://server.test/b'));
      expect(transport.sent.map((r) => r.url.toString()), ['https://server.test/a', 'https://server.test/b']);
      expect(transport.sent.last.headers['X-Plex-Token'], 'secret');
      expect(transport.sent.every((r) => !r.followRedirects), isTrue);
    });

    test('drops the token when the redirect leaves for another host', () async {
      final transport = _RoutingClient({
        'https://server.test/a': (302, {'location': 'https://elsewhere.test/b'}),
      });
      final client = MediaServerHttpClient(
        client: transport,
        baseUrl: 'https://server.test/',
        defaultHeaders: {..._token, 'Authorization': 'MediaBrowser Token="secret"', 'Cookie': 'sid=1'},
      );

      await client.get('a');

      final followed = transport.sent.last;
      expect(followed.url.host, 'elsewhere.test');
      expect(followed.headers.keys.map((k) => k.toLowerCase()), isNot(contains('x-plex-token')));
      expect(followed.headers.keys.map((k) => k.toLowerCase()), isNot(contains('x-emby-token')));
      expect(followed.headers.keys.map((k) => k.toLowerCase()), isNot(contains('authorization')));
      expect(followed.headers.keys.map((k) => k.toLowerCase()), isNot(contains('cookie')));
      expect(followed.headers['X-Plex-Client-Identifier'], 'device');
    });

    test('keeps the token when the same host moves up to HTTPS', () async {
      final transport = _RoutingClient({
        'http://server.test:8096/a': (301, {'location': 'https://server.test:8920/a'}),
      });
      final client = MediaServerHttpClient(
        client: transport,
        baseUrl: 'http://server.test:8096/',
        defaultHeaders: _token,
      );

      await client.get('a');

      expect(transport.sent.last.url.toString(), 'https://server.test:8920/a');
      expect(transport.sent.last.headers['X-Emby-Token'], 'secret');
    });

    test('refuses a redirect from HTTPS to plain HTTP', () async {
      final transport = _RoutingClient({
        'https://server.test/a': (302, {'location': 'http://server.test/a'}),
      });
      final client = MediaServerHttpClient(client: transport, baseUrl: 'https://server.test/', defaultHeaders: _token);

      await expectLater(client.get('a'), throwsA(isA<MediaServerHttpException>()));
      expect(transport.sent, hasLength(1));
    });

    test('gives up after the hop limit', () async {
      final transport = _RoutingClient({
        'https://server.test/a': (302, {'location': '/a'}),
      });
      final client = MediaServerHttpClient(client: transport, baseUrl: 'https://server.test/');

      await expectLater(client.get('a'), throwsA(isA<MediaServerHttpException>()));
      expect(transport.sent, hasLength(MediaServerHttpClient.maxRedirects + 1));
    });

    test('a POST answered with 303 continues as a GET without its body', () async {
      final transport = _RoutingClient({
        'https://server.test/a': (303, {'location': '/b'}),
      });
      final client = MediaServerHttpClient(client: transport, baseUrl: 'https://server.test/');

      await client.post('a', body: {'x': 1});

      expect(transport.sent.map((r) => '${r.method} ${r.url.path}'), ['POST /a', 'GET /b']);
      expect(transport.sent.last.contentLength, 0);
    });

    test('other methods are not redirected', () async {
      final transport = _RoutingClient({
        'https://server.test/a': (307, {'location': '/b'}),
      });
      final client = MediaServerHttpClient(client: transport, baseUrl: 'https://server.test/');

      final response = await client.delete('a');

      expect(response.statusCode, 307);
      expect(transport.sent, hasLength(1));
    });
  });

  group('keepsCredentialsOnRedirect', () {
    bool keeps(String from, String to) =>
        MediaServerHttpClient.keepsCredentialsOnRedirect(Uri.parse(from), Uri.parse(to));

    test('same origin and an upgrade to HTTPS on the same host keep them', () {
      expect(keeps('https://a.test/x', 'https://A.test/y'), isTrue);
      expect(keeps('http://a.test/x', 'https://a.test/x'), isTrue);
    });

    test('another host, another plain-HTTP port or a downgrade drop them', () {
      expect(keeps('https://a.test/x', 'https://b.test/x'), isFalse);
      expect(keeps('http://a.test:80/x', 'http://a.test:8080/x'), isFalse);
      expect(keeps('https://a.test/x', 'http://a.test/x'), isFalse);
    });
  });
}
