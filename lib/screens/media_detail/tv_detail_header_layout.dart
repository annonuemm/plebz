/// How the TV detail page divides the height above the rails.
///
/// The header is a fixed box: logo or title, facts line, genres, summary and
/// the action row have to share whatever the rails leave. This file owns the
/// rule for that division, away from the widget that draws it, because the
/// rule is what goes wrong — a section loading late shrinks the box, and the
/// summary silently loses lines.
library;

/// What stands where the title goes.
enum TvDetailTitleMode {
  /// The clear logo, in a box tall enough to be worth showing.
  logo,

  /// The title set as text.
  ///
  /// A last resort, not a trade: the logo is shown whenever there is any
  /// height for it. Type takes over only where a logo would be too small to
  /// read, so that the page still names itself.
  text,
}

/// The height budget, resolved.
class TvDetailHeaderLayout {
  /// Lines the summary may use, 0 to 3.
  final int summaryLines;

  /// Height of the title box — the logo's or the text's.
  final double titleHeight;

  final TvDetailTitleMode titleMode;

  /// Font size for [TvDetailTitleMode.text], derived from [titleHeight] so a
  /// small box gets small type rather than clipped type.
  final double titleFontSize;

  const TvDetailHeaderLayout({
    required this.summaryLines,
    required this.titleHeight,
    required this.titleMode,
    required this.titleFontSize,
  });

  bool get showsTitle => titleHeight > 0;
}

/// Type and spacing of the header, all derived from [scale] and the height the
/// header actually got.
class TvDetailHeaderMetrics {
  final double availableHeight;
  final double scale;
  final bool hasDescription;
  final bool hasGenres;

  /// Whether a focused episode's own title needs a line of its own.
  ///
  /// The title slot above carries the *show's* name, so without this the
  /// episode's name exists only on its rail card, where it is usually cut off.
  final bool hasEpisodeTitle;

  /// Whether the title area has the screen to itself. It then has room the
  /// fixed layout never has, and spends it on the summary.
  final bool heroLayout;

  /// Lines this particular summary actually fills, measured against the width
  /// it will be laid out in. Null before it has been measured.
  ///
  /// Without it the layout reserves the ceiling for every title, and a
  /// three-line synopsis pays for six — height the logo could have had.
  final int? descriptionLines;

  /// Whether the facts take a second row: under "Glas" the picture and sound
  /// go on a line of their own below year, age and length.
  final bool hasQualityLine;

  const TvDetailHeaderMetrics({
    required this.availableHeight,
    required this.scale,
    required this.hasDescription,
    required this.hasGenres,
    this.hasEpisodeTitle = false,
    this.heroLayout = false,
    this.descriptionLines,
    this.hasQualityLine = false,
  });

  /// Lines the summary may grow to.
  ///
  /// Three where the rails share the screen — more would only be given back a
  /// moment later. Six where the title area owns it: at that width six lines
  /// is roughly a full synopsis, and beyond it the block starts competing with
  /// the artwork it sits on.
  int get summaryLineCeiling => heroLayout ? 6 : 3;

  /// What the summary may take here: the ceiling, or the lines this text needs
  /// if that is fewer.
  int get maxSummaryLines {
    final measured = descriptionLines;
    if (measured == null) return summaryLineCeiling;
    return measured < summaryLineCeiling ? measured : summaryLineCeiling;
  }

  /// How tall a logo wants to be. Thirty per cent under what the page used to
  /// give it: at this distance a title mark carries at a fraction of the size,
  /// and the height it gives up goes to the text.
  double get desiredLogoHeight => 154 * scale;

  /// What the logo must keep before the summary gives up a line.
  double get minLogoHeight => 60 * scale;

  /// Below this nothing legible fits — not a logo, not a line of type at a
  /// sensible size. The floor where the title falls back to text.
  double get minTitleHeight => 30 * scale;

  double get maxTitleFontSize => 56 * scale;

  /// A logo wider than this stops reading as a title and starts reading as a
  /// banner. The hero layout takes the narrower of the two: with the backdrop
  /// filling the screen behind it, a wide wordmark covers the picture, and the
  /// mark sits directly above the facts row — measured against that row rather
  /// than against the screen, so the two read as one stack.
  double get desiredLogoWidth => (heroLayout ? 280.0 : 553.0) * scale;

  /// Room for the facts line, which is a row of outlined boxes rather than
  /// bare text: the box adds its padding and its outline around the type.
  /// Budgeted here because the whole header is laid out from these numbers —
  /// too little and the boxes are cut off top and bottom.
  ///
  /// 33 rather than the ~28 the device font needs at the row's 16pt: a line's
  /// height comes from the font, and the one the tests measure with is taller
  /// than Roboto. The spare few points cost the summary nothing measurable and
  /// cover both. Any more and the slack shows as air around the boxes, because
  /// the row is centred in whatever this reserves.
  double get metadataLineHeight => 33 * scale;

  /// Between the two rows of facts, where there are two.
  double get metadataRowGap => 6 * scale;

