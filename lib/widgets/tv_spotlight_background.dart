import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../redesign/ocker_skin.dart';
import '../redesign/ocker_type.dart';
import '../theme/glass_backdrop.dart' show FlachGroundGlow, flachGroundGlows;
import '../theme/mono_tokens.dart';
import '../redesign/ultra_blur_backdrop.dart';
import '../media/ultra_blur_colors.dart';

import '../i18n/strings.g.dart';
import '../media/media_item.dart';
import '../media/media_item_types.dart';
import '../media/media_server_client.dart';
import '../services/device_performance.dart';
import '../utils/content_utils.dart';
import '../utils/formatters.dart';
import '../utils/layout_constants.dart';
import '../utils/media_image_helper.dart';
import '../services/settings_service.dart';
import '../services/tmdb/tmdb_fill_in_service.dart';
import '../utils/tone_mapped_logo_image.dart';
import 'corner_backdrop.dart';
import 'cycling_media_backdrop.dart';
import 'fitting_title_text.dart';
import 'fitted_metadata_line.dart';
import 'settings_builder.dart';
import 'media_rating_badge.dart';
import 'optimized_media_image.dart' show ClearLogoImage, blurArtwork;
import 'rasterized_gradient.dart';

class TvSpotlightBackground extends StatelessWidget {
  final MediaItem? item;
  final MediaServerClient? client;
  final bool hideSpoilers;
  final double contentBottom;
  final double? contentTop;
  final double? contentLeft;
  final bool compact;
  final bool showInfo;
  final String? Function(String? artworkPath)? localArtworkPathResolver;
  final bool allowNetwork;

  /// Drives the backdrop between full screen (0) and the corner box (1),
  /// overriding [SettingsService.tvCornerSpotlightBackdrop] while set.
  ///
  /// For a page whose title area owns the screen and then hands it back: the
  /// picture fills the screen while the title is up and withdraws into the
  /// corner when the rows come over it, which is where the home screen keeps
  /// it. Null leaves the setting in charge, as everywhere else.
  final double? cornerProgress;

  /// Optional caller-owned fact appended to the existing metadata line.
  final Widget? metadataTrailing;

  const TvSpotlightBackground({
    super.key,
    required this.item,
    required this.client,
    this.hideSpoilers = false,
    this.contentBottom = 360,
    this.contentTop,
    this.contentLeft,
    this.compact = false,
    this.showInfo = true,
    this.localArtworkPathResolver,
    this.allowNetwork = true,
    this.cornerProgress,
    this.metadataTrailing,
  });

  double _scale(BuildContext context) => TvLayoutConstants.scaleOf(context);

