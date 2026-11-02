package com.edde746.plezy.ambient

import android.view.KeyEvent
import kotlin.random.Random

/** A club on a game's scene: its crest by key and the colour it is known by. */
internal data class AmbientTeam(val name: String, val image: String?, val colour: Int?)

/**
 * One scene of the screensaver, worded by the app (`AmbientFeed`): what it says and shows, and the
 * `plebz://` link OK opens. Pictures are keys into the ambient store.
 */
internal data class AmbientScene(
  val kind: String,
  val kicker: String,
  val title: String,
  val subtitle: String? = null,
  val image: String? = null,
  val logo: String? = null,
  val posters: List<String> = emptyList(),
  val progress: Double? = null,
  val home: AmbientTeam? = null,
  val away: AmbientTeam? = null,
  val score: String? = null,
  val live: Boolean = false,
  val startsAt: Long? = null,
  val endsAt: Long? = null,
  val validUntil: Long? = null,
  val open: String? = null
) {
  companion object {
    const val CONTINUE = "continue"
    const val LIBRARY = "library"
    const val NEW = "new"
    const val SPORT = "sport"
    const val TV = "tv"
  }
}

/** A line of the "Heute" strip along the bottom; a game carries its clubs' colours. */
internal data class AmbientTickerEntry(
  val time: String?,
  val text: String,
  val live: Boolean = false,
  val startsAt: Long? = null,
  val endsAt: Long? = null,
  val home: Int? = null,
  val away: Int? = null
)

/** The app's look as the start page had it: design and colours. */
internal data class AmbientTheme(val variant: String, val accent: Int, val background: Int, val text: Int) {
  /** Flach paints flat; Original wears Flach's plain surfaces here too. */
  val glass: Boolean get() = variant == "glas"

  companion object {
    val DEFAULT = AmbientTheme("glas", 0xFFA866EE.toInt(), 0xFF08070C.toInt(), 0xFFF3EFFA.toInt())
  }
}

internal data class AmbientSnapshot(
  val updatedAt: Long,
  val theme: AmbientTheme,
  val liveLabel: String,
  /** The app's language (a BCP 47 tag), which the date is written in. */
  val locale: String? = null,
  val scenes: List<AmbientScene>,
  val ticker: List<AmbientTickerEntry>,
  /** Whether the app's look is frosted ("Milchglas"), which the card and the strip then are too. */
  val frost: Boolean = false
)

/** What the paused player handed over (in memory only): the screensaver's first scene. */
internal data class AmbientPause(
  val kicker: String,
  val title: String,
  val subtitle: String?,
  val remaining: String?,
  val hint: String,
  val image: String?
)

/** What a key does on the screensaver, in Android's slot and in the app's own window alike. */
internal object AmbientKeys {
  enum class Effect {
    /** Not the screensaver's: the volume goes on to the device. */
    PASS,

    /** OK, once released: play on or open the scene. */
    ACT,

    /** Any other key ends the screensaver as it goes down. */
    CLOSE,

    /** The other half of a press the screensaver already answered. */
    SWALLOW
  }

  fun effect(keyCode: Int, down: Boolean): Effect = when (keyCode) {
    KeyEvent.KEYCODE_VOLUME_UP, KeyEvent.KEYCODE_VOLUME_DOWN, KeyEvent.KEYCODE_VOLUME_MUTE -> Effect.PASS
    KeyEvent.KEYCODE_DPAD_CENTER, KeyEvent.KEYCODE_ENTER, KeyEvent.KEYCODE_NUMPAD_ENTER, KeyEvent.KEYCODE_BUTTON_A ->
      if (down) Effect.SWALLOW else Effect.ACT
    else -> if (down) Effect.CLOSE else Effect.SWALLOW
  }
}

/** "Milchglas" without a GPU: a small picture blurred once, apart from drawing. */
internal object AmbientFrost {
  /** Blurs [pixels] (ARGB) in place: box passes, which three times over come close to a Gaussian. */
  fun blur(pixels: IntArray, width: Int, height: Int, radius: Int, passes: Int = 3) {
    if (radius <= 0 || width <= 0 || height <= 0) return
    val scratch = IntArray(pixels.size)
    repeat(passes) {
      lines(pixels, scratch, length = width, lines = height, along = 1, across = width, radius = radius)
      lines(scratch, pixels, length = height, lines = width, along = width, across = 1, radius = radius)
    }
  }

