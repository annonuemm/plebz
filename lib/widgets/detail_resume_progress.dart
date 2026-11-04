import 'dart:async';

import 'package:flutter/material.dart';

import '../i18n/strings.g.dart';
import '../media/media_item.dart';
import '../redesign/ocker_type.dart';
import '../theme/mono_tokens.dart';
import '../utils/formatters.dart';

/// How much of the title Play would resume is left (Plebz), under the play
/// button of a detail page: "Noch 1 Std 12 Min · bis 22:41", starting where
/// the button's play icon starts. How far in the viewer is, the button itself
/// shows — see [DetailResumeWash].
///
/// For a show it describes the episode the button continues, so the two
/// always agree. Takes no focus.
class DetailResumeProgress extends StatefulWidget {
  /// The item Play would start. Nothing is drawn unless it is part-watched.
  final MediaItem item;

  /// From the button's edge to its icon, so the line starts under it.
  final double leadingInset;

  /// Under a phone's centred header the line is centred too.
  final bool centered;

  const DetailResumeProgress({super.key, required this.item, this.leadingInset = 0, this.centered = false});

  /// Whether [item] has anything to show.
  static bool shows(MediaItem? item) => item != null && item.hasActiveProgress;

  /// The share of [item] already watched, 0 to 1.
  static double fractionOf(MediaItem item) =>
      ((item.viewOffsetMs ?? 0) / (item.durationMs ?? 1)).clamp(0.0, 1.0).toDouble();

  /// The type size at the reference scale — 22 on the v2 ramp, a step over
  /// the button's word: what the viewer reads from the sofa.
  static const double fontSize = 22;

  /// The line's height at [scale], for a header that budgets its rows.
  static double heightFor(double scale) => fontSize * 1.25 * scale;

  @override
  State<DetailResumeProgress> createState() => _DetailResumeProgressState();
}

class _DetailResumeProgressState extends State<DetailResumeProgress> {
  Timer? _minuteTick;

  @override
  void initState() {
    super.initState();
    _scheduleTick();
  }

  @override
  void dispose() {
    _minuteTick?.cancel();
    super.dispose();
  }

  /// The end time moves on while the page stands open: redrawn on each new
  /// minute, never more often.
  void _scheduleTick() {
    final now = DateTime.now();
    final toNextMinute = Duration(seconds: 60 - now.second, milliseconds: -now.millisecond);
    _minuteTick = Timer(toNextMinute, () {
      if (!mounted) return;
      setState(() {});
      _scheduleTick();
    });
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    if (!DetailResumeProgress.shows(item)) return const SizedBox.shrink();
    final tk = Theme.of(context).extension<MonoTokens>();
    final type = OckerType.of(context);
    final scale = type.scale;
    final remaining = Duration(milliseconds: item.durationMs! - item.viewOffsetMs!);
    final ends = DateTime.now().add(remaining);
    final words = t.discover.resumeRemaining(
      duration: formatDurationTextual(remaining.inMilliseconds),
      time: formatClockTime(ends, is24Hour: MediaQuery.alwaysUse24HourFormatOf(context)),
    );
    final ink = tk?.ink(0.78) ?? Theme.of(context).colorScheme.onSurfaceVariant;

    return SizedBox(
      height: DetailResumeProgress.heightFor(scale),
      child: Align(
        alignment: widget.centered ? Alignment.center : AlignmentDirectional.centerStart,
        child: Padding(
          padding: EdgeInsetsDirectional.only(start: widget.centered ? 0 : widget.leadingInset),
          child: Text(
            words,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: widget.centered ? TextAlign.center : TextAlign.start,
            style: type.metadata.copyWith(color: ink, fontSize: DetailResumeProgress.fontSize * scale, height: 1.25),
          ),
        ),
      ),
    );
  }
}

/// The watched share of the play button, a lighter wash over its ground from
/// the leading edge (Plebz). Lies under the button's word and icon, clipped
/// to the button's [shape]; [color] is the word's colour, so a light accent
/// darkens where a dark one lightens.
class DetailResumeWash extends StatelessWidget {
  final double fraction;
  final ShapeBorder shape;
  final Color color;
  final bool focused;

  const DetailResumeWash({
    super.key,
    required this.fraction,
    required this.shape,
    required this.color,
    this.focused = false,
  });

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ClipPath(
        clipper: ShapeBorderClipper(shape: shape, textDirection: Directionality.of(context)),
        child: Align(
          alignment: AlignmentDirectional.centerStart,
          child: FractionallySizedBox(
            widthFactor: fraction,
            heightFactor: 1,
            child: ColoredBox(color: color.withValues(alpha: focused ? 0.30 : 0.22)),
          ),
        ),
      ),
    );
  }
}
