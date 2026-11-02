import 'package:flutter/foundation.dart';

import '../media/ids.dart';
import '../media/media_item.dart';
import '../media/media_server_client.dart';
import '../utils/app_logger.dart';

/// Which servers permit the signed-in account to download media.
///
/// The app used to ask nobody: it built the media URL and fetched it, and the
/// file came down because the same URL serves playback. Plex enforces its
/// "Allow Downloads" setting in its own clients rather than at that URL, so a
/// client that never asks never notices the restriction. This service is the
/// asking.
///
/// **A silent server is not a refusal, and not a permission either.** Only an
/// explicit answer changes anything: a failed probe, an older server, a backend
/// without the notion all leave downloads as they were. Restricting on silence
/// would strand every setup whose server simply does not answer the question;
/// lifting a refusal on silence let one slow answer undo it.
class DownloadPermissionService extends ChangeNotifier {
  DownloadPermissionService._();

  static final DownloadPermissionService instance = DownloadPermissionService._();

  /// How long an answer from [confirm] holds: a Retry all asks once.
  static const _confirmedFor = Duration(seconds: 30);

  /// Servers that answered "no". Absence means "not told otherwise".
  final Set<String> _blocked = {};

  /// When each server was last asked by [confirm].
  final Map<String, DateTime> _confirmedAt = {};

  /// Whether media may be downloaded from [serverId].
  bool allows(String serverId) => !_blocked.contains(serverId);

  /// Whether [item]'s own server permits downloading it. An item with no
  /// server (a downloaded file read offline) is nobody's to forbid.
  bool allowsItem(MediaItem item) {
    final id = serverIdOrNull(item.serverId);
    return id == null || allows(id.value);
  }

  /// Whether any connected server has refused. Drives the wording where the
  /// UI explains why a download is not on offer.
  bool get hasBlockedServer => _blocked.isNotEmpty;

  /// Asks [client] and remembers the answer.
  Future<void> refreshFor(MediaServerClient client) async {
    final id = client.serverId.value;
    bool? allowed;
    try {
      allowed = await client.fetchDownloadsAllowed();
    } catch (error) {
      // Includes a fake client in a test that does not implement the call.
      appLogger.d('Download permission probe failed for $id', error: error);
      return;
    }
    _apply(id, allowed);
  }

  /// Whether [client]'s server permits downloads right now, for the moment one
  /// is about to start. What [allows] holds dates from the last connect, and an
  /// admin can withdraw downloads while the app stays open.
  Future<bool> confirm(MediaServerClient client) async {
    final id = client.serverId.value;
    final now = DateTime.now();
    final asked = _confirmedAt[id];
    if (asked == null || now.difference(asked) >= _confirmedFor) {
      _confirmedAt[id] = now;
      await refreshFor(client);
    }
    return allows(id);
  }

  /// Asks every server in [clients], and forgets any server no longer among
  /// them — a disconnected server must not keep blocking downloads that a
  /// reconnect might permit.
  Future<void> refreshAll(Iterable<MediaServerClient> clients) async {
    final present = {for (final client in clients) client.serverId.value};
    final removed = _blocked.where((id) => !present.contains(id)).toList();
    for (final id in removed) {
      _blocked.remove(id);
    }
    final before = _blocked.length;
    await Future.wait([for (final client in clients) refreshFor(client)]);
    if (removed.isNotEmpty && _blocked.length == before) notifyListeners();
  }

  void _apply(String serverId, bool? allowed) {
    if (allowed == null) return;
    final changed = allowed ? _blocked.remove(serverId) : _blocked.add(serverId);
    if (changed) {
      appLogger.i('Downloads ${allowed ? 'permitted' : 'blocked'} on server $serverId');
      notifyListeners();
    }
  }

  @visibleForTesting
  void debugSetAllowed(String serverId, bool? allowed) => _apply(serverId, allowed);

  @visibleForTesting
  void debugReset() {
    _blocked.clear();
    _confirmedAt.clear();
    notifyListeners();
  }
}
