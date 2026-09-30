/// The archive window to assume when a provider offers one without saying how
/// far back it goes. Seven days is what most panels serve and what the
/// established players assume; the per-source setting overrides it.
const kDefaultIptvCatchupDays = 7;

/// How a provider addresses its archive ("catch-up", "timeshift", "replay").
///
/// There is no standard here, only conventions that grew up beside each other,
/// so the mode is a choice rather than something the app can always infer. What
/// a source declares is read first ([IptvCatchupMode.automatic]); an explicit
/// mode overrules it, for the providers that ship an archive without saying so
/// or that declare one shape and serve another.
enum IptvCatchupMode {
  /// Take the provider at its word: `catchup="…"` on a playlist entry, or the
  /// panel's own archive flag for Xtream.
  automatic,

  /// Never offer an archive, whatever the source claims.
  off,

  /// Xtream Codes: `/timeshift/{user}/{pass}/{minutes}/{Y-m-d:H-M}/{id}.ts`.
  xtream,

  /// The live URL with the archive window as query parameters
  /// (`?utc=…&lutc=…`), or the entry's own `catchup-source` when it has one.
  query,

  /// The entry's `catchup-source` glued onto the live URL as-is.
  append,

  /// Flussonic: the last path segment carries the window
  /// (`index.m3u8` → `index-{start}-{duration}.m3u8`).
  flussonic;

  /// Whether this mode can build a URL on its own.
  bool get isExplicit => this != IptvCatchupMode.automatic && this != IptvCatchupMode.off;
}

/// What one channel's playlist entry or panel row says about its archive.
class IptvCatchupInfo {
  const IptvCatchupInfo({this.declaredMode, this.source, this.days});

  /// The `catchup`/`catchup-type` attribute, lowercased, as written.
  final String? declaredMode;

  /// The `catchup-source` template, when the entry carries one.
  final String? source;

  /// How far back the archive goes, in days.
  final int? days;

  bool get isEmpty => declaredMode == null && source == null && days == null;

  /// The mode this entry declares, or null when it declares none.
  ///
  /// `default` is the odd one out: it means "use `catchup-source`", and only
  /// falls back to the query form when no source was given — which is exactly
  /// what [IptvCatchupMode.query] does.
  IptvCatchupMode? get resolvedMode => switch (declaredMode) {
    'xc' || 'xtream' || 'xtream-codes' => IptvCatchupMode.xtream,
    'append' => IptvCatchupMode.append,
    'default' || 'shift' || 'timeshift' || 'utc' => IptvCatchupMode.query,
    'flussonic' || 'flussonic-hls' || 'flussonic-ts' || 'fs' => IptvCatchupMode.flussonic,
    // A window without a form still says there is an archive, and the query
    // form is what a playlist that names no other means — the same reading
    // the established players give it.
    _ => days != null ? IptvCatchupMode.query : null,
  };
}

/// How many days of archive one channel has, or null when it has none.
///
/// Three sources of truth, most specific first: what the channel's own entry
/// declares, what the panel reports for it, and the per-source fallback for
/// providers that serve an archive without ever stating its depth. An explicit
/// mode is itself an assertion that there is one — that is what picking it is
/// for — so it does not need the provider's agreement.
int? iptvCatchupWindowDays({required IptvCatchupMode mode, IptvCatchupInfo? info, int? providerDays, int? sourceDays}) {
  if (mode == IptvCatchupMode.off) return null;
  final declared = info?.resolvedMode != null || providerDays != null;
  if (!mode.isExplicit && !declared) return null;
  return info?.days ?? providerDays ?? sourceDays ?? kDefaultIptvCatchupDays;
}

