import 'package:flutter/material.dart';

import '../redesign/ocker_skin.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../media/media_item.dart';
import '../media/media_item_types.dart';
import '../media/media_kind.dart';
import '../services/settings_service.dart';
import '../theme/mono_tokens.dart';
import 'app_icon.dart';
import 'media_progress_bar.dart';
import 'unwatched_count_badge.dart';

/// Size preset for [WatchedIndicator]: [standard] for grid/poster cards,
/// [compact] for dense surfaces (folder tree rows, episode thumbnails).
/// Add a preset here instead of hand-rolling a new overlay variant.
enum WatchedIndicatorSize {
  standard(checkInset: 4, checkPadding: 4, checkIconSize: 16, barRadius: 8, barMinHeight: 4, floatingBarHeight: 5),
  compact(checkInset: 3, checkPadding: 2, checkIconSize: 12, barRadius: 6, barMinHeight: 3, floatingBarHeight: 3);

  const WatchedIndicatorSize({
    required this.checkInset,
    required this.checkPadding,
    required this.checkIconSize,
    required this.barRadius,
    required this.barMinHeight,
    required this.floatingBarHeight,
  });

  final double checkInset;
  final double checkPadding;
  final double checkIconSize;
  final double barRadius;
  final double barMinHeight;

  /// The bar's height where it floats inside the picture (the redesigns).
  final double floatingBarHeight;
}

/// Watched/progress overlay for media artwork: watched checkmark,
/// unwatched-count pill (shows/seasons), active-progress bar, and season
/// completion bar. The single implementation behind every surface that
/// stamps watch state onto a poster/thumbnail. Callers that must react to
/// [SettingsService.showWatchedIndicators] or [SettingsService.showUnwatchedCount]
/// flipping wrap themselves in a [SettingsBuilder] on those prefs.
class WatchedIndicator extends StatelessWidget {
  final MediaItem item;
  final WatchedIndicatorSize size;

  /// Overrides the settings read for the unwatched-count pill — pass it when
  /// the caller already watches [SettingsService.showUnwatchedCount] so pill
  /// visibility updates reactively with the caller's rebuilds.
  final bool? showUnwatchedCount;

  const WatchedIndicator({
    super.key,
    required this.item,
    this.size = WatchedIndicatorSize.standard,
    this.showUnwatchedCount,
  });

  @override
  Widget build(BuildContext context) {
    final bool showCount = showUnwatchedCount ?? SettingsService.instance.read(SettingsService.showUnwatchedCount);
    final bool showWatched = SettingsService.instance.read(SettingsService.showWatchedIndicators);
    final hasActiveProgress = item.hasActiveProgress;
    final unwatched = item.unwatchedCount;
    // The redesigns float the bar inside the picture, clear of its edges and
    // round at both ends (the viewer's call, 2026-10-10). Along the bottom
    // edge it lost its dark track wherever a poster ran dark at the foot, and
    // read as a loose stroke under the picture.
    final floating = ockerGlass(context);
    final barRadius = BorderRadius.only(
      bottomLeft: Radius.circular(flatRadius(context, size.barRadius)),
      bottomRight: Radius.circular(flatRadius(context, size.barRadius)),
    );

    return Stack(
      children: [
        // Watched checkmark
        if (showWatched && item.isWatched && !hasActiveProgress)
          Positioned(
            top: size.checkInset,
            right: size.checkInset,
            child: Container(
              padding: EdgeInsets.all(size.checkPadding),
              decoration: BoxDecoration(
                color: tokens(context).text,
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 4)],
              ),
              child: AppIcon(Symbols.check_rounded, fill: 1, color: tokens(context).bg, size: size.checkIconSize),
            ),
          ),
        // Unwatched count for shows/seasons
        if (showCount &&
            !item.isWatched &&
            (item.kind == MediaKind.show || item.kind == MediaKind.season) &&
            unwatched != null &&
            unwatched > 0)
          Positioned(
            top: size.checkInset,
            right: size.checkInset,
            // No per-preset size: the count is one element with one size,
            // wherever it appears.
            child: UnwatchedCountBadge(count: unwatched),
          ),
        // Progress bar for partially watched content (episodes/movies)
        if (hasActiveProgress && floating)
          _floatingBar(
            MediaProgressBar(
              viewOffset: item.viewOffsetMs!,
              duration: item.durationMs!,
              minHeight: size.floatingBarHeight,
            ),
          )
        else if (hasActiveProgress)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: ClipRRect(
              borderRadius: barRadius,
              child: MediaProgressBar(
                viewOffset: item.viewOffsetMs!,
                duration: item.durationMs!,
                minHeight: size.barMinHeight,
              ),
            ),
          ),
        // Progress bar for seasons (viewed leaves / total leaves).
        if (item.isSeason && item.isPartiallyWatched && floating)
          _floatingBar(
            LinearProgressIndicator(
              value: item.leafWatchFraction,
              backgroundColor: MediaProgressBar.posterTrack,
              valueColor: AlwaysStoppedAnimation<Color>(MediaProgressBar.redesignFill(context)),
              minHeight: size.floatingBarHeight,
            ),
          )
        else if (item.isSeason && item.isPartiallyWatched)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: ClipRRect(
              borderRadius: barRadius,
              child: LinearProgressIndicator(
                value: item.leafWatchFraction,
                backgroundColor: tokens(context).outline,
                valueColor: AlwaysStoppedAnimation<Color>(
                  isOcker(context) ? tokens(context).accent : Theme.of(context).colorScheme.primary,
                ),
                minHeight: size.barMinHeight,
              ),
            ),
          ),
      ],
    );
  }

  /// [bar] floating at the foot of the picture, a little in from its sides and
  /// less from the bottom, so it sits low (the viewer's call) — the room grows
  /// with the picture, so a thumbnail keeps it in proportion.
  Widget _floatingBar(Widget bar) => Positioned.fill(
    child: LayoutBuilder(
      builder: (context, constraints) {
        final room = (constraints.maxWidth * 0.07).clamp(5.0, 14.0);
        return Padding(
          padding: EdgeInsets.fromLTRB(room, 0, room, room * 0.55),
          child: Align(
            alignment: Alignment.bottomCenter,
            child: ClipRRect(borderRadius: BorderRadius.circular(size.floatingBarHeight / 2), child: bar),
          ),
        );
      },
    ),
  );
}