  @override
  Widget build(BuildContext context) {
    final media = item;
    final bgColor = Theme.of(context).scaffoldBackgroundColor;

    // The gradients never differ between spotlight items, so only the artwork
    // cross-fades by image paint alpha. Keeping the gradients outside the
    // rotating layer avoids full-screen saveLayers on low-end TVs.
    final size = MediaQuery.sizeOf(context);
    final containerAspect = size.width / size.height;
    final fallbackPaths = media == null
        ? const <String>[]
        : <String>[...media.heroArtCandidates(containerAspectRatio: containerAspect), ?media.thumbPath];
    return SettingValueBuilder<bool>(
      pref: SettingsService.tvCornerSpotlightBackdrop,
      builder: (context, cornerBackdrop, _) {
        final useCorner = cornerProgress == null ? cornerBackdrop : cornerProgress! > 0;
        final backdropSize = useCorner ? cornerBackdropSize(size) : size;
        final backdrop = CyclingMediaBackdrop(
          mediaKey: media?.globalKey,
          imagePaths: media?.heroRotationPaths(containerAspectRatio: containerAspect) ?? const [],
          fallbackImagePaths: fallbackPaths,
          client: client,
          localArtworkPathResolver: localArtworkPathResolver == null ? null : (path) => localArtworkPathResolver!(path),
          allowNetwork: allowNetwork,
          // Always request at full-screen size: the corner box only crops the
          // layout. A mode-dependent size would change the transcode URL and
          // cold-start every cached backdrop when the setting is toggled.
          width: size.width,
          height: size.height,
          fallbackColor: media == null ? bgColor : Theme.of(context).colorScheme.surfaceContainerHighest,
        );
        final artwork = backdrop;
        return Stack(
          fit: StackFit.expand,
          children: [
            RepaintBoundary(
              child: cornerProgress != null
                  ? _buildMovingBackdrop(size, cornerProgress!, artwork)
                  : (useCorner ? _buildCornerBackdrop(backdropSize, artwork) : blurArtwork(artwork)),
            ),
            _buildScrims(context, bgColor, useCorner: useCorner),
            if (media != null && showInfo)
              Positioned(
                left: contentLeft ?? TvLayoutConstants.horizontalInset,
                right: MediaQuery.sizeOf(context).width * 0.43,
                top: contentTop,
                bottom: contentBottom,
                // The info block still cross-fades via AnimatedSwitcher, but its
                // saveLayers are bounded to the text region, not the screen.
                child: AnimatedSwitcher(
                  duration: DevicePerformance.reducedDuration(const Duration(milliseconds: 280)),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeOutCubic,
                  // Expand instead of the default loose centered Stack so the
                  // info keeps filling the region and bottom-left aligning.
                  layoutBuilder: (currentChild, previousChildren) =>
                      Stack(fit: StackFit.expand, children: [...previousChildren, ?currentChild]),
                  child: KeyedSubtree(
                    key: ValueKey(media.globalKey),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        if (!constraints.hasBoundedHeight || constraints.maxHeight <= 0 || constraints.maxWidth <= 0) {
                          return Align(alignment: .bottomLeft, child: _buildInfo(context, media, constraints.maxWidth));
                        }

                        return Align(
                          alignment: .bottomLeft,
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: .bottomLeft,
                            child: SizedBox(
                              width: constraints.maxWidth,
                              child: _buildInfo(context, media, constraints.maxWidth),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  /// The backdrop on its way between full screen and the corner box.
  ///
  /// One box that shrinks, rather than two that cross-fade: a dissolve reads
  /// as the picture being swapped, and it is the same picture the whole way.
  Widget _buildMovingBackdrop(Size screen, double target, Widget backdrop) {
    final corner = cornerBackdropSize(screen);
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: target.clamp(0.0, 1.0)),
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      builder: (context, t, child) => Align(
        alignment: Alignment.topRight,
        child: CornerBackdrop(
          width: lerpDouble(screen.width, corner.width, t)!,
          height: lerpDouble(screen.height, corner.height, t)!,
          feather: t,
          child: child!,
        ),
      ),
      child: backdrop,
    );
  }

  /// Corner spotlight: artwork pinned to the top-right corner so the info
  /// block sits on a calm surface instead of on the image. Shared with the
  /// catalog detail page — see [CornerBackdrop].
  Widget _buildCornerBackdrop(Size backdropSize, Widget backdrop) {
    return Align(
      alignment: Alignment.topRight,
      child: CornerBackdrop(width: backdropSize.width, height: backdropSize.height, child: backdrop),
    );
  }

  /// The two scrims — or, while the ground takes the focused title's colours
  /// ([UltraBlurAmbient]), lighter ones in black: scrims in the ground's own
  /// flat colour, nearly opaque at the left and the foot, covered exactly the
  /// part of the screen the colours were to show on. The picture then fades
  /// into the colours, as on Plex.
  Widget _buildScrims(BuildContext context, Color bgColor, {required bool useCorner}) {
    if (ockerFlat(context)) return _buildFlatScrims(context, bgColor);
    final ambient = UltraBlurScope.of(context);
    Widget standard() => Stack(
      fit: StackFit.expand,
      children: [
        _buildHorizontalScrim(context, bgColor),
        RasterizedGradient(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.black.withValues(alpha: 0.45), Colors.transparent, bgColor.withValues(alpha: 0.96)],
            stops: const [0.0, 0.38, 1.0],
          ),
        ),
      ],
    );
    if (ambient == null) return standard();
    return ValueListenableBuilder<UltraBlurColors?>(
      valueListenable: ambient,
      builder: (context, colors, _) {
        if (colors == null) return standard();
        // Over the full-screen picture the text still needs its shade; beside
        // the corner box it stands on the colours themselves.
        final side = useCorner ? 0.3 : 0.7;
        final foot = useCorner ? 0.25 : 0.6;
        return Stack(
          fit: StackFit.expand,
          children: [
            RasterizedGradient(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  Colors.black.withValues(alpha: side),
                  Colors.black.withValues(alpha: side * 0.35),
                  Colors.transparent,
                ],
                stops: const [0.0, 0.56, 1.0],
              ),
            ),
            RasterizedGradient(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.3),
                  Colors.transparent,
                  Colors.black.withValues(alpha: foot),
                ],
                stops: const [0.0, 0.38, 1.0],
              ),
            ),
          ],
        );
      },
    );
  }

  /// "Redesign – Flach" (Plebz): scrims in several steps with no seam, so the
  /// picture runs softly into the ground, with the ground's faint lights of
  /// the accent over them ([flachGroundGlows]).
  ///
  /// Solid ground under the words and the rows, the picture only where
  /// nothing is written on it. The detail page ([showInfo] off — it draws its
  /// own header) gives the picture a little more of the width.
  ///
  /// While the ground takes the focused title's colours ([UltraBlurAmbient])
  /// the same two fades are laid over again in those colours, so the picture
  /// runs into them rather than into the plain ground. Here, not under the
  /// shell: the picture fills the screen, and the solid parts of these
  /// scrims are all of the ground there is to see.
  Widget _buildFlatScrims(BuildContext context, Color bgColor) {
    final detail = !showInfo;
    final ambient = UltraBlurScope.of(context);
    LinearGradient side(Color Function(double alpha) paint) => LinearGradient(
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
      colors: [paint(1), paint(1), paint(0.86), paint(detail ? 0.5 : 0.55), paint(detail ? 0.12 : 0.18), paint(0)],
      stops: detail ? const [0, 0.26, 0.38, 0.52, 0.70, 0.86] : const [0, 0.34, 0.44, 0.56, 0.72, 0.88],
    );
    LinearGradient foot(Color Function(double alpha) paint) => LinearGradient(
      begin: Alignment.bottomCenter,
      end: Alignment.topCenter,
      colors: [paint(1), paint(1), paint(detail ? 0.8 : 0.82), paint(detail ? 0.3 : 0.35), paint(0)],
      stops: detail ? const [0, 0.24, 0.36, 0.52, 0.68] : const [0, 0.30, 0.42, 0.56, 0.70],
    );
    Color ground(double alpha) => bgColor.withValues(alpha: alpha);
    Color mask(double alpha) => Colors.white.withValues(alpha: alpha);
    return Stack(
      fit: StackFit.expand,
      children: [
        RasterizedGradient(gradient: side(ground)),
        RasterizedGradient(gradient: foot(ground)),
        // One copy per fade, each masked by it: the two cover what the two
        // scrims cover together, where one copy under both masks would only
        // cover where they overlap.
        if (ambient != null)
          RepaintBoundary(
            child: Stack(
              fit: StackFit.expand,
              children: [
                for (final fade in [side(mask), foot(mask)])
                  ShaderMask(
                    blendMode: BlendMode.dstIn,
                    shaderCallback: fade.createShader,
                    child: UltraBlurLayer(colors: ambient, dim: flatUltraBlurDim),
                  ),
              ],
            ),
          ),
        // The ground's own two lights of the accent, which these scrims of
        // solid ground would otherwise cover — gone while the colours show,
        // which are the ground then.
        if (ambient == null)
          FlachGroundGlow(glows: flachGroundGlows(tokens(context)))
        else
          ValueListenableBuilder<UltraBlurColors?>(
            valueListenable: ambient,
            builder: (context, colors, glow) =>
                AnimatedOpacity(opacity: colors == null ? 1 : 0, duration: UltraBlurLayer.crossfade, child: glow),
            child: FlachGroundGlow(glows: flachGroundGlows(tokens(context))),
          ),
      ],
    );
  }

  /// How dark the colours are under "Flach". The words and the rows stand on
  /// them directly, with no scrim of black between, so they are taken further
  /// towards black than the shell's ground: about where Glas's corner
  /// spotlight ends up with its own scrim over the colours.
  static const double flatUltraBlurDim = 0.5;

  /// The scrim, at one strength for every variant.
  ///
  /// "Ocker" had a heavier, wider one for a while. It was written for the
  /// catalog's hero on the app's own layout — a screen that no longer exists
  /// in that variant, since the rows now describe the focused title
  /// themselves. What was left of it landed on the one surface still built
  /// from this widget, the detail page, where it was never the intent.
  Widget _buildHorizontalScrim(BuildContext context, Color bgColor) {
    return RasterizedGradient(
      gradient: LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [bgColor.withValues(alpha: 0.86), bgColor.withValues(alpha: 0.32), Colors.transparent],
        stops: const [0.0, 0.56, 1.0],
      ),
    );
  }

