package com.edde746.plezy.homerows

import java.io.File
import javax.xml.parsers.DocumentBuilderFactory
import org.junit.Assert.assertEquals
import org.junit.Test
import org.w3c.dom.Document
import org.w3c.dom.Element

/**
 * [HomeRowsProvider] is exported so a launcher signed with the app's key can read it, and checks no caller itself: the
 * signature permission in the manifest is all that keeps every other app out.
 */
class HomeRowsManifestTest {
  private companion object {
    const val ANDROID_NAMESPACE = "http://schemas.android.com/apk/res/android"
    const val AUTHORITY = "app.plebz.homerows"
    const val PERMISSION = "app.plebz.permission.HOME_ROWS"
    val MANIFEST_CANDIDATES = listOf(
      "src/main/AndroidManifest.xml",
      "app/src/main/AndroidManifest.xml",
      "android/app/src/main/AndroidManifest.xml"
    )
  }

  @Test
  fun providerIsGuardedBySignaturePermission() {
    val manifest = manifest()
    val provider = element(manifest, "provider") { it.getAttributeNS(ANDROID_NAMESPACE, "authorities") == AUTHORITY }
    val permission = element(manifest, "permission") { it.getAttributeNS(ANDROID_NAMESPACE, "name") == PERMISSION }

    assertEquals("true", provider.getAttributeNS(ANDROID_NAMESPACE, "exported"))
    assertEquals(PERMISSION, provider.getAttributeNS(ANDROID_NAMESPACE, "readPermission"))
    assertEquals(PERMISSION, provider.getAttributeNS(ANDROID_NAMESPACE, "writePermission"))
    assertEquals("", provider.getAttributeNS(ANDROID_NAMESPACE, "permission"))
    assertEquals("", provider.getAttributeNS(ANDROID_NAMESPACE, "grantUriPermissions"))
    assertEquals("signature", permission.getAttributeNS(ANDROID_NAMESPACE, "protectionLevel"))
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
