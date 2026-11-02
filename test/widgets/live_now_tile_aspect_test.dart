import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/focus/focus_theme.dart';
import 'package:plezy/media/media_hub.dart';
import 'package:plezy/screens/live_now/live_now_tile.dart';
import 'package:plezy/services/settings_service.dart';
import 'package:plezy/widgets/tv_browse_rail.dart';

void main() {
  TvBrowseRailLayoutMetrics metrics({required String type, required bool v2}) => TvBrowseRailLayout.metricsForHub(
    hub: MediaHub(id: 'row', title: 'Row', type: type, items: const [], size: 0),
    availableWidth: 1800,
    density: LibraryDensity.min,
    episodePosterMode: EpisodePosterMode.seriesPoster,
    scale: 1,
    fullCardLayout: true,
    v2: v2,
  );

  test('Glas – v2 flattens the live row, keeping the width', () {
    final flat = metrics(type: liveNowHubType, v2: true);
    final plain = metrics(type: liveNowHubType, v2: false);

    expect(flat.cardWidth, plain.cardWidth);
    expect(flat.posterHeight, closeTo(flat.cardWidth / liveNowV2TileAspect, 0.01));
    expect(plain.posterHeight, closeTo(plain.cardWidth * 9 / 16, 0.01));
    expect(flat.height, lessThan(plain.height), reason: 'the row hands the height back');
  });

  test('no other row changes shape with it', () {
    final studio = metrics(type: 'genre', v2: true);
    expect(studio.posterHeight, metrics(type: 'genre', v2: false).posterHeight);
  });

  test("a Glas – v2 poster row keeps room for the grids' zoom and its ring", () {
    final row = metrics(type: 'movie', v2: true);
    final reach =
        row.posterHeight * (FocusTheme.flatPosterFocusScale - 1) / 2 +
        FocusTheme.flatRingGap +
        FocusTheme.flatRingWidth;

    final above = row.cardTop + TvBrowseRailLayout.hubStripHeightForScale(1) / 2;
    final below = row.height - row.cardTop - row.containerHeight;

    expect(reach, lessThan(above), reason: 'the ring stays clear of the heading');
    expect(reach, lessThan(below), reason: 'the ring stays inside the section');
  });
}
