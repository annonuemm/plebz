package com.edde746.plezy.homerows

import java.io.File
import java.util.concurrent.ConcurrentHashMap

/**
 * What [HomeRowsProvider] serves (Plebz): the latest snapshot of the app's home rows as JSON, the
 * artwork sources it refers to by key, and the artwork fetched for them.
 *
 * The snapshot names artwork only by key. The source addresses carry server credentials and never
 * leave the app: the provider fetches and serves the bytes itself. On disk they are kept only
 * sealed by [seal]; a store whose seal fails keeps none, so the artwork not fetched yet stays
 * missing until the app writes again, rather than the tokens lying in a plain file.
 *
 * Sources are kept one per line as `key<TAB>address` inside the seal, so the store reads and
 * writes them without a JSON parser and stays testable on a plain JVM.
 */
internal class HomeRowsStore(
  private val dataDir: File,
  private val artDir: File,
  private val seal: SourceSeal = KeystoreSourceSeal,
) {
  private companion object {
    const val SNAPSHOT = "snapshot.json"
    const val SOURCES = "sources.sealed"

    /** Where sources were kept in plain text before they were sealed; removed on sight. */
    const val LEGACY_SOURCES = "sources.txt"
    val KEY = Regex("^[a-f0-9]{40}$")

    /**
     * The opened sources per file, so a launcher asking for a whole row of artwork opens the
     * file once rather than once per picture. Shared by every store on the same folder, since
     * the provider makes a new store per call; stamped with the file's size and time, and set
     * directly by [write].
     */
    val opened = ConcurrentHashMap<String, Pair<Long, Map<String, String>>>()
  }

  private val sourcesFile get() = File(dataDir, SOURCES)

  /** Replaces the snapshot and its sources, and drops artwork no source names any more. */
  @Synchronized
  fun write(snapshot: String, sources: Map<String, String>) {
    dataDir.mkdirs()
    File(dataDir, LEGACY_SOURCES).delete()
    val valid = sources.filter { (key, address) -> KEY.matches(key) && address.none { it == '\n' || it == '\t' } }
    val file = sourcesFile
    val sealed = runCatching { seal.seal(valid.entries.joinToString("\n") { "${it.key}\t${it.value}" }.toByteArray()) }
    sealed.fold(
      onSuccess = { bytes ->
        replace(file, bytes)
        opened[file.path] = stamp(file) to valid
      },
      onFailure = {
        file.delete()
        opened.remove(file.path)
      },
    )
    replace(File(dataDir, SNAPSHOT), snapshot.toByteArray())
    artDir.listFiles()?.forEach { art -> if (art.name !in valid) art.delete() }
  }

  @Synchronized
  fun snapshot(): String? = File(dataDir, SNAPSHOT).takeIf { it.isFile }?.readText()

  /** The address behind [key], or null when the latest snapshot names no such artwork. */
  @Synchronized
  fun source(key: String): String? {
    if (!KEY.matches(key)) return null
    return sources()[key]
  }

  private fun sources(): Map<String, String> {
    File(dataDir, LEGACY_SOURCES).delete()
    val file = sourcesFile
    if (!file.isFile) return emptyMap()
    val stamp = stamp(file)
    opened[file.path]?.let { (at, sources) -> if (at == stamp) return sources }
    val text = runCatching { String(seal.open(file.readBytes())) }.getOrNull() ?: return emptyMap()
    val sources = text.lineSequence().mapNotNull { line ->
      val tab = line.indexOf('\t')
      if (tab > 0) line.substring(0, tab) to line.substring(tab + 1) else null
    }.toMap()
    opened[file.path] = stamp to sources
    return sources
  }

  /** Where the artwork for [key] is kept; null for anything that is not a key. */
  fun artFile(key: String): File? = if (KEY.matches(key)) File(artDir, key) else null

  @Synchronized
  fun clear() {
    File(dataDir, SNAPSHOT).delete()
    File(dataDir, LEGACY_SOURCES).delete()
    sourcesFile.delete()
    opened.remove(sourcesFile.path)
    artDir.deleteRecursively()
  }

  private fun stamp(file: File): Long = file.lastModified() * 31 + file.length()

  private fun replace(target: File, bytes: ByteArray) {
    val staging = File(target.parentFile, "${target.name}.tmp")
    staging.writeBytes(bytes)
    if (!staging.renameTo(target)) {
      target.delete()
      staging.renameTo(target)
    }
  }
}
