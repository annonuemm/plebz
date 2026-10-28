package com.edde746.plezy.ambient

import android.graphics.Color
import org.json.JSONArray
import org.json.JSONObject

/** Reads what `AmbientFeed` wrote (Plebz); anything it does not understand is left out. */
internal object AmbientJson {
  fun snapshot(text: String?): AmbientSnapshot? {
    if (text.isNullOrBlank()) return null
    return try {
      val json = JSONObject(text)
      AmbientSnapshot(
        updatedAt = json.optLong("updatedAt"),
        theme = theme(json.optJSONObject("theme")),
        liveLabel = json.optJSONObject("labels")?.optStringOrNull("live") ?: "Live",
        locale = json.optStringOrNull("locale"),
        scenes = json.optJSONArray("scenes").objects().mapNotNull(::scene),
        ticker = json.optJSONArray("ticker").objects().mapNotNull(::tickerEntry)
      )
    } catch (_: Exception) {
      null
    }
  }

  /** The paused title as the channel carries it; null when nothing is paused. */
  fun pause(map: Map<*, *>?): AmbientPause? {
    val title = (map?.get("title") as? String)?.takeIf { it.isNotBlank() } ?: return null
    return AmbientPause(
      kicker = map["kicker"] as? String ?: "",
      title = title,
      subtitle = (map["subtitle"] as? String)?.takeIf { it.isNotBlank() },
      remaining = (map["remaining"] as? String)?.takeIf { it.isNotBlank() },
      hint = map["hint"] as? String ?: "",
      image = (map["image"] as? String)?.takeIf { it.isNotBlank() }
    )
  }

  private fun theme(json: JSONObject?): AmbientTheme {
    val fallback = AmbientTheme.DEFAULT
    if (json == null) return fallback
    return AmbientTheme(
      variant = json.optStringOrNull("variant") ?: fallback.variant,
      accent = colour(json.optStringOrNull("accent")) ?: fallback.accent,
      background = colour(json.optStringOrNull("background")) ?: fallback.background,
      text = colour(json.optStringOrNull("text")) ?: fallback.text
    )
  }

  private fun scene(json: JSONObject): AmbientScene? {
    val kind = json.optStringOrNull("kind") ?: return null
    val title = json.optStringOrNull("title") ?: return null
    return AmbientScene(
      kind = kind,
      kicker = json.optStringOrNull("kicker") ?: "",
      title = title,
      subtitle = json.optStringOrNull("subtitle"),
      image = json.optStringOrNull("image"),
      logo = json.optStringOrNull("logo"),
      posters = json.optJSONArray("posters").strings(),
      progress = if (json.has("progress")) json.optDouble("progress").takeIf { !it.isNaN() } else null,
      home = team(json.optJSONObject("home")),
      away = team(json.optJSONObject("away")),
      score = json.optStringOrNull("score"),
      live = json.optBoolean("live"),
      startsAt = json.optLongOrNull("startsAt"),
      endsAt = json.optLongOrNull("endsAt"),
      validUntil = json.optLongOrNull("validUntil"),
      open = json.optStringOrNull("open")
    )
  }

  private fun team(json: JSONObject?): AmbientTeam? {
    val name = json?.optStringOrNull("name") ?: return null
    return AmbientTeam(name, json.optStringOrNull("image"), colour(json.optStringOrNull("colour")))
  }

  private fun tickerEntry(json: JSONObject): AmbientTickerEntry? {
    val text = json.optStringOrNull("text") ?: return null
    return AmbientTickerEntry(
      time = json.optStringOrNull("time"),
      text = text,
      live = json.optBoolean("live"),
      startsAt = json.optLongOrNull("startsAt"),
      endsAt = json.optLongOrNull("endsAt")
    )
  }

  private fun colour(hex: String?): Int? = try {
    hex?.let(Color::parseColor)
  } catch (_: IllegalArgumentException) {
    null
  }

  private fun JSONObject.optStringOrNull(name: String): String? =
    if (has(name) && !isNull(name)) optString(name).takeIf { it.isNotBlank() } else null

  private fun JSONObject.optLongOrNull(name: String): Long? = if (has(name) && !isNull(name)) optLong(name) else null

  private fun JSONArray?.objects(): List<JSONObject> =
    if (this == null) emptyList() else (0 until length()).mapNotNull { optJSONObject(it) }

  private fun JSONArray?.strings(): List<String> =
    if (this == null) emptyList() else (0 until length()).mapNotNull { optString(it).takeIf(String::isNotBlank) }
}
