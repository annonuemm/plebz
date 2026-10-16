package com.edde746.plezy.homerows

import java.io.File

/**
 * What [HomeRowsProvider] serves (Plebz): the latest snapshot of the app's home rows as JSON, the
 * artwork sources it refers to by key, and the artwork fetched for them.
 *
 * The snapshot names artwork only by key. The source addresses carry server credentials and never
 * leave the app: the provider fetches and serves the bytes itself.
 *
 * Sources are kept one per line as `key<TAB>address`, so the store reads and writes them without
 * a JSON parser and stays testable on a plain JVM.
 */
internal class HomeRowsStore(private val dataDir: File, private val artDir: File) {
  private companion object {
    const val SNAPSHOT = "snapshot.json"
    const val SOURCES = "sources.txt"
    val KEY = Regex("^[a-f0-9]{40}$")
  }

  /** Replaces the snapshot and its sources, and drops artwork no source names any more. */
  @Synchronized
  fun write(snapshot: String, sources: Map<String, String>) {
    dataDir.mkdirs()
    val valid = sources.filter { (key, address) -> KEY.matches(key) && address.none { it == '\n' || it == '\t' } }
    replace(File(dataDir, SOURCES), valid.entries.joinToString("\n") { "${it.key}\t${it.value}" })
    replace(File(dataDir, SNAPSHOT), snapshot)
    artDir.listFiles()?.forEach { file -> if (file.name !in valid) file.delete() }
  }

  @Synchronized
  fun snapshot(): String? = File(dataDir, SNAPSHOT).takeIf { it.isFile }?.readText()

  /** The address behind [key], or null when the latest snapshot names no such artwork. */
  @Synchronized
  fun source(key: String): String? {
    if (!KEY.matches(key)) return null
    val sources = File(dataDir, SOURCES).takeIf { it.isFile } ?: return null
    return sources.useLines { lines ->
      lines.firstNotNullOfOrNull { line ->
        val tab = line.indexOf('\t')
        if (tab > 0 && line.substring(0, tab) == key) line.substring(tab + 1) else null
      }
    }
  }

  /** Where the artwork for [key] is kept; null for anything that is not a key. */
  fun artFile(key: String): File? = if (KEY.matches(key)) File(artDir, key) else null

  @Synchronized
  fun clear() {
    File(dataDir, SNAPSHOT).delete()
    File(dataDir, SOURCES).delete()
    artDir.deleteRecursively()
  }

  private fun replace(target: File, text: String) {
    val staging = File(target.parentFile, "${target.name}.tmp")
    staging.writeText(text)
    if (!staging.renameTo(target)) {
      target.delete()
      staging.renameTo(target)
    }
  }
}
