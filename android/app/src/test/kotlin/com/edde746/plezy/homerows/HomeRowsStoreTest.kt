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
  /** Stands in for the Keystore, which a plain JVM lacks: reversible, and never the plain bytes. */
  private class FakeSeal : SourceSeal {
    var broken = false

    override fun seal(plain: ByteArray): ByteArray {
      check(!broken) { "Keystore unavailable" }
      return MARK + plain.map { (it.toInt() xor 0x5a).toByte() }
    }

    override fun open(sealed: ByteArray): ByteArray {
      check(!broken) { "Keystore unavailable" }
      require(sealed.take(MARK.size) == MARK.toList()) { "not sealed by this key" }
      return sealed.drop(MARK.size).map { (it.toInt() xor 0x5a).toByte() }.toByteArray()
    }

    companion object {
      val MARK = byteArrayOf(1, 2, 3)
    }
  }

  private lateinit var root: File
  private lateinit var seal: FakeSeal
  private lateinit var store: HomeRowsStore
  private val keyA = "a".repeat(40)
  private val keyB = "b".repeat(40)

  @Before
  fun setUp() {
    root = Files.createTempDirectory("home_rows").toFile()
    seal = FakeSeal()
    store = HomeRowsStore(File(root, "data"), File(root, "art"), seal)
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

  @Test
  fun keepsTheAddressesOnlySealed() {
    store.write("{}", mapOf(keyA to "https://server/a?X-Plex-Token=secret"))

    val onDisk = File(root, "data").listFiles()!!.joinToString("") { String(it.readBytes()) }
    assertFalse("the token is not on disk in plain text", onDisk.contains("secret"))
    val fresh = HomeRowsStore(File(root, "data"), File(root, "art"), seal)
    assertEquals("https://server/a?X-Plex-Token=secret", fresh.source(keyA))
  }

  @Test
  fun aFailingSealKeepsNoSources() {
    store.write("{}", mapOf(keyA to "https://server/a?X-Plex-Token=old"))
    seal.broken = true

    store.write("""{"schema":2}""", mapOf(keyB to "https://server/b?X-Plex-Token=new"))

    assertEquals("""{"schema":2}""", store.snapshot())
    val onDisk = File(root, "data").listFiles()!!.joinToString("") { String(it.readBytes()) }
    assertFalse(onDisk.contains("new"))
    assertNull(store.source(keyB))
    assertNull("the older sources do not linger either", store.source(keyA))
  }

  @Test
  fun anUnreadableFileNamesNoSource() {
    store.write("{}", mapOf(keyA to "https://server/a"))
    File(root, "data/sources.sealed").writeBytes(byteArrayOf(9, 9, 9, 9))

    val fresh = HomeRowsStore(File(root, "data"), File(root, "art"), seal)
    assertNull(fresh.source(keyA))
  }

  @Test
  fun removesThePlainFileOfOlderVersions() {
    val legacy = File(root, "data/sources.txt").apply {
      parentFile!!.mkdirs()
      writeText("$keyA\thttps://server/a?X-Plex-Token=t")
    }

    assertNull("a plain file is not read", store.source(keyA))
    assertFalse(legacy.exists())
  }
}
