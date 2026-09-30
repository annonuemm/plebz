import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../i18n/strings.g.dart';
import '../media/library_copy_quality.dart';
import '../media/media_item.dart';
import '../media/media_version.dart';
import 'app_icon.dart';
import 'backend_badge.dart';
import 'focusable_list_tile.dart';

/// The best fassung a copy holds, as its display label ("4K HEVC MKV").
///
/// What tells two copies of one title apart is mostly resolution, which is
/// exactly the question two libraries holding the same movie pose (#1754), so
/// the row states it outright. Null when the backend reported no resolution at
/// all, rather than showing "Unknown".
String? bestVersionLabel(MediaItem item) {
  MediaVersion? best;
  for (final version in item.mediaVersions ?? const <MediaVersion>[]) {
    if (version.resolutionHeight == null) continue;
    if (best == null || version.resolutionHeight! > best.resolutionHeight!) best = version;
  }
  return best?.technicalLabel;
}

/// The name a copy is listed under: its library, else the server it sits on,
/// else the backend's product name. Shared so a copy is called the same thing
/// in the phone section and in the TV rail.
String libraryCopyName(MediaItem copy) =>
    copy.libraryTitle ?? copy.serverName ?? copy.backend.dialect?.productName ?? 'Plex';

/// The server a copy sits on, where [libraryCopyName] named its library —
/// null where the name already is the server's.
String? libraryCopyServer(MediaItem copy) => copy.libraryTitle == null ? null : copy.serverName;

/// One library holding a copy of a title: backend badge, library or server
/// name, and what quality it has there.
///
/// Shared by the Explore detail page ("In these libraries") and the library
/// detail page ("Also available on") so a copy reads the same either way.
class LibraryCopyTile extends StatelessWidget {
  const LibraryCopyTile({
    super.key,
    required this.copy,
    required this.onTap,
    this.focusNode,
    this.quality,
    this.showsQuality = true,
  });

  final MediaItem copy;
  final VoidCallback onTap;
  final FocusNode? focusNode;

  /// What the copy's own server said about its file — for a series, about one
  /// episode — where that was asked. Stands in for the resolution the lookup
  /// brought, which a series never has.
  final LibraryCopyQuality? quality;

  /// Whether the row says what quality the copy has. Explore's "In these
  /// libraries" does — it is the choice of which copy to open. A library
  /// title's "Also available on" names only where the copy is: which server
  /// it sits on is what that list is read for.
  final bool showsQuality;

  @override
  Widget build(BuildContext context) {
    // Plex copies carry their library title; MediaBrowser search-based lookup
    // only does when the ancestors call succeeded, so fall back to the server
    // name alone. The subtitle carries whatever else tells two copies apart.
    final measured = quality;
    final details = [
      if (showsQuality)
        if (measured != null && measured.labels.isNotEmpty) measured.labels.join(' · ') else ?bestVersionLabel(copy),
      if (measured?.episodes case final int episodes) t.explore.episodeCount(n: episodes),
      ?libraryCopyServer(copy),
    ];
    return FocusableListTile(
      focusNode: focusNode,
      leading: BackendBadge(backend: copy.backend, size: 24),
      title: Text(libraryCopyName(copy)),
      subtitle: details.isEmpty ? null : Text(details.join(' • ')),
      trailing: const AppIcon(Symbols.chevron_right_rounded, fill: 1),
      onTap: onTap,
    );
  }
}
