import '../i18n/strings.g.dart';
import '../services/plebz_prefs.dart';

/// The name of an end-of-episode style (Plebz), in the settings and the
/// player's own sheet alike.
String endOfEpisodeStyleLabel(EndOfEpisodeStyle style) => switch (style) {
  EndOfEpisodeStyle.upNextPanel => t.settings.endOfEpisodeUpNextPanel,
  EndOfEpisodeStyle.endCard => t.settings.endOfEpisodeEndCard,
  EndOfEpisodeStyle.plezyPrompt => t.settings.endOfEpisodePlezyPrompt,
};
