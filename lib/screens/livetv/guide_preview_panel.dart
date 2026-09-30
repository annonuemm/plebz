import 'package:flutter/material.dart';

import '../../i18n/strings.g.dart';
import '../../models/livetv_channel.dart';
import '../../models/livetv_program.dart';
import '../../theme/mono_tokens.dart';
import '../../widgets/fitted_metadata_line.dart';
import '../../utils/formatters.dart';
import 'guide_preview_player.dart';

/// The band above the guide grid: a live picture on the left, what is on the
/// channel the cursor stands on to the right of it.
///
/// The proportions follow what a guide is read for. The picture is small
/// enough that the grid keeps most of the screen, and wide enough to be worth
/// looking at; the text beside it is where the eye goes while travelling the
/// grid, so it gets the rest of the width rather than a column of its own.
class GuidePreviewPanel extends StatelessWidget {
  /// The channel the preview plays. Null leaves the picture dark — nothing is
  /// tuned until a channel is chosen.
  final LiveTvChannel? previewChannel;

  /// What the cursor stands on, which is not necessarily what is playing.
  final LiveTvChannel? focusedChannel;
  final LiveTvProgram? focusedProgram;

  final GlobalKey<GuidePreviewPlayerState>? playerKey;

  /// Share of the guide's height this band takes.
  ///
  /// The rest belongs to the grid, and how many channels fit there is what a
  /// guide is judged by — so this is as small as the picture and the text can
  /// live with, not as large as they would like.
  static const double heightFraction = 0.30;

  /// The most of the band's width the picture may take. It is normally
  /// narrower: the height decides, and the width follows from 16:9. This is
  /// only the guard for a band that is tall relative to how wide it is.
  static const double maxPictureWidthFraction = 0.45;

  const GuidePreviewPanel({
    super.key,
    required this.previewChannel,
    required this.focusedChannel,
    required this.focusedProgram,
    this.playerKey,
  });

  @override
  Widget build(BuildContext context) {
    const padding = EdgeInsets.fromLTRB(16, 12, 16, 12);
    return LayoutBuilder(
      builder: (context, constraints) {
        // The height is what is given; the width follows from it. Sizing the
        // other way round and asking for an aspect ratio does nothing — the
        // row hands its children a tight height, so the box would simply be
        // as tall as the band however wide it was made.
        final pictureHeight = (constraints.maxHeight - padding.vertical).clamp(0.0, double.infinity);
        final pictureWidth = (pictureHeight * 16 / 9).clamp(
          0.0,
          (constraints.maxWidth - padding.horizontal) * maxPictureWidthFraction,
        );
        return Padding(
          padding: padding,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: pictureWidth,
                height: pictureHeight,
                child: GuidePreviewPlayer(key: playerKey, channel: previewChannel),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: SizedBox(
                  height: pictureHeight,
                  child: _Details(channel: focusedChannel, program: focusedProgram),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Details extends StatelessWidget {
  final LiveTvChannel? channel;
  final LiveTvProgram? program;

  const _Details({required this.channel, required this.program});

  /// The name of what is on, in the face this theme gives to a title.
  ///
  /// "Ocker" sets the name of something you can watch in the serif and nothing
  /// else in it — a programme beside the preview is exactly that, and leaving
  /// it in the interface face made this one panel read as a different app from
  /// every other place the same programme is named.
  ///
  /// A step up in size comes with it, and the bold goes: Instrument Serif
  /// ships one weight, and asking for another has the renderer fake it.
  TextStyle? _titleStyle(BuildContext context) {
    final theme = Theme.of(context);
    final base = theme.textTheme.titleMedium;
    final redesign = Theme.of(context).extension<MonoTokens>()?.displayFontFamily != null;
    if (!redesign) return base?.copyWith(fontWeight: FontWeight.w600);
    // The title of the programme, in the same bold the redesign gives every
    // other title — see [OckerType.detailTitle] for why it is not the serif it
    // was drawn with.
    return TextStyle(
      fontWeight: FontWeight.w700,
      fontSize: 24,
      height: 1.08,
      letterSpacing: -0.6,
      color: base?.color ?? theme.colorScheme.onSurface,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final program = this.program;
    if (program == null) {
      return Align(
        alignment: Alignment.topLeft,
        child: Text(
          channel?.displayName ?? '',
          style: _titleStyle(context),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      );
    }

    final is24Hour = MediaQuery.alwaysUse24HourFormatOf(context);
    final muted = theme.colorScheme.onSurface.withValues(alpha: 0.7);

    // The block reads at the grid's size: it is the same schedule, and text
    // twice as large beside it reads as a different page. Only the title
    // steps up, and only by one.
    final bodyStyle = theme.textTheme.bodySmall?.copyWith(color: muted);
    // A broadcast window and what is left of it are timecodes, which is the
    // one job this design gives the mono face. The channel name and the
    // description beside them are words and stay where they are.
    final timeStyle = bodyStyle == null ? null : monoFacts(context, bodyStyle);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(program.displayTitle, style: _titleStyle(context), maxLines: 2, overflow: TextOverflow.ellipsis),
        const SizedBox(height: 6),
        Row(
          children: [
            if (program.startTime case final start? when program.endTime != null)
              Text(
                '${formatClockTime(start, is24Hour: is24Hour)} – ${formatClockTime(program.endTime!, is24Hour: is24Hour)}',
                style: timeStyle,
              ),
            // The bar is the answer to "have I missed much of this", which is
            // the question a guide is opened with.
            if (program.isCurrentlyAiring) ...[
              const SizedBox(width: 12),
              SizedBox(
                width: 90,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(flatRadius(context, 999)),
                  child: LinearProgressIndicator(value: program.progress, minHeight: 4),
                ),
              ),
              const SizedBox(width: 12),
              Text(t.discover.minutesLeft(minutes: _minutesLeft(program)), style: timeStyle),
            ] else if (program.durationMinutes > 0) ...[
              const SizedBox(width: 12),
              Text('${program.durationMinutes} min', style: timeStyle),
            ],
            // On the same line as the times: it belongs with them, and a line
            // of its own cost the description a line it could use.
            if (channel?.displayName case final name? when name.isNotEmpty) ...[
              const SizedBox(width: 12),
              Flexible(
                child: Text(
                  '· $name',
                  style: theme.textTheme.bodyMedium?.copyWith(color: muted),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ],
        ),
        if (program.summary case final summary? when summary.trim().isNotEmpty) ...[
          const SizedBox(height: 10),
          Expanded(
            child: Text(summary.trim(), style: bodyStyle?.copyWith(height: 1.35), overflow: TextOverflow.fade),
          ),
        ],
      ],
    );
  }

  static int _minutesLeft(LiveTvProgram program) {
    final end = program.endTime;
    if (end == null) return 0;
    final left = end.difference(DateTime.now()).inMinutes;
    return left < 0 ? 0 : left;
  }
}