  private fun lines(
    from: IntArray,
    to: IntArray,
    length: Int,
    lines: Int,
    along: Int,
    across: Int,
    radius: Int
  ) {
    val span = radius * 2 + 1
    for (line in 0 until lines) {
      val base = line * across
      var alpha = 0
      var red = 0
      var green = 0
      var blue = 0
      for (i in -radius..radius) {
        val pixel = from[base + i.coerceIn(0, length - 1) * along]
        alpha += pixel ushr 24
        red += pixel shr 16 and 0xFF
        green += pixel shr 8 and 0xFF
        blue += pixel and 0xFF
      }
      for (i in 0 until length) {
        to[base + i * along] =
          (alpha / span shl 24) or (red / span shl 16) or (green / span shl 8) or (blue / span)
        val entering = from[base + (i + radius + 1).coerceAtMost(length - 1) * along]
        val leaving = from[base + (i - radius).coerceAtLeast(0) * along]
        alpha += (entering ushr 24) - (leaving ushr 24)
        red += (entering shr 16 and 0xFF) - (leaving shr 16 and 0xFF)
        green += (entering shr 8 and 0xFF) - (leaving shr 8 and 0xFF)
        blue += (entering and 0xFF) - (leaving and 0xFF)
      }
    }
  }
}

/** The screensaver's choices, apart from drawing, so a plain JVM can test them. */
internal object AmbientPlan {
  /** How long a live score from the snapshot is still worth showing. */
  const val SCORE_FRESH_MS = 3 * 60_000L

  /** From 23:00 to 6:00 the screen dims to a clock. */
  fun isNight(hour: Int): Boolean = hour >= 23 || hour < 6

  /** The scenes still true at [now]: what has ended and an outdated "new" left out. */
  fun current(scenes: List<AmbientScene>, now: Long): List<AmbientScene> = scenes.filter { scene ->
    val ended = scene.endsAt?.let { it <= now } ?: false
    val expired = scene.validUntil?.let { it <= now } ?: false
    !ended && !expired
  }

  /** The strip's lines still ahead or running at [now], without the game [shown] large already. */
  fun ticker(entries: List<AmbientTickerEntry>, now: Long, shown: AmbientScene? = null): List<AmbientTickerEntry> =
    entries.filter { entry ->
      val running = entry.endsAt?.let { it > now } ?: true
      val onScreen = shown?.kind == AmbientScene.SPORT && entry.text == shown.title && entry.startsAt == shown.startsAt
      running && !onScreen
    }

  /** A score shows once the game is over, or while the snapshot is fresh enough to be right. */
  fun showsScore(scene: AmbientScene, updatedAt: Long, now: Long): Boolean {
    if (scene.score == null) return false
    if (!scene.live) return true
    return now - updatedAt <= SCORE_FRESH_MS
  }

  /**
   * The order to show [scenes] in: one of each kind in turn, so the library's many titles do not
   * crowd out the game or the reminder, and the library itself in a fresh order each time.
   */
  fun order(scenes: List<AmbientScene>, random: Random = Random.Default): List<AmbientScene> {
    val kinds = listOf(
      AmbientScene.CONTINUE,
      AmbientScene.LIBRARY,
      AmbientScene.NEW,
      AmbientScene.SPORT,
      AmbientScene.TV
    )
    val groups = kinds.map { kind ->
      val ofKind = scenes.filter { it.kind == kind }
      ArrayDeque(if (kind == AmbientScene.LIBRARY) ofKind.shuffled(random) else ofKind)
    }.toMutableList()
    val others = scenes.filter { it.kind !in kinds }
    if (others.isNotEmpty()) groups.add(ArrayDeque(others))
    val ordered = mutableListOf<AmbientScene>()
    while (groups.any { it.isNotEmpty() }) {
      for (group in groups) group.removeFirstOrNull()?.let(ordered::add)
    }
    return ordered
  }

  /** Where the info card sits in turn, so nothing stands still on an OLED screen. */
  fun shift(step: Int): Pair<Int, Int> {
    val offsets = listOf(0 to 0, 18 to -10, 6 to -22, 24 to -4)
    return offsets[Math.floorMod(step, offsets.size)]
  }

  /** How far the clock and the strip may drift from their places (1920×1080 design pixels). */
  const val DRIFT_RANGE = 30

  /**
   * Where the clock and the "Heute" strip sit in turn: the clock in from its corner (left and down),
   * the strip up and in, a little further each scene and never twice in the same spot running.
   */
  fun drift(step: Int): Pair<Int, Int> {
    val offsets = listOf(0 to 0, -12 to 8, -26 to 18, -6 to 30, -20 to 2, -30 to 22)
    return offsets[Math.floorMod(step, offsets.size)]
  }

  /** How far the night clock may stray from the middle and still stand whole on the screen. */
  const val NIGHT_REACH_X = 400
  const val NIGHT_REACH_Y = 240

  /** Where the night clock stands, from the middle: somewhere well apart every few minutes. */
  fun nightSpot(step: Int): Pair<Int, Int> {
    val spots = listOf(
      0 to 0,
      -380 to -200,
      360 to 180,
      -320 to 220,
      400 to -180,
      0 to 240,
      -400 to 20,
      380 to 40,
      0 to -230
    )
    return spots[Math.floorMod(step, spots.size)]
  }
}
