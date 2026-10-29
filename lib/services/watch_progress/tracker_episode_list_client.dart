import '../../media/media_item.dart';

/// A server that can list a series' episodes lighter than its general list
/// (fork addition).
///
/// Finding a tracker-led profile's next episode needs the season and episode
/// numbers only; the audio and subtitle tracks of every episode made a long
/// series' list several times larger.
abstract interface class TrackerEpisodeListClient {
  /// Every episode of [seriesId], without their audio and subtitle tracks.
  Future<List<MediaItem>> fetchEpisodesWithoutStreams(String seriesId);
}
