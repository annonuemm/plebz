part of '../../plex_client.dart';

/// Plex's "UltraBlur" background colours (fork addition).
mixin _PlexUltraBlurMethods on _PlexClientInternals {
  /// The four corner colours the server derives from the image at [imageUrl]
  /// — a library path such as `/library/metadata/1/art/2`, or an absolute URL
  /// (the catalogue's artwork). Null when the server has none to give.
  Future<UltraBlurColors?> fetchUltraBlurColors(String imageUrl) async {
    final response = await _getWithFailover('/services/ultrablur/colors', queryParameters: {'url': imageUrl});
    return UltraBlurColors.fromJson(_getMediaContainer(response)?['UltraBlurColors']);
  }
}
