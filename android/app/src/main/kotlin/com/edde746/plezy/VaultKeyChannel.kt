package com.edde746.plezy

import android.os.Handler
import android.os.Looper
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.security.KeyStore
import java.util.concurrent.Executors
import javax.crypto.AEADBadTagException
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * Plebz: wraps the credential vault's key with a key that never leaves the Android Keystore.
 *
 * The vault seals every stored token with an AES key kept in the app's preferences; with this,
 * the preferences hold only that key encrypted (AES-256-GCM) under a Keystore key, so a copy of
 * the app's files — from a rooted box, a forensic image — no longer opens the tokens.
 *
 * Errors come back by kind, because the Dart side must treat them differently:
 * - `UNAVAILABLE`: the Keystore failed for now (some boxes refuse it shortly after boot). Nothing
 *   may be overwritten; the next access tries again.
 * - `KEY_GONE`: the wrapping key does not exist. What it wrapped cannot be recovered.
 * - `CORRUPT`: the wrapped value does not belong to the key. Equally unrecoverable.
 */
internal class VaultKeyChannel {
  companion object {
    private const val CHANNEL = "com.plebz/vault_key"
    private const val ALIAS = "plebz_vault_wrap_v1"
    private const val TRANSFORMATION = "AES/GCM/NoPadding"
    private const val IV_BYTES = 12
    private const val TAG_BITS = 128
  }

  private val executor = Executors.newSingleThreadExecutor()
  private val main = Handler(Looper.getMainLooper())

  fun attach(messenger: BinaryMessenger) {
    MethodChannel(messenger, CHANNEL).setMethodCallHandler(::onMethodCall)
  }

  private fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
    val input = call.arguments as? ByteArray
    if (input == null) {
      result.error("BAD_ARGUMENT", "bytes are required", null)
      return
    }
    when (call.method) {
      "wrap" -> run(result) { wrap(input) }
      "unwrap" -> run(result) { unwrap(input) }
      else -> result.notImplemented()
    }
  }

  private fun run(result: MethodChannel.Result, work: () -> ByteArray) {
    executor.execute {
      val outcome: Result<ByteArray> = runCatching(work)
      main.post {
        outcome.fold(
          onSuccess = { result.success(it) },
          onFailure = { error ->
            when (error) {
              is KeyGoneException -> result.error("KEY_GONE", error.message, null)
              is AEADBadTagException, is IllegalArgumentException -> result.error("CORRUPT", error.message, null)
              else -> result.error("UNAVAILABLE", error.message ?: error.javaClass.simpleName, null)
            }
          },
        )
      }
    }
  }

  private class KeyGoneException : Exception("The vault wrapping key is not in the Keystore")

  private fun keyStore(): KeyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }

  /** The wrapping key; made the first time something is wrapped. */
  private fun wrappingKey(create: Boolean): SecretKey {
    (keyStore().getKey(ALIAS, null) as? SecretKey)?.let { return it }
    if (!create) throw KeyGoneException()
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

  /** IV followed by ciphertext and tag. */
  private fun wrap(plain: ByteArray): ByteArray {
    val cipher = Cipher.getInstance(TRANSFORMATION)
    cipher.init(Cipher.ENCRYPT_MODE, wrappingKey(create = true))
    return cipher.iv + cipher.doFinal(plain)
  }

  private fun unwrap(blob: ByteArray): ByteArray {
    require(blob.size > IV_BYTES + TAG_BITS / 8) { "wrapped value too short" }
    val cipher = Cipher.getInstance(TRANSFORMATION)
    cipher.init(
      Cipher.DECRYPT_MODE,
      wrappingKey(create = false),
      GCMParameterSpec(TAG_BITS, blob, 0, IV_BYTES),
    )
    return cipher.doFinal(blob, IV_BYTES, blob.size - IV_BYTES)
  }
}
