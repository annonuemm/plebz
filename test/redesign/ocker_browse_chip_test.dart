import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/widgets/catalog_tile_cards.dart';
import 'package:plezy/widgets/tv_browse_rail.dart';

/// A browse chip — a genre on Plex Erkunden, a decade, an award — is drawn by
/// one set of helpers that the rail and the phone's hub section share.
void main() {
  group('Browse chips', () {
    test('leave the shared surfaces exactly where they were', () {
      // The defaults are the numbers the rail and the phone have always drawn.
      // A change here is a change to Standard, which is why it has to
      // fail a test rather than pass unnoticed.
      expect(chipTileTextStyle(1).fontSize, 15);
      expect(chipTileHeight(1), 52);
      expect(TvBrowseRailLayout.chipTextStyle(1).fontSize, 15);
      expect(TvBrowseRailLayout.chipHeightFor(1), 52);
      expect(chipTileWidth('Krimi', 1), TvBrowseRailLayout.chipWidthFor('Krimi', 1));
    });
  });
}
