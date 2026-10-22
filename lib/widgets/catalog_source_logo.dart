import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../models/catalog/catalog_item.dart';
import '../redesign/ocker_skin.dart' show OckerFlatFocusInk, OckerKeepColours;

/// The brand mark asset of a service: the single table of brand asset paths.
/// Every surface that shows a service logo goes through here, including
/// services that do not participate in the Explore catalog and the trackers'
/// scores on the ratings rows. The marks draw in `currentColor`.
String catalogSourceLogoAsset(CatalogSourceId id) => switch (id) {
  CatalogSourceId.plex => 'assets/plex_chevron.svg',
  CatalogSourceId.trakt => 'assets/trakt_circlemark.svg',
  CatalogSourceId.mal => 'assets/mal_mark.svg',
  CatalogSourceId.anilist => 'assets/anilist_mark.svg',
  CatalogSourceId.simkl => 'assets/simkl_mark.svg',
  CatalogSourceId.seerr => 'assets/seerr_mark.svg',
  CatalogSourceId.mdblist => 'assets/mdblist_mark.svg',
};

/// Brand mark of a service, tinted with the ambient icon color. Uses
/// [SvgTheme.currentColor] so SVGs with multiple explicit fills (AniList keeps
/// its brand-blue L while the A follows the theme) render correctly alongside
/// single-color wordmarks.
class CatalogSourceLogo extends StatelessWidget {
  final CatalogSourceId id;
  final double size;

  const CatalogSourceLogo(this.id, {super.key, this.size = 20});

  @override
  Widget build(BuildContext context) {
    final color = IconTheme.of(context).color ?? Theme.of(context).colorScheme.onSurface;
    // Under "Flach"'s inverted focus (Plebz) the brand colours stay as they
    // are; only the part that follows the ink turns with it.
    if (OckerFlatFocusInk.invertingAt(context)) {
      return OckerKeepColours(
        child: SvgPicture.asset(
          catalogSourceLogoAsset(id),
          width: size,
          height: size,
          theme: SvgTheme(
            currentColor: Color.from(alpha: color.a, red: 1 - color.r, green: 1 - color.g, blue: 1 - color.b),
          ),
        ),
      );
    }
    return SvgPicture.asset(
      catalogSourceLogoAsset(id),
      width: size,
      height: size,
      theme: SvgTheme(currentColor: color),
    );
  }
}
