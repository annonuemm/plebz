package com.edde746.plezy.exoplayer

import androidx.media3.common.MimeTypes
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class PlaybackMimeTypeTest {

  @Test
  fun livePlaylistIsPinnedToHls() {
    // Plex and Jellyfin hand over a manifest whose URL need not say so, which
    // is the whole reason the MIME is pinned rather than sniffed.
    assertEquals(
      MimeTypes.APPLICATION_M3U8,
      playbackMimeType(isLive = true, uri = "https://plex.example/video/:/transcode/universal/start")
    )
    assertEquals(
      MimeTypes.APPLICATION_M3U8,
      playbackMimeType(isLive = true, uri = "http://panel.example:8080/live/user/pass/1234.m3u8")
    )
  }

  @Test
  fun liveTransportStreamIsLeftToTheExtractor() {
    // An M3U playlist entry is whatever the provider wrote. Read as a
    // playlist, a transport stream fails on its first packet.
    assertNull(playbackMimeType(isLive = true, uri = "http://panel.example:8080/live/user/pass/1234.ts"))
    assertNull(playbackMimeType(isLive = true, uri = "http://panel.example:8080/live/user/pass/1234.ts?token=abc"))
    assertNull(playbackMimeType(isLive = true, uri = "http://provider.example/channel.mkv"))
  }

  @Test
  fun aDotInThePathIsNotAnExtension() {
    // Hosts and path segments carry dots of their own; only the last segment
    // names a container.
    assertEquals(
      MimeTypes.APPLICATION_M3U8,
      playbackMimeType(isLive = true, uri = "http://panel.example:8080/live.tv/user/stream")
    )
  }

  @Test
  fun nonLivePlaybackUsesNormalSourceInference() {
    assertNull(playbackMimeType(isLive = false, uri = "http://server.example/file.mkv"))
    assertNull(playbackMimeType(isLive = false, uri = "http://server.example/stream.m3u8"))
  }
}