/// Build the URL that plays [start] from the archive.
///
/// [liveUrl] is where the channel plays live, which every convention except
/// Xtream's is derived from. [durationSeconds] is how much to serve — the
/// programme's length, since both Xtream and Flussonic address a window rather
/// than a point. [now] is the live edge, which some providers want alongside
/// the start so they can tell an archive request from a seek.
///
/// Returns null when the mode cannot build anything for this channel, which is
/// a refusal to guess: a wrong archive URL plays the live edge or an error, and
/// both look to the viewer like the app losing their place.
String? buildIptvCatchupUrl({
  required IptvCatchupMode mode,
  required String liveUrl,
  required DateTime start,
  required int durationSeconds,
  required DateTime now,
  IptvCatchupInfo? info,
  String? xtreamRoot,
  String? xtreamUsername,
  String? xtreamPassword,
}) {
  final effective = mode == IptvCatchupMode.automatic ? info?.resolvedMode : mode;
  if (effective == null || effective == IptvCatchupMode.off) return null;

  final template = info?.source?.trim();

  switch (effective) {
    case IptvCatchupMode.xtream:
      if (xtreamRoot == null || xtreamUsername == null || xtreamPassword == null) return null;
      // The stream id and the container come out of the live URL
      // (`…/live/user/pass/12345.ts`) rather than being passed in: a channel
      // merged from several playlist entries has one id per copy, and the
      // copy that is playing is the one whose URL this is.
      final stream = _lastSegment(liveUrl);
      if (stream == null) return null;
      // Minutes, and the panel's own date shape: `2026-08-30:20-15`. Local
      // time, because that is what a panel serves its archive in and what the
      // established players send.
      final minutes = (durationSeconds / 60).ceil().clamp(1, 24 * 60);
      final stamp =
          '${_pad(start.year, 4)}-${_pad(start.month)}-${_pad(start.day)}:${_pad(start.hour)}-${_pad(start.minute)}';
      return '$xtreamRoot/timeshift/$xtreamUsername/$xtreamPassword/$minutes/$stamp/${stream.name}${stream.extension}';

    case IptvCatchupMode.append:
      if (template == null || template.isEmpty) return null;
      return '$liveUrl${_expand(template, start: start, durationSeconds: durationSeconds, now: now)}';

    case IptvCatchupMode.query:
      if (template != null && template.isNotEmpty) {
        final expanded = _expand(template, start: start, durationSeconds: durationSeconds, now: now);
        // A source that is a whole URL replaces the live one; a bare query or
        // fragment is glued on.
        if (expanded.startsWith('http://') || expanded.startsWith('https://')) return expanded;
        return '$liveUrl$expanded';
      }
      final separator = liveUrl.contains('?') ? '&' : '?';
      final startEpoch = start.millisecondsSinceEpoch ~/ 1000;
      final nowEpoch = now.millisecondsSinceEpoch ~/ 1000;
      return '$liveUrl${separator}utc=$startEpoch&lutc=$nowEpoch';

    case IptvCatchupMode.flussonic:
      return _flussonicUrl(liveUrl, start: start, durationSeconds: durationSeconds);

    case IptvCatchupMode.automatic || IptvCatchupMode.off:
      return null;
  }
}

/// Rewrite a Flussonic live URL to its archive form.
///
/// The window rides on the last path segment: `.../index.m3u8` becomes
/// `.../index-{start}-{duration}.m3u8`, and the same for `mono.m3u8` or a bare
/// `.ts`. A URL with no segment to rewrite gets none back rather than a guess.
String? _flussonicUrl(String liveUrl, {required DateTime start, required int durationSeconds}) {
  final uri = Uri.tryParse(liveUrl);
  if (uri == null || uri.pathSegments.isEmpty) return null;

  final segments = List<String>.of(uri.pathSegments);
  final last = segments.last;
  if (last.isEmpty) return null;

  final startEpoch = start.millisecondsSinceEpoch ~/ 1000;
  final dot = last.lastIndexOf('.');
  final name = dot == -1 ? last : last.substring(0, dot);
  final extension = dot == -1 ? '' : last.substring(dot);
  segments[segments.length - 1] = '$name-$startEpoch-$durationSeconds$extension';

  return uri.replace(pathSegments: segments).toString();
}

/// Fill a `catchup-source` template.
///
/// Both spellings are in the wild — `${start}` and `{start}` — and providers
/// mix them inside one string, so both are accepted. An unknown placeholder is
/// left standing: a provider-specific token this app does not know is still
/// more likely to work verbatim than replaced with nothing.
String _expand(String template, {required DateTime start, required int durationSeconds, required DateTime now}) {
  final startEpoch = start.millisecondsSinceEpoch ~/ 1000;
  final nowEpoch = now.millisecondsSinceEpoch ~/ 1000;

  final values = <String, String>{
    'start': '$startEpoch',
    'utc': '$startEpoch',
    'utcstart': '$startEpoch',
    'timestamp': '$startEpoch',
    'lutc': '$nowEpoch',
    'now': '$nowEpoch',
    'end': '${startEpoch + durationSeconds}',
    'utcend': '${startEpoch + durationSeconds}',
    'offset': '${nowEpoch - startEpoch}',
    'duration': '$durationSeconds',
    'dur': '$durationSeconds',
    'durmin': '${(durationSeconds / 60).ceil()}',
    'Y': _pad(start.year, 4),
    'm': _pad(start.month),
    'd': _pad(start.day),
    'H': _pad(start.hour),
    'M': _pad(start.minute),
    'S': _pad(start.second),
  };

  return template.replaceAllMapped(RegExp(r'\$?\{([A-Za-z_]+)\}'), (match) {
    final key = match.group(1)!;
    return values[key] ?? values[key.toLowerCase()] ?? match.group(0)!;
  });
}

/// The last path segment of [url], split into name and extension.
({String name, String extension})? _lastSegment(String url) {
  final segments = Uri.tryParse(url)?.pathSegments;
  if (segments == null || segments.isEmpty) return null;
  final last = segments.last;
  if (last.isEmpty) return null;
  final dot = last.lastIndexOf('.');
  return dot == -1 ? (name: last, extension: '') : (name: last.substring(0, dot), extension: last.substring(dot));
}

String _pad(int value, [int width = 2]) => value.toString().padLeft(width, '0');
