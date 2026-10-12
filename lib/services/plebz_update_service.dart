import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../utils/fork_identity.dart';

/// GitHub answered the release query, but not with a release.
class PlebzUpdateCheckException implements Exception {
  const PlebzUpdateCheckException(this.statusCode);

  final int statusCode;

  @override
  String toString() => 'GitHub answered HTTP $statusCode';
}

/// One downloadable file of a Plebz release on GitHub.
/// The viewer stopped the update download.
class PlebzUpdateCancelled implements Exception {
  const PlebzUpdateCancelled();

  @override
  String toString() => 'PlebzUpdateCancelled';
}

class PlebzReleaseAsset {
  const PlebzReleaseAsset({required this.name, required this.url, required this.size, this.sha256});

  final String name;
  final Uri url;
  final int size;

  /// Lower-case hex, when GitHub reports a digest for the file.
  final String? sha256;
}

/// The newest published Plebz release.
class PlebzRelease {
  const PlebzRelease({
    required this.tag,
    required this.title,
    required this.notes,
    required this.build,
    required this.assets,
    this.important = false,
  });

  final String tag;
  final String title;
  final String notes;

  /// Offered whatever "Updates anbieten" says ([PlebzUpdateService.isImportantTag]).
  final bool important;

  /// The Android build number the release carries ("…+551" or "…build551"),
  /// which is what decides whether it is newer — never the version name.
  final int? build;
  final List<PlebzReleaseAsset> assets;
}

/// Plebz's own updates: the latest GitHub Release of [plebzReleaseRepository],
/// the APK for this device's processor, and Android's installer.
///
/// Updates cannot be silent for an app installed by hand: Android's installer
/// asks once per update, and Plebz must be allowed to install apps. What makes
/// this safe is Android itself — it refuses an APK not signed with the key of
/// the installed app — plus the file digest GitHub publishes, checked here.
class PlebzUpdateService {
  PlebzUpdateService({
    http.Client? client,
    MethodChannel? channel,
    Future<Directory> Function()? downloadDirectory,
    this.repository = plebzReleaseRepository,
    this.idleTimeout = downloadIdleTimeout,
  }) : _client = client ?? http.Client(),
       _channel = channel ?? const MethodChannel('com.plebz/update_installer'),
       _downloadDirectory = downloadDirectory ?? getTemporaryDirectory;

  final http.Client _client;
  final MethodChannel _channel;
  final Future<Directory> Function() _downloadDirectory;

  /// "owner/repository" on GitHub; [plebzReleaseRepository] unless a test says otherwise.
  final String repository;

  /// [downloadIdleTimeout] unless a test says otherwise.
  final Duration idleTimeout;

  void dispose() => _client.close();

  /// The latest release, or null when the repository has none yet.
  ///
  /// Throws when GitHub cannot be asked or answers with anything else — a
  /// refusal, a rate limit, a network that is not there. Those used to read
  /// as "nothing newer", which is a claim the app could not make.
  Future<PlebzRelease?> latestRelease() async {
    if (repository.isEmpty) return null;
    final response = await _client
        .get(
          Uri.parse('https://api.github.com/repos/$repository/releases/latest'),
          headers: const {'Accept': 'application/vnd.github+json', 'User-Agent': 'Plebz'},
        )
        .timeout(const Duration(seconds: 15));
    // GitHub's answer for a repository without a release.
    if (response.statusCode == 404) return null;
    if (response.statusCode != 200) throw PlebzUpdateCheckException(response.statusCode);
    final decoded = jsonDecode(response.body);
    return decoded is Map<String, dynamic> ? parseRelease(decoded) : null;
  }

  /// The newest published releases, newest first — drafts and pre-releases
  /// left out, as `releases/latest` leaves them out. For finding an important
  /// release that a newer, ordinary one followed. Throws as [latestRelease].
  Future<List<PlebzRelease>> recentReleases({int count = 20}) async {
    if (repository.isEmpty) return const [];
    final response = await _client
        .get(
          Uri.parse('https://api.github.com/repos/$repository/releases?per_page=$count'),
          headers: const {'Accept': 'application/vnd.github+json', 'User-Agent': 'Plebz'},
        )
        .timeout(const Duration(seconds: 15));
    if (response.statusCode == 404) return const [];
    if (response.statusCode != 200) throw PlebzUpdateCheckException(response.statusCode);
    final decoded = jsonDecode(response.body);
    if (decoded is! List) return const [];
    return [
      for (final raw in decoded)
        if (raw is Map<String, dynamic> && raw['draft'] != true && raw['prerelease'] != true) ?parseRelease(raw),
    ];
  }

