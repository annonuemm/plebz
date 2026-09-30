import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/utils/trailer_urls.dart';

/// A catalog trailer is a YouTube video, and reading its id back out is what
/// lets the app hand it to the YouTube app instead of a browser tab.
void main() {
  test('reads the id out of every shape a provider sends', () {
    expect(youTubeVideoId('dQw4w9WgXcQ'), 'dQw4w9WgXcQ');
    expect(youTubeVideoId('https://www.youtube.com/watch?v=dQw4w9WgXcQ'), 'dQw4w9WgXcQ');
    expect(youTubeVideoId('https://youtu.be/dQw4w9WgXcQ'), 'dQw4w9WgXcQ');
    expect(youTubeVideoId('https://www.youtube.com/embed/dQw4w9WgXcQ'), 'dQw4w9WgXcQ');
    // Extra query parameters ride along on a real Seerr payload.
    expect(youTubeVideoId('https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=42s'), 'dQw4w9WgXcQ');
  });

  test('says nothing for a trailer that is not on YouTube', () {
    // The app-first launch only applies to YouTube; anything else has to go
    // to the platform as it stands, and a wrong id would send it nowhere.
    expect(youTubeVideoId('https://vimeo.com/123456789'), isNull);
    expect(youTubeVideoId('https://example.com/watch?v=dQw4w9WgXcQ'), isNull);
    expect(youTubeVideoId(''), isNull);
    expect(youTubeVideoId(null), isNull);
  });

  test('the watch URL still accepts both forms', () {
    expect(youTubeTrailerUrl('dQw4w9WgXcQ'), 'https://www.youtube.com/watch?v=dQw4w9WgXcQ');
    expect(youTubeTrailerUrl('https://youtu.be/dQw4w9WgXcQ'), 'https://youtu.be/dQw4w9WgXcQ');
  });
}
