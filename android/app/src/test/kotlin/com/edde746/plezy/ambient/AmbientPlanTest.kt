package com.edde746.plezy.ambient

import kotlin.math.abs
import kotlin.random.Random
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class AmbientPlanTest {
  private fun scene(kind: String, title: String = kind, endsAt: Long? = null, validUntil: Long? = null) =
    AmbientScene(kind = kind, kicker = "", title = title, endsAt = endsAt, validUntil = validUntil)

  @Test
  fun nightRunsFromElevenToSix() {
    assertFalse(AmbientPlan.isNight(22))
    assertTrue(AmbientPlan.isNight(23))
    assertTrue(AmbientPlan.isNight(0))
    assertTrue(AmbientPlan.isNight(5))
    assertFalse(AmbientPlan.isNight(6))
  }

  @Test
  fun whatHasEndedOrExpiredIsLeftOut() {
    val now = 1_000_000L
    val kept = AmbientPlan.current(
      listOf(
        scene(AmbientScene.TV, "over", endsAt = now - 1),
        scene(AmbientScene.TV, "running", endsAt = now + 60_000),
        scene(AmbientScene.NEW, "old news", validUntil = now),
        scene(AmbientScene.LIBRARY, "always")
      ),
      now
    )
    assertEquals(listOf("running", "always"), kept.map { it.title })
  }

  @Test
  fun tickerKeepsOnlyWhatIsAheadOrRunning() {
    val now = 5_000L
    val entries = listOf(
      AmbientTickerEntry("19:00", "gone", endsAt = now - 1),
      AmbientTickerEntry("20:15", "later", endsAt = now + 1),
      AmbientTickerEntry(null, "new titles")
    )
    assertEquals(listOf("later", "new titles"), AmbientPlan.ticker(entries, now).map { it.text })
  }

  @Test
  fun aLiveScoreShowsOnlyWhileTheSnapshotIsFresh() {
    val live = AmbientScene(AmbientScene.SPORT, "", "A – B", score = "2:1", live = true)
    val over = live.copy(live = false)
    val written = 0L
    assertTrue(AmbientPlan.showsScore(live, written, AmbientPlan.SCORE_FRESH_MS))
    assertFalse(AmbientPlan.showsScore(live, written, AmbientPlan.SCORE_FRESH_MS + 1))
    assertTrue(AmbientPlan.showsScore(over, written, Long.MAX_VALUE))
    assertFalse(AmbientPlan.showsScore(live.copy(score = null), written, 0))
  }

  @Test
  fun kindsTakeTurnsSoTheLibraryDoesNotCrowdTheRestOut() {
    val scenes = listOf(
      scene(AmbientScene.LIBRARY, "l1"),
      scene(AmbientScene.LIBRARY, "l2"),
      scene(AmbientScene.LIBRARY, "l3"),
      scene(AmbientScene.CONTINUE, "c1"),
      scene(AmbientScene.SPORT, "s1"),
      scene(AmbientScene.TV, "t1"),
      scene(AmbientScene.NEW, "n1")
    )
    val ordered = AmbientPlan.order(scenes, Random(7))
    assertEquals(scenes.size, ordered.size)
    assertEquals(
      listOf(AmbientScene.CONTINUE, AmbientScene.LIBRARY, AmbientScene.NEW, AmbientScene.SPORT, AmbientScene.TV),
      ordered.take(5).map { it.kind }
    )
    assertEquals(setOf("l1", "l2", "l3"), ordered.filter { it.kind == AmbientScene.LIBRARY }.map { it.title }.toSet())
  }

  @Test
  fun theCardNeverStandsStill() {
    val positions = (0 until 4).map(AmbientPlan::shift)
    assertEquals(4, positions.toSet().size)
    assertEquals(AmbientPlan.shift(0), AmbientPlan.shift(4))
    assertEquals(AmbientPlan.shift(3), AmbientPlan.shift(-1))
  }

  @Test
  fun theClockAndTheStripDriftInwardWithinTheirMargin() {
    val spots = (0 until 13).map(AmbientPlan::drift)
    for ((x, y) in spots) {
      assertTrue("$x stays left of the corner", x in -AmbientPlan.DRIFT_RANGE..0)
      assertTrue("$y stays below the top", y in 0..AmbientPlan.DRIFT_RANGE)
    }
    spots.zipWithNext().forEach { (a, b) -> assertNotEquals(a, b) }
    assertTrue(spots.toSet().size >= 5)
  }

  @Test
  fun theNightClockMovesFarAndStaysWhole() {
    val spots = (0 until 19).map(AmbientPlan::nightSpot)
    for ((x, y) in spots) {
      assertTrue(abs(x) <= AmbientPlan.NIGHT_REACH_X)
      assertTrue(abs(y) <= AmbientPlan.NIGHT_REACH_Y)
    }
    spots.zipWithNext().forEach { (a, b) ->
      assertTrue("$a → $b is a real move", abs(a.first - b.first) + abs(a.second - b.second) >= 200)
    }
  }
}
