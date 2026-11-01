package com.edde746.plezy.homerows

import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * Encrypts what [HomeRowsStore] keeps of the artwork sources (Plebz). Their addresses carry server
 * tokens (`X-Plex-Token`, Jellyfin's `api_key`), which the app otherwise keeps only in its
 * credential vault.
 */
internal interface SourceSeal {
  fun seal(plain: ByteArray): ByteArray

  /** Throws when [sealed] cannot be opened: the key is gone, or the bytes are not its. */
  fun open(sealed: ByteArray): ByteArray
}

/**
 * AES-256-GCM under a key that never leaves the Android Keystore, so a copy of the app's files —
 * from a rooted box, a forensic image — does not hand out the tokens in the addresses. The stored
 * form is the IV followed by ciphertext and tag, as in `VaultKeyChannel`.
 */
internal object KeystoreSourceSeal : SourceSeal {
  private const val ALIAS = "plebz_home_rows_sources_v1"
  private const val TRANSFORMATION = "AES/GCM/NoPadding"
  private const val IV_BYTES = 12
  private const val TAG_BITS = 128

  override fun seal(plain: ByteArray): ByteArray {
    val cipher = Cipher.getInstance(TRANSFORMATION)
    cipher.init(Cipher.ENCRYPT_MODE, key(create = true))
    return cipher.iv + cipher.doFinal(plain)
  }

  override fun open(sealed: ByteArray): ByteArray {
    require(sealed.size > IV_BYTES + TAG_BITS / 8) { "sealed sources too short" }
    val cipher = Cipher.getInstance(TRANSFORMATION)
    cipher.init(Cipher.DECRYPT_MODE, key(create = false), GCMParameterSpec(TAG_BITS, sealed, 0, IV_BYTES))
    return cipher.doFinal(sealed, IV_BYTES, sealed.size - IV_BYTES)
  }

  @Synchronized
  private fun key(create: Boolean): SecretKey {
    val keyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
    (keyStore.getKey(ALIAS, null) as? SecretKey)?.let { return it }
    check(create) { "The home rows key is not in the Keystore" }
    val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
    generator.init(
      KeyGenParameterSpec.Builder(ALIAS, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
        .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
        .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
        .setKeySize(256)
        .build()
    )
    return generator.generateKey()
  }
}
