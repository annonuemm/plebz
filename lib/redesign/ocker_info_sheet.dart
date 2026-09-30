import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../focus/dpad_navigator.dart';
import '../media/media_item.dart';
import '../media/media_item_types.dart';
import '../theme/mono_tokens.dart';
import '../utils/formatters.dart';
import '../widgets/overlay_sheet.dart' show OverlaySheetController;
import '../widgets/tv_spotlight_background.dart' show SpotlightSummary;
import 'ocker_detail_panel.dart' show OckerFacts, OckerProgress;
import 'ocker_enriched_item.dart';
import 'ocker_skin.dart';
import 'ocker_type.dart';

/// How far into a title the viewer already is, or null where that is not a
/// question about it — nothing started, or nothing with a running time.
double? ockerWatchProgress(MediaItem item) {
  final duration = item.durationMs;
  final offset = item.viewOffsetMs;
  if (duration == null || duration <= 0 || offset == null || offset <= 0) return null;
  return (offset / duration).clamp(0.0, 1.0);
}

/// What the INFO key shows on a poster.
///
/// A row is posters and nothing else, and a grid has no room beside a cell.
/// The question "what is this?" does not go away with that, so the key that
/// asks it gets an answer of its own: the words, in a panel over the page,
/// gone again on the next press.
///
/// Words only. No wordmark, no still, no backdrop: the picture is already on
/// the screen behind this, under the cursor, and a second copy of it here would
/// be the one thing this panel is not for.
Future<void> showOckerInfoSheet(
  BuildContext context, {
  required MediaItem item,
  required OckerClientResolver resolveClient,
}) {
  final scale = ockerScale(context);
  return OverlaySheetController.showAdaptive<void>(
    context,
    alignment: Alignment.center,
    constraints: BoxConstraints(
      maxWidth: (MediaQuery.sizeOf(context).width * 0.56).clamp(320.0, 900.0),
      maxHeight: MediaQuery.sizeOf(context).height * 0.8,
    ),
    builder: (context) => Padding(
      padding: EdgeInsets.symmetric(horizontal: 36 * scale, vertical: 32 * scale),
      child: _OckerInfo(item: item, resolveClient: resolveClient),
    ),
  );
}

class _OckerInfo extends StatelessWidget {
  final MediaItem item;
  final OckerClientResolver resolveClient;

  const _OckerInfo({required this.item, required this.resolveClient});

  @override
  Widget build(BuildContext context) {
    // A catalogue row carries a poster and a title and nothing else, so it is
    // filled out from its own provider first — otherwise this panel is a name
    // over an empty space on the whole of Explore.
    return OckerEnrichedItem(item: item, builder: (context, filled, resolving) => _build(context, filled, resolving));
  }

  Widget _build(BuildContext context, MediaItem item, bool resolving) {
    final tk = tokens(context);
    final type = OckerType.of(context);
    final scale = ockerScale(context);
    final episode = item.isEpisode ? formatSeasonEpisodeLabel(item.parentIndex, item.index) : null;
    final progress = ockerWatchProgress(item);
    final subtitle = _subtitleOf(item);

    return Focus(
      autofocus: true,
      // The key that opened it closes it, which is what a viewer expects of a
      // key that shows and hides something. BACK is the sheet's own job.
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        if (!event.logicalKey.isInfoKey && event.logicalKey != LogicalKeyboardKey.keyI) {
          return KeyEventResult.ignored;
        }
        Navigator.of(context).maybePop();
        return KeyEventResult.handled;
      },
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: .start,
          mainAxisSize: .min,
          children: [
            Text(item.displayTitle, style: type.detailTitle(withGroupBar: true).copyWith(color: tk.ink(1))),
            if (subtitle != null) ...[
              SizedBox(height: 6 * scale),
              Text(subtitle, style: type.detailSubtitle(withGroupBar: true).copyWith(color: tk.ink(0.55))),
            ],
            SizedBox(height: 18 * scale),
            OckerFacts(item: item, opacity: 0.86, leading: episode, sizeScale: OckerType.readingScale),
            if (progress != null) ...[
              SizedBox(height: 18 * scale),
              OckerProgress(item: item, fraction: progress, opacity: 0.86, barWidth: 260),
            ],
            SizedBox(height: 20 * scale),
            // As long as it is. This panel exists to be read and has a scroller
            // behind it, so there is no reason to cut the description here the
            // way a block on a photograph has to.
            SpotlightSummary(
              item: item,
              client: resolveClient(item),
              summary: item.summary,
              allowFillIn: !item.shouldHideSpoiler,
              gap: 0,
              maxLines: 20,
              style: type.synopsis.copyWith(color: tk.ink(0.92)),
            ),
          ],
        ),
      ),
    );
  }

  /// The second line: an episode's own name, or a film's other title.
  static String? _subtitleOf(MediaItem item) {
    if (!item.isEpisode) return null;
    // An episode's own name, where the line above it is the series'.
    final title = item.title?.trim();
    if (title == null || title.isEmpty || title == item.displayTitle.trim()) return null;
    return title;
  }
}
