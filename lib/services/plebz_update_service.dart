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
  });

  final String tag;
  final String title;
  final String notes;

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
  }) : _client = client ?? http.Client(),
       _channel = channel ?? const MethodChannel('com.plebz/update_installer'),
       _downloadDirectory = downloadDirectory ?? getTemporaryDirectory;

  final http.Client _client;
  final MethodChannel _channel;
  final Future<Directory> Function() _downloadDirectory;

  /// "owner/repository" on GitHub; [plebzReleaseRepository] unless a test says otherwise.
  final String repository;

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
      notes: notesForApp(json['body'] is String ? json['body'] as String : ''),
      build:
          buildNumberOf(tag) ?? buildNumberOf(title) ?? assets.map((a) => buildNumberOf(a.name)).nonNulls.firstOrNull,
      assets: assets,
    );
  }

  /// The part of a release body the app shows. GitHub shows the English
  /// notes; the German ones the app speaks follow them inside an HTML comment
  /// (`<!-- de` … `-->`, see scripts/whats_new_section.py), which GitHub does
  /// not render. Without that comment the body is shown as it stands: older
  /// releases are German throughout, 1.3.0's is English alone.
  static String notesForApp(String body) {
    final german = RegExp(r'<!--[ \t]*de[ \t]*\r?\n([\s\S]*?)-->').firstMatch(body);
    return german == null ? body : german.group(1)!.trim();
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

  /// Downloads [asset] into the app's cache and checks it against the digest
  /// GitHub published. Throws on a failed download or a mismatch.
  Future<File> download(PlebzReleaseAsset asset, {void Function(double progress)? onProgress}) async {
    final directory = Directory(p.join((await _downloadDirectory()).path, 'updates'));
    if (directory.existsSync()) directory.deleteSync(recursive: true);
    directory.createSync(recursive: true);
    final file = File(p.join(directory.path, p.basename(asset.name)));

    final request = http.Request('GET', asset.url)..headers['User-Agent'] = 'Plebz';
    final response = await _client.send(request);
    if (response.statusCode != 200) {
      throw HttpException('Update download failed (${response.statusCode})', uri: asset.url);
    }
    final total = response.contentLength ?? asset.size;
    final sink = file.openWrite();
    final hashInput = _DigestSink();
    final hasher = sha256.startChunkedConversion(hashInput);
    var received = 0;
    try {
      await for (final chunk in response.stream) {
        sink.add(chunk);
        hasher.add(chunk);
        received += chunk.length;
        if (total > 0) onProgress?.call(received / total);
      }
    } finally {
      await sink.close();
      hasher.close();
    }
    final expected = asset.sha256;
    if (expected != null && hashInput.value.toString() != expected) {
      file.deleteSync();
      throw const FormatException('The downloaded update does not match the published checksum');
    }
    return file;
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