  Widget _buildInfo(BuildContext context, MediaItem media, double width) {
    if (ockerFlat(context)) return _buildFlatInfo(context, media, width);
    final scale = _scale(context);
    final colorScheme = Theme.of(context).colorScheme;
    final shouldHideSpoiler = hideSpoilers && media.shouldHideSpoiler;
    final summary = shouldHideSpoiler ? null : media.summary;
    final title = media.grandparentTitle ?? media.displayTitle;

    return Column(
      crossAxisAlignment: .start,
      mainAxisSize: .min,
      children: [
        _buildLogoOrTitle(context, media, title, width),
        SizedBox(height: _titleGap(context, scale)),
        _buildMetadataLine(context, media),
        if (shouldHideSpoiler && media.isEpisode) ...[
          SizedBox(height: _summaryGap(context, scale)),
          Text(
            media.title ?? '',
            maxLines: 2,
            overflow: .ellipsis,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: colorScheme.onSurface.withValues(alpha: 0.72),
              fontSize: _summaryFontSize(scale),
              height: compact ? 1.34 : 1.45,
            ),
          ),
        ] else
          SpotlightSummary(
            item: media,
            client: client,
            summary: summary,
            allowFillIn: !shouldHideSpoiler,
            gap: _summaryGap(context, scale),
            maxLines: compact ? 3 : 4,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: colorScheme.onSurface.withValues(alpha: 0.78),
              fontSize: _summaryFontSize(scale),
              height: compact ? 1.34 : 1.45,
            ),
          ),
      ],
    );
  }

  /// The block under "Flach" (Plebz): the title, a line of plain facts, and
  /// three lines of description at most — on the design's own steps of 20 and
  /// 22 between them, the prose a little wider for its larger type.
  Widget _buildFlatInfo(BuildContext context, MediaItem media, double width) {
    final tk = tokens(context);
    final type = OckerType.of(context);
    final scale = ockerScale(context);
    final shouldHideSpoiler = hideSpoilers && media.shouldHideSpoiler;
    final summary = shouldHideSpoiler ? null : media.summary;
    final title = media.grandparentTitle ?? media.displayTitle;
    final prose = type.synopsis.copyWith(color: tk.ink(0.78));

    return Column(
      crossAxisAlignment: .start,
      mainAxisSize: .min,
      children: [
        _buildLogoOrTitle(context, media, title, width),
        // Closer than the summary below: the facts belong to the title. At
        // the design's 20 against 22 the line floated between the two.
        SizedBox(height: 10 * scale),
        _buildMetadataLine(context, media),
        ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 840 * scale),
          child: shouldHideSpoiler && media.isEpisode
              ? Padding(
                  padding: EdgeInsets.only(top: 22 * scale),
                  child: Text(media.title ?? '', maxLines: 2, overflow: .ellipsis, style: prose),
                )
              : SpotlightSummary(
                  item: media,
                  client: client,
                  summary: summary,
                  allowFillIn: !shouldHideSpoiler,
                  gap: 22 * scale,
                  maxLines: 3,
                  style: prose,
                ),
        ),
      ],
    );
  }

  /// The logo is contained within its slot; the title fallback gets
  /// [ClearLogoImage.fallbackWidthFor] of the info block's [availableWidth]
  /// at the slot's height (#1796).
  /// The logo, or the title set as type where the viewer switched logos off
  /// here ([SettingsService.showHomeTitleLogos]).
  Widget _buildLogoOrTitle(BuildContext context, MediaItem media, String title, double availableWidth) {
    return SettingValueBuilder<bool>(
      pref: SettingsService.showHomeTitleLogos,
      builder: (context, logos, _) => _buildLogoOrTitleWith(context, media, title, availableWidth, logos: logos),
    );
  }

  Widget _buildLogoOrTitleWith(
    BuildContext context,
    MediaItem media,
    String title,
    double availableWidth, {
    required bool logos,
  }) {
    // The title the design sets is the fallback, not the first choice: a film's
    // own logo is how it is recognised across a room, and ClearLogoImage draws
    // the set title itself where a server has no logo to give. (This design
    // did once set every title in the serif instead, on the grounds that a
    // logo arrives with its own weight and letterspacing and often a tagline.
    // Seen on a television, the plain line read as a placeholder.)

    final theme = Theme.of(context);
    // The spotlight scrim washes artwork toward the scaffold background, so
    // light themes recolor light-toned logos to stay visible.
    final logoToneTarget = logoToneTargetFor(
      surface: theme.scaffoldBackgroundColor,
      foreground: theme.colorScheme.onSurface,
    );
    final scale = _scale(context);
    // Off, no logo is shown or looked for: the same box, with the title in it.
    final logoPath = logos ? media.clearLogoPath : null;
    final logoWidth = math.min(_logoWidth(context, scale), availableWidth);
    final logoHeight = _logoHeight(context, scale);
    // The title slot, wider than the mark's: a title confined to a box cut for
    // a wordmark ellipsizes long before the column runs out (#1796).
    final width = ClearLogoImage.fallbackWidthFor(logoWidth: logoWidth, available: availableWidth);
    // No early return for a missing logo: ClearLogoImage draws the title
    // itself when there is nothing to show, and it is also what asks
    // ClearLogoService for a logo the server does not have. Returning here
    // would skip that lookup on the one surface that needs it most.
    // Stand the logo on the floor of its box rather than centring it in it.
    //
    // The box reserves room for the tallest wordmark there could be, and
    // BoxFit.contain then decides which edge binds. A squarish logo is bound
    // by the height, fills the box top to bottom, and centring it is invisible.
    // A long one — a wordmark set on a single line — is bound by the width and
    // comes out a fraction of the box's height, so centring leaves it floating
    // with a gap beneath that the facts row then has to start below. Bottom
    // alignment puts every logo the same distance above that line, whatever
    // shape it arrived in.
    // In every theme since the original look took it over from the redesign.
    const logoAlignment = Alignment.bottomLeft;
    final pixelRatio = MediaImageHelper.artworkPixelRatio(context, imageType: ImageType.heroLogo);
    final (logoMemWidth, logoMemHeight) = MediaImageHelper.getMemCacheDimensions(
      displayWidth: (logoWidth * pixelRatio).round(),
      displayHeight: (logoHeight * pixelRatio).round(),
      imageType: ImageType.heroLogo,
    );

    final localLogoPath = logoPath == null || logoPath.isEmpty ? null : localArtworkPathResolver?.call(logoPath);
    if (localLogoPath != null && File(localLogoPath).existsSync()) {
      final bounded = MediaImageHelper.boundedDecode(
        FileImage(File(localLogoPath)),
        memWidth: logoMemWidth,
        memHeight: logoMemHeight,
      );
      return SizedBox(
        width: width,
        height: logoHeight,
        child: Align(
          alignment: logoAlignment,
          child: blurArtwork(
            Image(
              image: logoToneTarget == null
                  ? bounded
                  : ToneMappedLogoImage(bounded, target: logoToneTarget, remapMixed: false),
              width: logoWidth,
              height: logoHeight,
              fit: BoxFit.contain,
              filterQuality: MediaImageHelper.artworkFilterQuality(context, ImageType.heroLogo),
              alignment: logoAlignment,
              // Replaces the image under Align's loose constraints, so it
              // takes the whole title slot rather than the logo's.
              errorBuilder: (context, error, stackTrace) => SizedBox.expand(child: _buildTitle(context, title)),
            ),
            sigma: 10,
            clip: false,
          ),
        ),
      );
    }

    return ClearLogoImage(
      client: client,
      logoPath: logoPath,
      item: logos ? media : null,
      width: logoWidth,
      height: logoHeight,
      // Under "Ocker" the box is cut to half the width, which a title set as
      // type does not fit into: it breaks over two lines and ends in an
      // ellipsis while the synopsis three lines below runs the full column.
      // Infinity here is the column's own width, because the box is bounded by
      // it, so the fallback gets exactly the room the prose under it has.
      // Elsewhere it is upstream's title slot — twice the mark, capped to the
      // column (#1796).
      fallbackWidth: isOcker(context) ? double.infinity : width,
      alignment: logoAlignment,
      fadeInDuration: DevicePerformance.reducedDuration(const Duration(milliseconds: 200)),
      logoToneTarget: logoToneTarget,
      fallbackBuilder: (context) => _buildTitle(context, title),
    );
  }

  Widget _buildTitle(BuildContext context, String title) {
    final scale = _scale(context);
    final colorScheme = Theme.of(context).colorScheme;
    if (ockerFlat(context)) {
      return FittingTitleText(
        title,
        alignment: Alignment.bottomLeft,
        style: OckerType.of(context).spotlightTitle().copyWith(color: tokens(context).ink(1)),
      );
    }
    return FittingTitleText(
      title,
      // Stands on the floor of the slot, like the logo it appears instead of,
      // so the distance down to the facts row is the same either way. A title
      // that needs two lines grows upward from that floor rather than pushing
      // the row down, and FittingTitleText shrinks the type until both lines
      // fit the slot's height, so it cannot climb into the band above.
      alignment: Alignment.bottomLeft,
      style: Theme.of(context).textTheme.displaySmall?.copyWith(
        color: colorScheme.onSurface,
        fontSize: _titleFontSize(scale),
        // Instrument Serif ships one weight. Asking for a heavier one makes
        // the renderer smear the glyphs sideways to fake it, which on a serif
        // at title size is unmistakable — so under "Ocker" it is not asked for.
        fontWeight: isOcker(context) ? null : FontWeight.w800,
        shadows: [Shadow(color: colorScheme.surface.withValues(alpha: 0.8), blurRadius: 12)],
      ),
    );
  }

  Widget _buildMetadataLine(BuildContext context, MediaItem media) {
    final scale = _scale(context);
    final colorScheme = Theme.of(context).colorScheme;
    final episodeLabel = formatSeasonEpisodeLabel(media.parentIndex, media.index);
    // Tracked out under "Ocker", the way the section headings above the rows
    // are: a mono line with air between its letters reads as a label, and a
    // label is not the first line of the paragraph under it. 0.1 is what the
    // standard theme sets, which is close enough to nothing that the line
    // reads as a sentence of facts — right for a proportional face, wrong for
    // this one.
    final metadataSize = _metadataFontSize(scale);
    final flat = ockerFlat(context);
    final textStyle = flat
        ? OckerType.of(context).spotlightFacts.copyWith(color: tokens(context).ink(0.66))
        : TextStyle(
            color: colorScheme.onSurface,
            fontSize: metadataSize,
            fontWeight: .w700,
            letterSpacing: isOcker(context) ? metadataSize * 0.07 : 0.1,
          );

    // The detail page's order, so a title is described the same way wherever
    // it is shown: which episode, when, what kind, for whom, how long, which
    // cut, how it scored.
    final parts = <MetadataLinePart>[];
    if (media.isEpisode && episodeLabel != null) parts.add(MetadataLineText(episodeLabel, dropPriority: 0));
    if (media.isEpisode && media.originallyAvailableAt != null) {
      parts.add(MetadataLineText(formatFullDate(media.originallyAvailableAt!), dropPriority: 0));
    } else if (media.year != null) {
      parts.add(MetadataLineText(media.year.toString(), dropPriority: 0));
    }
    if (media.isMovie) {
      parts.add(MetadataLineText(t.discover.movie, dropPriority: 3));
    } else if (media.isShow) {
      parts.add(MetadataLineText(t.discover.tvShow, dropPriority: 3));
    }
    if (media.contentRating != null) {
      parts.add(MetadataLineText(formatContentRating(media.contentRating!), dropPriority: 2, badge: true));
    }
    if (media.hasRuntime) {
      parts.add(MetadataLineText(formatDurationTextual(media.durationMs!), dropPriority: 1));
    }
    if (media.editionTitle case final edition? when edition.trim().isNotEmpty) {
      parts.add(MetadataLineText(edition.trim(), dropPriority: 3));
    }
    // Hub listings carry the scalar rating pair, so the dashboard spotlight
    // shows every score the shelf request already returned — no per-item
    // hydration to lengthen it.
    final ratings = mediaRatingsFor(media);
    if (ratings.isNotEmpty) parts.add(MetadataLineRatings(ratings, dropPriority: 4));

    final line = parts.isEmpty
        ? null
        : FittedMetadataLine(
            textStyle: flat ? textStyle : monoFacts(context, textStyle),
            parts: parts,
            // Same boxes as the detail page: this line is read across a room,
            // and a box tells two facts apart where a bullet between words of
            // equal weight does not. Under "Glas" each is a capsule of glass,
            // as on the detail page.
            chipped: true,
            chipSpacing: 8 * scale,
            ratingIconSize: textStyle.fontSize,
            ratingSpacing: 4 * scale,
            ratingEntrySpacing: 12 * scale,
          );
    final trailing = metadataTrailing;
    if (trailing == null) return line ?? const SizedBox.shrink();
    if (line == null) return trailing;
    // The trailing fact is caller-owned and always shown; the line fits
    // itself into whatever width the trailing widget leaves over.
    return Row(
      mainAxisSize: .min,
      children: [
        Flexible(child: line),
        // A gap, not a bullet: the boxes already do the separating. Under
        // "Flach" the same air as between two facts; the trailing fact brings
        // its own mark.
        SizedBox(width: flat ? 16 * ockerScale(context) : 8 * scale),
        trailing,
      ],
    );
  }

  double _sectionGap(double scale) => (compact ? 10 : 16) * scale;

  /// The gap under the title, which is not the same gap as the one under the
  /// facts line.
  ///
  /// One number for every join is what makes a stack read as "assembled"
  /// rather than "composed": the eye expects the distance to grow as the type
  /// gets quieter. A title is the loudest thing here and wants room; the line
  /// of facts under it is a label and belongs close to what it describes.
  /// Above the facts line, and below it.
  ///
  /// The two belong together and are the same decision read twice: the facts
  /// are part of the title block, not the first sentence of the prose, and the
  /// eye groups by distance before it reads a typeface. The synopsis sets its
  /// own lines about 29 apart (20 at a height of 1.45), so anything under that
  /// below the facts says "same block" however differently the line is set —
  /// which is what the first arrangement did, at 22 above and 18 below. It
  /// sits by the title now and has clear air under it, which is also how every
  /// television streaming app arranges the same three things.
  // Under "Glas" the facts sit closer to the title and to the synopsis: on
  // capsules they stand apart by their shape, and the air that separated a
  // bare line of facts only pulled the block apart.
  double _titleGap(BuildContext context, double scale) => ockerGlass(context)
      ? (compact ? 6 : 8) * scale
      : isOcker(context)
      ? (compact ? 9 : 13) * scale
      : _sectionGap(scale);

  double _summaryGap(BuildContext context, double scale) => ockerGlass(context)
      ? (compact ? 12 : 16) * scale
      : isOcker(context)
      ? (compact ? 22 : 32) * scale
      : _sectionGap(scale);

  /// Half the width and four fifths the height under "Ocker".
  ///
  /// The box is what shrinks, not the picture: BoxFit.contain keeps the logo's
  /// own proportions inside it, so halving the width halves a wide wordmark
  /// while the shorter height only binds the tall ones. The design carries its
  /// titles at a size the type scale sets, and a logo drawn to the standard
  /// theme's box arrives at twice that.
  double _logoWidth(BuildContext context, double scale) {
    final width = (compact ? TvLayoutConstants.compactHeroLogoWidth : TvLayoutConstants.heroLogoWidth) * scale;
    return isOcker(context) ? width * 0.5 : width;
  }

  double _logoHeight(BuildContext context, double scale) {
    final height = (compact ? TvLayoutConstants.compactHeroLogoHeight : TvLayoutConstants.heroLogoHeight) * scale;
    return isOcker(context) ? height * 0.8 : height;
  }

  double _titleFontSize(double scale) => (compact ? 44 : 54) * scale;

  double _metadataFontSize(double scale) => (compact ? 16 : 18) * scale;

  double _summaryFontSize(double scale) => (compact ? 18 : 20) * scale;
}

