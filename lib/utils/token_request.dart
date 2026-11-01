import 'package:http/http.dart' as http;

/// Sends a request that carries an account token in a header of its own
/// (Plebz), following a redirect only to an https address under [home].
///
/// The platform client follows redirects by itself and copies every header
/// to the new address except `Authorization` and cookies, so an
/// `X-Plex-Token` would go along to whatever host a redirect named. Here a
/// redirect anywhere else, or past [maxRedirects], is handed back as it came
/// and fails as any other non-2xx answer does.
Future<http.Response> sendTokenRequest(
  http.Client client,
  String method,
  Uri uri, {
  required Map<String, String> headers,
  String? body,
  required String home,
  int maxRedirects = 5,
}) async {
  var target = uri;
  var verb = method;
  var payload = body;
  for (var hop = 0; ; hop++) {
    final request = http.Request(verb, target)
      ..followRedirects = false
      ..headers.addAll(headers);
    if (payload != null) request.body = payload;
    final response = await http.Response.fromStream(await client.send(request));
    final location = response.headers['location'];
    if (!_redirects.contains(response.statusCode) || location == null || hop >= maxRedirects) return response;
    final next = target.resolve(location);
    if (!staysHome(next, home)) return response;
    // A 303, and a 301/302 after a POST, ask for the new address by GET.
    if (response.statusCode == 303 || (verb == 'POST' && response.statusCode <= 302)) {
      verb = 'GET';
      payload = null;
    }
    target = next;
  }
}

/// Whether [uri] is an https address on [home] or one of its subdomains.
bool staysHome(Uri uri, String home) => uri.scheme == 'https' && (uri.host == home || uri.host.endsWith('.$home'));

const _redirects = {301, 302, 303, 307, 308};
