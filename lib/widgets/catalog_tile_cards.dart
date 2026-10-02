import 'package:flutter/material.dart';

import '../media/media_hub.dart';
import '../media/media_item.dart';
import '../theme/mono_tokens.dart';
import '../utils/media_image_helper.dart';
import 'optimized_media_image.dart';

/// The two shelves whose entries are destinations rather than titles.
///
/// Both layouts draw them — the television rail and the stacked sections on
/// everything else — so the shapes live here rather than in either. A poster's
/// geometry on a row of service logos is what this file exists to prevent.
bool isPlatformTileHub(MediaHub hub) => hub.type == 'platform';

bool isChipTileHub(MediaHub hub) => hub.type == 'chip';

/// A shelf of studios or networks: logos rather than titles.
///
/// Seerr's own way of offering the same thing Plex offers as a "platform"
/// shelf. Named here rather than in whichever layout happens to draw it,
/// because a shelf that one layout recognises and another does not is a row of
/// broken-image tiles — which is exactly what these were.
bool isBrandTileHub(MediaHub hub) => hub.type == 'studio' || hub.type == 'network';

/// A shelf of genres. Seerr's counterpart to Plex's chip shelf; it carries a
/// backdrop per entry, which the layouts are free to use or not.
bool isGenreTileHub(MediaHub hub) => hub.type == 'genre';

/// The type a chip is set in. Shared with [chipTileWidth], so a chip is
/// exactly as wide as the row reserved for it.
///
/// [size] is the height of the type in the frame the caller measures in. The
/// rail's own frame and the redesign's are not the same — the rail scales
/// between 0.85 and 1.35 of a 1080-tall screen, the redesign between 0.5 and 1
/// of a 1920-wide one — so one constant here would be two different physical
/// sizes on the same television. The caller says which frame it is in.
TextStyle chipTileTextStyle(double scale, {double size = 15}) =>
    TextStyle(fontSize: size * scale, fontWeight: FontWeight.w600, height: 1.2);

double chipTileHeight(double scale, {double size = 52}) => size * scale;

double _chipPadding(double scale, double size) => 20 * (size / 15) * scale;

/// A chip is as wide as its word, within reason: a row of pills all the width
/// of "Dokumentation" is a row of boxes, and one clipped to "Doku" is a
/// riddle.
double chipTileWidth(String label, double scale, {double size = 15}) {
  final painter = TextPainter(
    text: TextSpan(
      text: label,
      style: chipTileTextStyle(scale, size: size),
    ),
    textDirection: TextDirection.ltr,
    maxLines: 1,
  )..layout();
  // The air around the word, and the two guards, are proportions of the type
  // rather than fixed numbers: a chip set larger has to grow in every
  // direction at once, or the word ends up pressed against its own edges.
  final k = size / 15;
  return (painter.width + _chipPadding(scale, size) * 2).clamp(72.0 * k * scale, 340.0 * k * scale).toDouble();
}

/// How much of an ordinary card a service tile takes. A logo carries at a
/// glance what a poster needs its whole frame for.
const double catalogPlatformTileScale = 0.62;

/// A streaming service as its artwork and nothing else.
///
/// Plex's service images are square and painted on the brand's own colour, so
/// a card behind one would only be a border around a border — the web client
/// sets them side by side, and so does this.
class PlatformTileCard extends StatelessWidget {
  const PlatformTileCard({super.key, required this.item, required this.size, this.scale = 1});

  final MediaItem item;
  final double size;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // A tile whose logo will not load is a black square naming nothing. The
    // name steps in, and for the reader who cannot see the picture it is
    // there either way.
    Widget fallback() => ColoredBox(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Center(
        child: Padding(
          padding: EdgeInsets.all(8 * scale),
          child: Text(
            item.displayTitle,
            maxLines: 3,
            textAlign: .center,
            overflow: .ellipsis,
            style: theme.textTheme.labelMedium,
          ),
        ),
      ),
    );

    return Semantics(
      label: item.displayTitle,
      image: true,
      child: SizedBox(
        width: size,
        height: size,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(flatRadius(context, 8) * scale),
          child: item.artPath == null || item.artPath!.isEmpty
              ? fallback()
              : OptimizedMediaImage(
                  client: null,
                  imagePath: item.artPath,
                  width: size,
                  height: size,
                  fit: BoxFit.cover,
                  imageType: ImageType.thumb,
                  errorWidget: (context, _, _) => fallback(),
                ),
        ),
      ),
    );
  }
}

/// A studio or a network as its logo.
///
/// Wide, and the logo contained rather than covering: TMDB draws these as wide
/// transparent marks on nothing, so a square box cropped to fill would leave
/// "Warner Bros. Pictures" reading "ner Bro". A service tile can be square
/// because Plex paints its service art onto a square of the brand's colour;
/// these are not that.
class BrandTileCard extends StatelessWidget {
  const BrandTileCard({super.key, required this.item, required this.width, required this.height, this.scale = 1});

  final MediaItem item;
  final double width;
  final double height;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tk = tokens(context);

    // A mark that will not load is an empty box naming nothing. The name steps
    // in, and for a reader who cannot see the picture it is there either way.
    Widget fallback() => Center(
      child: Padding(
        padding: EdgeInsets.all(10 * scale),
        child: Text(
          item.displayTitle,
          maxLines: 2,
          textAlign: .center,
          overflow: .ellipsis,
          style: theme.textTheme.labelMedium,
        ),
      ),
    );

    return Semantics(
      label: item.displayTitle,
      image: true,
      child: SizedBox(
        width: width,
        height: height,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: tk.tileFill,
            borderRadius: BorderRadius.circular(flatRadius(context, 8) * scale),
          ),
          child: item.artPath == null || item.artPath!.isEmpty
              ? fallback()
              : Padding(
                  padding: EdgeInsets.symmetric(horizontal: 18 * scale, vertical: 14 * scale),
                  child: OptimizedMediaImage(
                    client: null,
                    imagePath: item.artPath,
                    width: width,
                    height: height,
                    fit: BoxFit.contain,
                    imageType: ImageType.thumb,
                    errorWidget: (context, _, _) => fallback(),
                  ),
                ),
        ),
      ),
    );
  }
}

/// A browse category as a pill with its name on it.
///
/// No artwork, though Plex sends some for genres: a genre is a word, and a row
/// of words is read at a glance where a row of pictures has to be looked at.
class ChipTileCard extends StatelessWidget {
  const ChipTileCard({
    super.key,
    required this.item,
    required this.width,
    required this.height,
    this.scale = 1,
    this.fontSize = 15,
  });

  final MediaItem item;
  final double width;
  final double height;
  final double scale;

  /// See [chipTileTextStyle]: the size in the caller's own frame.
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      label: item.displayTitle,
      button: true,
      child: SizedBox(
        width: width,
        height: height,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: tokens(context).tileFill,
            borderRadius: BorderRadius.circular(flatRadius(context, 8) * scale),
          ),
          child: Center(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 8 * scale),
              child: Text(
                item.displayTitle,
                maxLines: 1,
                overflow: .ellipsis,
                style: chipTileTextStyle(scale, size: fontSize).copyWith(color: theme.colorScheme.onSurface),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