  /// Whether a release tag marks an important update: `v1.22.2+779-wichtig`.
  ///
  /// The tag, not the body: a body line would reach every installed Plebz up
  /// to 1.22.1 as visible text in its update dialog, while the tag only ever
  /// gave them the build number, which reads the same with the suffix.
  static bool isImportantTag(String tag) => RegExp(r'[-_.](wichtig|important)$', caseSensitive: false).hasMatch(tag);

  static PlebzRelease? parseRelease(Map<String, dynamic> json) {
    final tag = json['tag_name'];
    if (tag is! String) return null;
    final title = json['name'] is String && (json['name'] as String).isNotEmpty ? json['name'] as String : tag;
    final assets = <PlebzReleaseAsset>[
      for (final raw in (json['assets'] as List?) ?? const [])
        if (raw is Map && raw['name'] is String && raw['browser_download_url'] is String)
          PlebzReleaseAsset(
            name: raw['name'] as String,
            url: Uri.parse(raw['browser_download_url'] as String),
            size: raw['size'] is int ? raw['size'] as int : 0,
            sha256: _sha256Of(raw['digest']),
          ),
    ];
    return PlebzRelease(
      tag: tag,
      title: title,
      // Empty since 1.3.1: the notes live in the app ("Was ist neu").
      notes: json['body'] is String ? json['body'] as String : '',
      build:
          buildNumberOf(tag) ?? buildNumberOf(title) ?? assets.map((a) => buildNumberOf(a.name)).nonNulls.firstOrNull,
      assets: assets,
      important: isImportantTag(tag),
    );
  }

  static String? _sha256Of(Object? digest) {
    if (digest is! String || !digest.startsWith('sha256:')) return null;
    final hex = digest.substring('sha256:'.length).toLowerCase();
    return RegExp(r'^[0-9a-f]{64}$').hasMatch(hex) ? hex : null;
  }

  /// The build number in "…+551", "…build551" or "(Build 551)".
  static int? buildNumberOf(String text) {
    final match = RegExp(r'(?:\+|build\s*)(\d+)', caseSensitive: false).firstMatch(text);
    return match == null ? null : int.tryParse(match.group(1)!);
  }

  static bool isNewer(PlebzRelease release, int currentBuild) => (release.build ?? -1) > currentBuild;

  /// The build number inside an installed APK's Android version code.
  ///
  /// A split APK does not carry the build as its version code: Flutter puts
  /// the processor in front, as `abi × 1000 + build` (arm32 1, arm64 2, x86_64
  /// 4), so build 556 installs as 1556, 2556 or 4556. Compared as it stands
  /// against a release's 557, no release was ever newer. A universal APK
  /// carries the bare build. Holds while builds stay under 1000, which is
  /// also where the split codes themselves would start to collide.
  static int buildFromVersionCode(int versionCode) => versionCode >= 1000 ? versionCode % 1000 : versionCode;

  /// The APK for the first of [supportedAbis] (the device's own order of
  /// preference) that the release has a file for. Matches the names
  /// `scripts/build_apk.sh` gives them: `…-arm64-…`, `…-arm32-…`, `…-x86_64-…`.
  static PlebzReleaseAsset? assetFor(List<PlebzReleaseAsset> assets, List<String> supportedAbis) {
    const labels = {'arm64-v8a': 'arm64', 'armeabi-v7a': 'arm32', 'x86_64': 'x86_64'};
    for (final abi in supportedAbis) {
      final label = labels[abi];
      if (label == null) continue;
      for (final asset in assets) {
        final name = asset.name.toLowerCase();
        if (name.endsWith('.apk') && name.contains('-$label-')) return asset;
      }
    }
    return null;
  }

  /// How long the download may go without a byte before it counts as failed.
  /// A phone that drops off the network mid-download otherwise waited on a
  /// response that never came, behind a dialog it could not leave.
  static const downloadIdleTimeout = Duration(seconds: 30);

