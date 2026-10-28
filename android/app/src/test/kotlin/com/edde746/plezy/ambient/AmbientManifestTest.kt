package com.edde746.plezy.ambient

import java.io.File
import javax.xml.parsers.DocumentBuilderFactory
import org.junit.Assert.assertEquals
import org.junit.Test
import org.w3c.dom.Document
import org.w3c.dom.Element

/**
 * The screensaver must be bindable by the system alone: [PlebzAmbientDream] is exported so Android
 * can start it, and `BIND_DREAM_SERVICE` keeps every other app from binding it.
 */
class AmbientManifestTest {
  private companion object {
    const val ANDROID_NAMESPACE = "http://schemas.android.com/apk/res/android"
    const val DREAM = "com.edde746.plezy.ambient.PlebzAmbientDream"
    val MANIFEST_CANDIDATES = listOf(
      "src/main/AndroidManifest.xml",
      "app/src/main/AndroidManifest.xml",
      "android/app/src/main/AndroidManifest.xml"
    )
  }

  @Test
  fun dreamIsGuardedByTheSystemPermission() {
    val service = element(manifest(), "service") { it.getAttributeNS(ANDROID_NAMESPACE, "name") == DREAM }
    assertEquals("true", service.getAttributeNS(ANDROID_NAMESPACE, "exported"))
    assertEquals("android.permission.BIND_DREAM_SERVICE", service.getAttributeNS(ANDROID_NAMESPACE, "permission"))
    val action = service.getElementsByTagName("action").item(0) as Element
    assertEquals("android.service.dreams.DreamService", action.getAttributeNS(ANDROID_NAMESPACE, "name"))
  }

  private fun element(manifest: Document, tag: String, matches: (Element) -> Boolean): Element {
    val nodes = manifest.getElementsByTagName(tag)
    for (index in 0 until nodes.length) {
      val node = nodes.item(index) as Element
      if (matches(node)) return node
    }
    throw AssertionError("No matching <$tag> in the manifest")
  }

  private fun manifest(): Document = DocumentBuilderFactory.newInstance()
    .apply { isNamespaceAware = true }
    .newDocumentBuilder()
    .parse(manifestFile())

  private fun manifestFile(): File {
    var directory: File? = File(System.getProperty("user.dir")).absoluteFile
    while (directory != null) {
      for (candidate in MANIFEST_CANDIDATES) {
        val manifest = File(directory, candidate)
        if (manifest.isFile) return manifest
      }
      directory = directory.parentFile
    }
    throw AssertionError("AndroidManifest.xml not found from ${System.getProperty("user.dir")}")
  }
}