  /// The facts, one row or two.
  double get metadataBlockHeight => hasQualityLine ? metadataLineHeight * 2 + metadataRowGap : metadataLineHeight;

  double get genreLineHeight => 22 * scale;

  double get episodeTitleLineHeight => 30 * scale;

  double get episodeTitleGap => 4 * scale;

  double get genreGap => 6 * scale;

  double get logoMetadataGap => 10 * scale;

  /// Air above the summary. Wider in the hero layout: a six-line block needs
  /// separating from the facts above it, or the two read as one paragraph.
  double get summaryGap => (heroLayout ? 16.0 : 6.0) * scale;

  double get summaryFontSize => availableHeight < 260 * scale ? 16.2 * scale : 18 * scale;

  double get summaryLineHeight => summaryFontSize * 1.35;

  double get actionHeight => 46 * scale;

  /// Air below the summary, before the buttons.
  double get actionGap => (heroLayout ? 24.0 : 12.0) * scale;

  double get genreBlockHeight => hasGenres ? genreGap + genreLineHeight : 0.0;

  double get episodeTitleBlockHeight => hasEpisodeTitle ? episodeTitleLineHeight + episodeTitleGap : 0.0;

  double summaryHeightFor(int lines) => lines > 0 ? summaryGap + (summaryLineHeight * lines) : 0.0;

  /// Everything except the title box, for a summary of [lines] lines.
  double fixedHeightFor(int lines) =>
      logoMetadataGap +
      episodeTitleBlockHeight +
      metadataBlockHeight +
      genreBlockHeight +
      summaryHeightFor(lines) +
      actionGap +
      actionHeight;
}

/// Divides the header's height between the title and the summary.
///
/// The **logo comes first**: the summary walks down from three lines until the
/// logo has the height it needs. A page that could show three lines by
/// dropping its logo keeps the logo instead — the artwork is the page's
/// identity, and the full summary is one press away on the info button.
///
/// Type replaces the logo only where a logo would be too small to read at all
/// ([TvDetailHeaderMetrics.minTitleHeight]). That is the one thing this rule
/// guarantees over the loop it replaced: the page always names itself, where
/// before it could end up showing neither logo nor title.
TvDetailHeaderLayout resolveTvDetailHeaderLayout(TvDetailHeaderMetrics metrics) {
  TvDetailHeaderLayout titled(int lines, double remaining, TvDetailTitleMode mode) {
    final height = mode == TvDetailTitleMode.logo
        ? remaining.clamp(0.0, metrics.desiredLogoHeight)
        : remaining.clamp(0.0, metrics.maxTitleFontSize * 1.2);
    return TvDetailHeaderLayout(
      summaryLines: lines,
      titleHeight: height,
      titleMode: mode,
      // 1.2 covers a line box's ascent and descent, so the type fills the
      // space it was given without spilling out of it.
      titleFontSize: (height / 1.2).clamp(0.0, metrics.maxTitleFontSize),
    );
  }

  final firstLines = metrics.hasDescription ? metrics.maxSummaryLines : 0;

  for (var lines = firstLines; lines >= 0; lines--) {
    final remaining = metrics.availableHeight - metrics.fixedHeightFor(lines);
    if (remaining < metrics.minLogoHeight && lines > 0) continue;
    final mode = remaining >= metrics.minTitleHeight ? TvDetailTitleMode.logo : TvDetailTitleMode.text;
    return titled(lines, remaining < 0 ? 0 : remaining, mode);
  }

  return titled(0, 0, TvDetailTitleMode.text);
}

/// How much height the rows have to give up so three lines of description fit.
///
/// Measured twice, because the header is not linear in its own height: the
/// summary type steps up a size once the header passes a threshold, and every
/// line grows with it. A single pass, taken at the squeezed height, therefore
/// asks for less than it needs and lands one line short — which is the whole
/// failure this exists to prevent.
///
/// [hasEpisodeTitle] says whether this page can ever put a focused episode's
/// name on its own line — not whether one is showing. A page that budgets only
/// for the state it is in gives the summary three lines until the first press
/// into the episode rail and one line after it, which is exactly the collapse
/// the give exists to prevent. Same reasoning as the genres below it: the
/// amount must not shift as focus moves, or the rows twitch on every press.
double tvDetailRailDrop({
  required double availableHeight,
  required double scale,
  required double maxDrop,
  bool hasEpisodeTitle = false,
}) {
  double needAt(double height) {
    final metrics = TvDetailHeaderMetrics(
      availableHeight: height,
      scale: scale,
      hasDescription: true,
      hasGenres: true,
      hasEpisodeTitle: hasEpisodeTitle,
    );
    return metrics.fixedHeightFor(3) + metrics.minLogoHeight - height;
  }

  final first = needAt(availableHeight).clamp(0.0, maxDrop);
  // What is still missing *after* that much has been given, added to it —
  // not measured instead of it. The step in type size only shows up once the
  // header has already grown, and it costs a few points more.
  final remainder = needAt(availableHeight + first);
  return remainder > 0 ? (first + remainder).clamp(0.0, maxDrop) : first;
}
