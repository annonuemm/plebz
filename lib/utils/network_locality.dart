import 'dart:io';

import 'url_utils.dart';

/// Whether [host] (a hostname or an IP literal, brackets allowed) is in the
/// home network rather than on the internet: private, loopback, link-local,
/// carrier-grade NAT and unique-local addresses; `localhost`, single-label
/// names and the home suffixes (`.local`, `.lan`, `.home.arpa`,
/// `.internal`, `.ts.net`).
///
/// The same rule as `PlexServer._isLocalOrPrivateHost`, which decides where a
/// Plex token may travel over plain HTTP; kept apart so the official Plezy
/// app's file stays as it is.
bool isLocalOrPrivateHost(String host) {
  final bare = (host.startsWith('[') && host.endsWith(']') ? host.substring(1, host.length - 1) : host).toLowerCase();
  if (bare.isEmpty) return true;
  final address = InternetAddress.tryParse(bare);
  if (address != null) return _isPrivateOrLocalAddress(address);
  if (bare == 'localhost' || !bare.contains('.')) return true;
  return bare.endsWith('.local') ||
      bare.endsWith('.lan') ||
      bare.endsWith('.home.arpa') ||
      bare.endsWith('.internal') ||
      bare.endsWith('.ts.net');
}

bool _isPrivateOrLocalAddress(InternetAddress address) {
  final bytes = address.rawAddress;
  if (address.type == InternetAddressType.IPv4 && bytes.length == 4) {
    final a = bytes[0];
    final b = bytes[1];
    return a == 0 ||
        a == 10 ||
        (a == 100 && b >= 64 && b <= 127) ||
        a == 127 ||
        (a == 169 && b == 254) ||
        (a == 172 && b >= 16 && b <= 31) ||
        (a == 192 && b == 168);
  }
  if (address.type == InternetAddressType.IPv6 && bytes.length == 16) {
    final isLoopback = bytes.take(15).every((b) => b == 0) && bytes[15] == 1;
    final isUnspecified = bytes.every((b) => b == 0);
    return isLoopback || isUnspecified || (bytes[0] & 0xfe) == 0xfc || (bytes[0] == 0xfe && (bytes[1] & 0xc0) == 0x80);
  }
  return false;
}

/// Whether [url] would carry a password or token unencrypted across the
/// internet: plain `http` to a host outside the home network.
bool isPlainHttpOverInternet(String url) {
  final uri = Uri.tryParse(url);
  return uri != null && uri.scheme.toLowerCase() == 'http' && !isLocalOrPrivateHost(uri.host);
}

/// The schemeless guesses worth trying for [input]: all of them in the home
/// network, only the TLS ones on the internet. Plain HTTP to an internet host
/// happens only when the person typed `http://` themselves — and then the
/// connect screens warn before credentials go out.
List<BaseUrlGuess> guessesForUserInput(String input, List<BaseUrlGuess> guesses) {
  final trimmed = canonicalizeBaseUrl(input);
  if (trimmed.isEmpty || hasUrlScheme(trimmed)) return guesses;
  final host = Uri.tryParse('http://$trimmed')?.host ?? '';
  if (isLocalOrPrivateHost(host)) return guesses;
  return [
    for (final guess in guesses)
      if (guess.scheme == 'https') guess,
  ];
}