/// The description under the title, with the gap above it, or nothing at all.
///
/// Catalog rows (Explore) never carry an overview — providers only return one
/// with their detail payload — so this asks [TmdbFillInService] for it, the
/// same lookup that already fetches the logo and from the same cached answer.
///
/// Only movies and shows are filled in. An episode's lookup resolves under its
/// *series* id, which is right for a logo and wrong for a description: it
/// would caption one episode with the plot of the whole series.
/// The description under a title, with the gap above it — asking the fill-in
/// services for one when the row did not carry it.
///
/// Public because the "Ocker" detail panel needs exactly this and nothing
/// else: catalog rows almost never carry an overview, so a panel that only
/// printed `item.summary` would be blank on most of what it describes.
class SpotlightSummary extends StatefulWidget {
  const SpotlightSummary({
    super.key,
    required this.item,
    required this.client,
    required this.summary,
    required this.allowFillIn,
    required this.gap,
    required this.maxLines,
    required this.style,
  });

  final MediaItem item;
  final MediaServerClient? client;

  /// What the server or catalog row supplied, if anything.
  final String? summary;

  /// False while spoilers are hidden — fetching the plot would defeat that.
  final bool allowFillIn;
  final double gap;
  final int maxLines;
  final TextStyle? style;

  @override
  State<SpotlightSummary> createState() => SpotlightSummaryState();
}