  /// Downloads [asset] into the app's cache and checks it against the digest
  /// GitHub published. Throws on a failed or stalled download or a mismatch,
  /// and [PlebzUpdateCancelled] once [cancelled] completes; a file that did
  /// not finish is removed.
  Future<File> download(
    PlebzReleaseAsset asset, {
    void Function(double progress)? onProgress,
    Future<void>? cancelled,
  }) async {
    final directory = Directory(p.join((await _downloadDirectory()).path, 'updates'));
    if (directory.existsSync()) directory.deleteSync(recursive: true);
    directory.createSync(recursive: true);
    final file = File(p.join(directory.path, p.basename(asset.name)));

    final request = http.Request('GET', asset.url)..headers['User-Agent'] = 'Plebz';
    final response = await _sendOrCancel(request, cancelled);
    if (response.statusCode != 200) {
      throw HttpException('Update download failed (${response.statusCode})', uri: asset.url);
    }
    final total = response.contentLength ?? asset.size;
    final sink = file.openWrite();
    final hashInput = _DigestSink();
    final hasher = sha256.startChunkedConversion(hashInput);
    var received = 0;
    var complete = false;
    try {
      await for (final chunk in _untilCancelled(response.stream.timeout(idleTimeout), cancelled)) {
        sink.add(chunk);
        hasher.add(chunk);
        received += chunk.length;
        if (total > 0) onProgress?.call(received / total);
      }
      complete = true;
    } finally {
      await sink.close();
      hasher.close();
      if (!complete && file.existsSync()) file.deleteSync();
    }
    final expected = asset.sha256;
    if (expected != null && hashInput.value.toString() != expected) {
      file.deleteSync();
      throw const FormatException('The downloaded update does not match the published checksum');
    }
    return file;
  }

  Future<http.StreamedResponse> _sendOrCancel(http.Request request, Future<void>? cancelled) {
    final sent = _client.send(request).timeout(idleTimeout);
    if (cancelled == null) return sent;
    var gaveUp = false;
    // A response that arrives after the viewer gave up is let go unread.
    unawaited(
      sent.then((response) {
        if (gaveUp) unawaited(response.stream.listen(null).cancel());
      }, onError: (Object _) {}),
    );
    return Future.any([
      sent,
      cancelled.then<http.StreamedResponse>((_) {
        gaveUp = true;
        throw const PlebzUpdateCancelled();
      }),
    ]);
  }

  /// [source] until [cancelled] completes, which ends it with
  /// [PlebzUpdateCancelled] and lets go of [source] — also while it is waiting
  /// on a byte that is not coming.
  static Stream<List<int>> _untilCancelled(Stream<List<int>> source, Future<void>? cancelled) {
    if (cancelled == null) return source;
    late final StreamController<List<int>> controller;
    StreamSubscription<List<int>>? subscription;
    controller = StreamController<List<int>>(
      onListen: () {
        subscription = source.listen(controller.add, onError: controller.addError, onDone: controller.close);
        unawaited(
          cancelled.then((_) async {
            if (controller.isClosed) return;
            await subscription?.cancel();
            controller.addError(const PlebzUpdateCancelled());
            unawaited(controller.close());
          }),
        );
      },
      onPause: () => subscription?.pause(),
      onResume: () => subscription?.resume(),
      onCancel: () => subscription?.cancel(),
    );
    return controller.stream;
  }

  Future<bool> canInstall() async => await _channel.invokeMethod<bool>('canInstall') ?? false;

  Future<bool> openInstallPermission() async => await _channel.invokeMethod<bool>('openInstallPermission') ?? false;

  Future<bool> install(File apk) async => await _channel.invokeMethod<bool>('install', {'path': apk.path}) ?? false;
}

class _DigestSink implements Sink<Digest> {
  late Digest value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}

/// How often the start-up check may show an available update (Plebz). Only
/// with "Beim Start nach Updates suchen" on; asking by hand always shows it,
/// and an important release comes whatever is set here.
enum PlebzUpdateOffer {
  whenAvailable(null),
  weekly(Duration(days: 7)),
  biweekly(Duration(days: 14)),
  monthly(Duration(days: 30));

  const PlebzUpdateOffer(this.spacing);

  /// The least time between two offers; null offers at every start.
  final Duration? spacing;
}

/// Whether the start-up check shows an available update now.
///
/// GitHub is still asked at every start — that is what lets an [important]
/// release through at once — but the offer waits out [offer]'s spacing since
/// the last one ([lastOfferAtMs], 0 for never); a "Später" counts as one. A
/// last offer in the future, a clock set back, does not hold anything up.
bool plebzUpdateOfferDue({
  required PlebzUpdateOffer offer,
  required int lastOfferAtMs,
  required DateTime now,
  required bool important,
}) {
  final spacing = offer.spacing;
  if (important || spacing == null || lastOfferAtMs <= 0) return true;
  final last = DateTime.fromMillisecondsSinceEpoch(lastOfferAtMs);
  if (last.isAfter(now)) return true;
  return now.difference(last) >= spacing;
}
