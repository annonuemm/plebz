package com.edde746.plezy.homerows

import java.io.File
import java.nio.file.Files
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

class HomeRowsStoreTest {
  private lateinit var root: File
  private lateinit var store: HomeRowsStore
  private val keyA = "a".repeat(40)
  private val keyB = "b".repeat(40)

  @Before
  fun setUp() {
    root = Files.createTempDirectory("home_rows").toFile()
    store = HomeRowsStore(File(root, "data"), File(root, "art"))
  }

  @After
  fun tearDown() {
    root.deleteRecursively()
  }

  @Test
  fun keepsTheLatestSnapshotAndItsSources() {
    store.write("""{"schema":1}""", mapOf(keyA to "https://server/a?X-Plex-Token=t"))
    store.write("""{"schema":1,"rows":[]}""", mapOf(keyB to "https://server/b"))

    assertEquals("""{"schema":1,"rows":[]}""", store.snapshot())
    assertEquals("https://server/b", store.source(keyB))
    assertNull("a source of an older snapshot is gone", store.source(keyA))
  }

  @Test
  fun dropsArtworkNoSourceNamesAnyMore() {
    store.write("{}", mapOf(keyA to "https://server/a", keyB to "https://server/b"))
    store.artFile(keyA)!!.apply { parentFile!!.mkdirs(); writeText("a") }
    store.artFile(keyB)!!.apply { writeText("b") }

    store.write("{}", mapOf(keyB to "https://server/b"))

    assertFalse(store.artFile(keyA)!!.exists())
    assertTrue(store.artFile(keyB)!!.exists())
  }

  @Test
  fun answersOnlyForWellFormedKeys() {
    store.write("{}", mapOf("../../etc/passwd" to "https://x", keyA to "https://a\nX-Injected: 1"))

    assertNull(store.artFile("../snapshot.json"))
    assertNull(store.source("../../etc/passwd"))
    assertNull("an address with a line break is not kept", store.source(keyA))
  }

  @Test
  fun clearEmptiesEverything() {
    store.write("{}", mapOf(keyA to "https://server/a"))
    store.artFile(keyA)!!.apply { parentFile!!.mkdirs(); writeText("a") }

    store.clear()

    assertNull(store.snapshot())
    assertNull(store.source(keyA))
    assertFalse(store.artFile(keyA)!!.exists())
  }
}