class SpotlightSummaryState extends State<SpotlightSummary> {
  String? _filledIn;
  ValueListenable<bool>? _enabledListenable;

  @override
  void initState() {
    super.initState();
    _enabledListenable = SettingsService.instanceOrNull?.listenable(SettingsService.tmdbLogosEnabled);
    _enabledListenable?.addListener(_onEnabledChanged);
    _resolveIfNeeded();
  }

  @override
  void dispose() {
    _enabledListenable?.removeListener(_onEnabledChanged);
    super.dispose();
  }

  void _onEnabledChanged() {
    if (!mounted) return;
    setState(_resolveIfNeeded);
  }

  @override
  void didUpdateWidget(covariant SpotlightSummary oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.item.globalKey != oldWidget.item.globalKey || widget.summary != oldWidget.summary) {
      _filledIn = null;
      _resolveIfNeeded();
    }
  }

  /// Mutates state directly; callers either run before the first build or wrap
  /// this in setState themselves.
  void _resolveIfNeeded() {
    final own = widget.summary;
    if (own != null && own.isNotEmpty) return;
    if (!widget.allowFillIn || !(widget.item.isMovie || widget.item.isShow)) return;

    final service = TmdbFillInService.instanceOrNull;
    if (service == null || !service.isEnabled) return;

    // A known answer is applied before the first paint, so the description
    // does not pop in a moment after the rest of the block has settled.
    final known = service.known(widget.item);
    if (known != null) {
      _filledIn = known.summary;
      return;
    }

    final requestedKey = widget.item.globalKey;
    unawaited(
      service.resolve(widget.item, client: widget.client).then((found) {
        if (!mounted || found.summary == null || widget.item.globalKey != requestedKey) return;
        setState(() => _filledIn = found.summary);
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final own = widget.summary;
    final text = own == null || own.isEmpty ? _filledIn : own;
    if (text == null || text.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: EdgeInsets.only(top: widget.gap),
      child: Text(text, maxLines: widget.maxLines, overflow: TextOverflow.ellipsis, style: widget.style),
    );
  }
}
