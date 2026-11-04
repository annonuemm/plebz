package com.edde746.plezy.ambient

import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.ColorFilter
import android.graphics.Paint
import android.graphics.Path
import android.graphics.PixelFormat
import android.graphics.Rect
import android.graphics.RectF
import android.graphics.Typeface
import android.graphics.drawable.ColorDrawable
import android.graphics.drawable.Drawable
import android.graphics.drawable.GradientDrawable
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.text.TextUtils
import android.text.format.DateFormat
import android.util.Log
import android.util.TypedValue
import android.view.Gravity
import android.view.KeyEvent
import android.view.View
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextClock
import android.widget.TextView
import com.edde746.plezy.homerows.ArtworkFetch
import java.io.File
import java.security.MessageDigest
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/**
 * Plebz Ambient's stage: what the screensaver shows and how it moves on, drawn natively so it
 * starts in a moment on a weak box, whether or not the app is running.
 *
 * It draws what the app last wrote (`AmbientFeed`): the library's pictures, Continue Watching, what
 * is new, today's games and the guide, one scene at a time, with the clock and a "Heute" strip. A
 * film paused in the app comes first, and OK plays it on; on any other scene OK opens what it
 * shows. From 23:00 the screen dims to a clock. Two hosts show it: Android's screensaver slot
 * ([PlebzAmbientDream]) and the app's own window ([AmbientInApp]).
 */
internal class AmbientStage(private val context: Context, private val host: Host) {
  /** What the stage needs from whoever shows it. */
  interface Host {
    /** Ends the screensaver. */
    fun close()

    /** Night asks for a dim screen, morning for the usual brightness again. */
    fun setBright(bright: Boolean)

    /** OK on the paused title: play it on. */
    fun resume()
  }

  private companion object {
    const val TAG = "AmbientStage"
    const val SCENE_MS = 25_000L
    const val NIGHT_SCENE_MS = 300_000L
    const val FADE_MS = 1_200L
    const val CARD_FADE_MS = 400L
    const val INTER = "flutter_assets/assets/fonts/Inter-Variable.ttf"
    const val PAUSE_ART = "ambient_pause"
    const val PAUSE_ART_MAX_AGE_MS = 24 * 60 * 60 * 1000L
    const val FROST_WIDTH = 384
    const val FROST_RADIUS = 4
  }

  private sealed class Shown {
    data class Pause(val pause: AmbientPause) : Shown()
    data class Scene(val scene: AmbientScene) : Shown()
  }

  private val main = Handler(Looper.getMainLooper())
  private var loader: ExecutorService? = null
  private var stopped = false
  private var snapshot: AmbientSnapshot? = null
  private var theme = AmbientTheme.DEFAULT
  private val queue = ArrayDeque<Shown>()
  private var current: Shown? = null
  private var step = 0
  private var night: Boolean? = null
  private var scale = 1f
  private val frost = FrostPicture()

  private lateinit var root: FrameLayout
  private lateinit var backs: Array<ImageView>
  private var front = 0
  private lateinit var scrim: View
  private lateinit var clockScrim: View
  private lateinit var crests: LinearLayout
  private lateinit var homeCrest: ImageView
  private lateinit var awayCrest: ImageView
  private lateinit var collage: LinearLayout
  private lateinit var logo: ImageView
  private lateinit var card: LinearLayout
  private lateinit var kicker: TextView
  private lateinit var title: TextView
  private lateinit var subtitle: TextView
  private lateinit var progress: ProgressLine
  private lateinit var hint: TextView
  private lateinit var clockBox: LinearLayout
  private lateinit var date: TextView
  private lateinit var ticker: LinearLayout
  private lateinit var nightLayer: FrameLayout
  private lateinit var nightContent: LinearLayout
  private lateinit var nightClock: TextClock
  private lateinit var nightDate: TextView
  private val tick = Runnable { next() }

  /** The stage, to be laid over the whole screen. */
  val view: View get() = root

  /** Reads the app's last snapshot and begins with the first scene. */
  fun start() {
    stopped = false
    val executor = Executors.newSingleThreadExecutor().also { loader = it }
    executor.execute {
      cleanPauseArt()
      val loaded = try {
        AmbientJson.snapshot(AmbientPlugin.store(context).snapshot())
      } catch (e: Exception) {
        Log.w(TAG, "Ambient snapshot unreadable", e)
        null
      }
      main.post {
        if (stopped) return@post
        snapshot = loaded
        loaded?.theme?.let(::applyTheme)
        next()
      }
    }
  }

  fun stop() {
    stopped = true
    main.removeCallbacks(tick)
    loader?.shutdownNow()
    loader = null
  }

  /** A key while the stage shows; false for one it lets through (the volume). */
  fun onKey(event: KeyEvent): Boolean {
    when (AmbientKeys.effect(event.keyCode, down = event.action == KeyEvent.ACTION_DOWN)) {
      AmbientKeys.Effect.PASS -> return false
      AmbientKeys.Effect.ACT -> act()
      AmbientKeys.Effect.CLOSE -> host.close()
      AmbientKeys.Effect.SWALLOW -> Unit
    }
    return true
  }

  /** OK: play the paused title on, or open what the scene shows; then close. */
  private fun act() {
    when (val shown = current) {
      is Shown.Pause -> host.resume()
      is Shown.Scene -> shown.scene.open?.let(::open)
      null -> Unit
    }
    host.close()
  }

  private fun open(link: String) {
    try {
      context.startActivity(
        Intent(Intent.ACTION_VIEW, Uri.parse(link))
          .setPackage(context.packageName)
          .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
      )
    } catch (e: Exception) {
      Log.w(TAG, "Could not open $link", e)
    }
  }

  // Scenes

  private fun next() {
    main.removeCallbacks(tick)
    if (stopped) return
    val now = System.currentTimeMillis()
    setNight(AmbientPlan.isNight(Calendar.getInstance().get(Calendar.HOUR_OF_DAY)))
    if (queue.isEmpty()) refill(now)
    val shown = queue.removeFirstOrNull()
    if (shown == null) showEmpty() else show(shown)
    main.postDelayed(tick, if (night == true) NIGHT_SCENE_MS else SCENE_MS)
  }

  /** A paused title first, then every scene still true, one kind after another. */
  private fun refill(now: Long) {
    AmbientPlugin.State.pause?.let { queue.addLast(Shown.Pause(it)) }
    val snapshot = snapshot ?: return
    AmbientPlan.order(AmbientPlan.current(snapshot.scenes, now)).forEach { queue.addLast(Shown.Scene(it)) }
  }

  private fun show(shown: Shown) {
    val loader = loader ?: return
    val width = context.resources.displayMetrics.widthPixels
    val height = context.resources.displayMetrics.heightPixels
    loader.execute {
      val scene = (shown as? Shown.Scene)?.scene
      val background = when (shown) {
        is Shown.Pause -> shown.pause.image?.let { loadAddress(it, width, height) }
        is Shown.Scene -> shown.scene.image?.let { loadKey(it, width, height) }
      }
      val posters = scene?.posters?.take(6)?.mapNotNull { loadKey(it, width / 6, height / 2) } ?: emptyList()
      val logoPicture = scene?.logo?.let { loadKey(it, width / 3, height / 3) }
      val home = scene?.home?.image?.let { loadKey(it, 512, 512) }
      val away = scene?.away?.image?.let { loadKey(it, 512, 512) }
      val blurred = background?.takeIf { frosted() }?.let(::frostOf)
      main.post {
        if (!stopped) render(shown, background, blurred, posters, logoPicture, home, away)
      }
    }
  }

  private fun render(
    shown: Shown,
    background: Bitmap?,
    blurred: Bitmap?,
    posters: List<Bitmap>,
    logoPicture: Bitmap?,
    home: Bitmap?,
    away: Bitmap?
  ) {
    current = shown
    val now = System.currentTimeMillis()
    crossfade(background)
    frost.bitmap = blurred
    scrim.visibility = if (background != null) View.VISIBLE else View.GONE
    clockScrim.visibility = scrim.visibility

    val scene = (shown as? Shown.Scene)?.scene
    // A game stands on the plain ground, its crests alone (the user's call: no clubs' colours).
    val sport = scene?.kind == AmbientScene.SPORT
    crests.visibility = if (sport && (home != null || away != null)) View.VISIBLE else View.GONE
    homeCrest.setImageBitmap(home)
    awayCrest.setImageBitmap(away)

    collage.visibility = if (posters.isNotEmpty() && background == null) View.VISIBLE else View.GONE
    collage.removeAllViews()
    for (poster in posters) {
      collage.addView(
        ImageView(context).apply {
          setImageBitmap(poster)
          scaleType = ImageView.ScaleType.CENTER_CROP
          clipToOutline = true
          outlineProvider = RoundedOutline(px(14))
        },
        LinearLayout.LayoutParams(px(200), px(300)).apply { marginEnd = px(24) }
      )
    }
    logo.visibility = if (logoPicture != null && background == null) View.VISIBLE else View.GONE
    logo.setImageBitmap(logoPicture)

    when (shown) {
      is Shown.Pause -> fill(
        kicker = shown.pause.kicker,
        title = shown.pause.title,
        subtitle = listOfNotNull(shown.pause.subtitle, shown.pause.remaining).joinToString(" · "),
        progress = null,
        hint = shown.pause.hint
      )
      is Shown.Scene -> {
        val snapshot = snapshot
        val showsScore = snapshot != null && AmbientPlan.showsScore(shown.scene, snapshot.updatedAt, now)
        fill(
          kicker = shown.scene.kicker,
          title = shown.scene.title,
          subtitle = listOfNotNull(
            if (showsScore) shown.scene.score else null,
            shown.scene.subtitle
          ).joinToString(" · "),
          progress = shown.scene.progress,
          hint = null
        )
      }
    }
    card.animate().cancel()
    card.alpha = 0f
    place()
    card.animate().alpha(1f).setDuration(CARD_FADE_MS).start()
    fillTicker(now)
    // The strip's lines and the frost behind them change with the scene: not in one hard step.
    ticker.animate().cancel()
    ticker.alpha = 0f
    ticker.animate().alpha(1f).setDuration(CARD_FADE_MS).start()
    date.text = dateLine()
    nightDate.text = dateLine()
  }

  private fun showEmpty() {
    current = null
    crossfade(null)
    frost.bitmap = null
    scrim.visibility = View.GONE
    clockScrim.visibility = View.GONE
    crests.visibility = View.GONE
    collage.visibility = View.GONE
    logo.visibility = View.GONE
    fill(kicker = "", title = "Plebz", subtitle = "", progress = null, hint = null)
    card.alpha = 1f
    ticker.alpha = 1f
    place()
    fillTicker(System.currentTimeMillis())
    date.text = dateLine()
    nightDate.text = dateLine()
  }

  /**
   * Moves everything that stays on screen with each scene — the card, the clock and the strip a
   * little, the night clock far — so an OLED panel keeps no trace of any of them.
   */
  private fun place() {
    step++
    val (cardX, cardY) = AmbientPlan.shift(step)
    card.translationX = cardX * scale
    card.translationY = cardY * scale
    // Under the card and flush with it wherever it has wandered to.
    ticker.translationX = cardX * scale
    ticker.translationY = cardY * scale
    val (driftX, driftY) = AmbientPlan.drift(step)
    clockBox.animate().translationX(driftX * scale).translationY(driftY * scale).setDuration(FADE_MS).start()
    val (nightX, nightY) = AmbientPlan.nightSpot(step)
    moveNightClock(nightX * scale, nightY * scale)
  }

  /** At night the clock fades out where it stood and in at its next spot; by day it just waits there. */
  private fun moveNightClock(x: Float, y: Float) {
    nightContent.animate().cancel()
    if (night != true) {
      nightContent.translationX = x
      nightContent.translationY = y
      nightContent.alpha = 1f
      return
    }
    nightContent.animate().alpha(0f).setDuration(FADE_MS / 2).withEndAction {
      nightContent.translationX = x
      nightContent.translationY = y
      nightContent.animate().alpha(1f).setDuration(FADE_MS / 2).start()
    }.start()
  }

  private fun fill(kicker: String, title: String, subtitle: String, progress: Double?, hint: String?) {
    this.kicker.text = kicker
    this.kicker.visibility = if (kicker.isBlank()) View.GONE else View.VISIBLE
    this.title.text = title
    this.subtitle.text = subtitle
    this.subtitle.visibility = if (subtitle.isBlank()) View.GONE else View.VISIBLE
    this.progress.fraction = progress?.toFloat()
    this.progress.visibility = if (progress == null) View.GONE else View.VISIBLE
    this.hint.text = hint ?: ""
    this.hint.visibility = if (hint.isNullOrBlank()) View.GONE else View.VISIBLE
  }

  private fun fillTicker(now: Long) {
    ticker.removeAllViews()
    val shown = (current as? Shown.Scene)?.scene
    val entries = snapshot?.let { AmbientPlan.ticker(it.ticker, now, shown) } ?: emptyList()
    ticker.visibility = if (entries.isEmpty() || night == true) View.GONE else View.VISIBLE
    entries.forEachIndexed { index, entry ->
      val last = index == entries.lastIndex
      if (entry.live) ticker.addView(dot(), LinearLayout.LayoutParams(px(10), px(10)).apply {
        marginEnd = px(10)
        gravity = Gravity.CENTER_VERTICAL
      })
      val game = entry.home != null || entry.away != null
      ticker.addView(
        text(22, regular = !game, alpha = if (game) 1f else 0.78f).apply {
          text = listOfNotNull(entry.time, entry.text).joinToString(" ")
          maxLines = 1
          ellipsize = TextUtils.TruncateAt.END
        },
        // A game is told by its weight alone, on the strip's own ground (the user's call: no
        // clubs' colours behind it).
        LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT)
          .apply {
            marginEnd = if (last) 0 else px(36)
            gravity = Gravity.CENTER_VERTICAL
          }
      )
      // As much room at the end as at the start.
      if (last) ticker.setPadding(px(30), 0, px(30), 0)
    }
  }

  private fun crossfade(picture: Bitmap?) {
    val incoming = backs[1 - front]
    val outgoing = backs[front]
    incoming.animate().cancel()
    outgoing.animate().cancel()
    incoming.setImageBitmap(picture)
    incoming.alpha = 0f
    incoming.animate().alpha(if (picture == null) 0f else 1f).setDuration(FADE_MS).start()
    outgoing.animate().alpha(0f).setDuration(FADE_MS).start()
    front = 1 - front
  }

  private fun setNight(on: Boolean) {
    if (night == on) return
    night = on
    host.setBright(!on)
    nightLayer.visibility = if (on) View.VISIBLE else View.GONE
    val day = if (on) View.GONE else View.VISIBLE
    card.visibility = day
    clockBox.visibility = day
    ticker.visibility = day
  }

  // Views

  private val regularFace by lazy { inter(400) }
  private val mediumFace by lazy { inter(500) }

  private fun build() {
    root = FrameLayout(context).apply { background = ColorDrawable(theme.background) }
    val full = FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT)

    backs = Array(2) {
      ImageView(context).apply {
        scaleType = ImageView.ScaleType.CENTER_CROP
        alpha = 0f
      }.also { root.addView(it, FrameLayout.LayoutParams(full)) }
    }
    scrim = View(context)
    root.addView(scrim, FrameLayout.LayoutParams(full))
    // The clock's corner, darkened so it reads on a light picture too.
    clockScrim = View(context)
    root.addView(
      clockScrim,
      FrameLayout.LayoutParams(px(1000), px(700)).apply { gravity = Gravity.END or Gravity.TOP }
    )

    collage = LinearLayout(context).apply {
      orientation = LinearLayout.HORIZONTAL
      gravity = Gravity.CENTER_HORIZONTAL
      visibility = View.GONE
    }
    root.addView(
      collage,
      FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.WRAP_CONTENT).apply {
        topMargin = px(250)
      }
    )

    crests = LinearLayout(context).apply {
      orientation = LinearLayout.HORIZONTAL
      gravity = Gravity.CENTER
      visibility = View.GONE
    }
    homeCrest = ImageView(context).apply { scaleType = ImageView.ScaleType.FIT_CENTER }
    awayCrest = ImageView(context).apply { scaleType = ImageView.ScaleType.FIT_CENTER }
    crests.addView(homeCrest, LinearLayout.LayoutParams(px(300), px(300)).apply { marginEnd = px(160) })
    crests.addView(awayCrest, LinearLayout.LayoutParams(px(300), px(300)))
    root.addView(
      crests,
      FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.WRAP_CONTENT).apply {
        topMargin = px(200)
      }
    )

    logo = ImageView(context).apply {
      scaleType = ImageView.ScaleType.FIT_CENTER
      visibility = View.GONE
    }
    root.addView(
      logo,
      FrameLayout.LayoutParams(px(560), px(320)).apply {
        gravity = Gravity.END or Gravity.CENTER_VERTICAL
        marginEnd = px(220)
      }
    )

    card = LinearLayout(context).apply {
      orientation = LinearLayout.VERTICAL
      setPadding(px(40), px(28), px(40), px(32))
    }
    kicker = text(22, regular = true, alpha = 0.72f)
    title = text(64, regular = false).apply {
      maxLines = 2
      ellipsize = TextUtils.TruncateAt.END
    }
    subtitle = text(28, regular = true, alpha = 0.88f).apply {
      maxLines = 2
      ellipsize = TextUtils.TruncateAt.END
    }
    progress = ProgressLine(context)
    hint = text(22, regular = true, alpha = 0.72f)
    card.addView(kicker)
    card.addView(title, LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT).apply {
      topMargin = px(6)
    })
    card.addView(subtitle, LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT).apply {
      topMargin = px(6)
    })
    card.addView(progress, LinearLayout.LayoutParams(px(420), px(6)).apply { topMargin = px(18) })
    card.addView(hint, LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT).apply {
      topMargin = px(16)
    })
    title.maxWidth = px(1100)
    subtitle.maxWidth = px(1100)
    card.minimumWidth = px(520)
    root.addView(
      card,
      FrameLayout.LayoutParams(FrameLayout.LayoutParams.WRAP_CONTENT, FrameLayout.LayoutParams.WRAP_CONTENT).apply {
        gravity = Gravity.START or Gravity.BOTTOM
        marginStart = px(86)
        bottomMargin = px(140)
      }
    )

    clockBox = LinearLayout(context).apply {
      orientation = LinearLayout.VERTICAL
      gravity = Gravity.END
    }
    clockBox.addView(clock(64))
    date = text(22, regular = true, alpha = 0.72f).apply { gravity = Gravity.END }
    clockBox.addView(date)
    root.addView(
      clockBox,
      FrameLayout.LayoutParams(FrameLayout.LayoutParams.WRAP_CONTENT, FrameLayout.LayoutParams.WRAP_CONTENT).apply {
        gravity = Gravity.END or Gravity.TOP
        marginEnd = px(86)
        topMargin = px(64)
      }
    )

    // A capsule floating over the picture, as the app's own bands do: as long as what it says, and
    // starting where the card above it starts. What runs past the screen's margin is cut at its end.
    ticker = LinearLayout(context).apply {
      orientation = LinearLayout.HORIZONTAL
      gravity = Gravity.CENTER_VERTICAL
      clipToOutline = true
      outlineProvider = RoundedOutline(px(32))
      visibility = View.GONE
    }
    root.addView(
      ticker,
      FrameLayout.LayoutParams(FrameLayout.LayoutParams.WRAP_CONTENT, px(64)).apply {
        gravity = Gravity.START or Gravity.BOTTOM
        leftMargin = px(86)
        rightMargin = px(86)
        bottomMargin = px(36)
      }
    )

    nightLayer = FrameLayout(context).apply {
      background = ColorDrawable(Color.argb(170, 0, 0, 0))
      visibility = View.GONE
    }
    nightContent = LinearLayout(context).apply {
      orientation = LinearLayout.VERTICAL
      gravity = Gravity.CENTER_HORIZONTAL
    }
    nightClock = clock(200, regular = true, alpha = 0.82f)
    nightContent.addView(nightClock)
    nightDate = text(30, regular = true, alpha = 0.6f).apply { gravity = Gravity.CENTER }
    nightContent.addView(nightDate)
    nightLayer.addView(
      nightContent,
      FrameLayout.LayoutParams(FrameLayout.LayoutParams.WRAP_CONTENT, FrameLayout.LayoutParams.WRAP_CONTENT).apply {
        gravity = Gravity.CENTER
      }
    )
    root.addView(nightLayer, FrameLayout.LayoutParams(full))

    applyTheme(theme)
  }

  private fun applyTheme(next: AmbientTheme) {
    theme = next
    root.background = ColorDrawable(next.background)
    scrim.background = GradientDrawable(
      GradientDrawable.Orientation.BL_TR,
      intArrayOf(withAlpha(next.background, 0.88f), withAlpha(next.background, 0.35f), Color.TRANSPARENT)
    )
    // A soft round shade from the corner, with no edge where the box ends.
    clockScrim.background = GradientDrawable().apply {
      gradientType = GradientDrawable.RADIAL_GRADIENT
      gradientRadius = px(620).toFloat()
      setGradientCenter(1f, 0f)
      colors = intArrayOf(withAlpha(next.background, 0.7f), withAlpha(next.background, 0.3f), Color.TRANSPARENT)
    }
    val glass = if (frosted(next)) frost else null
    card.background = CardDrawable(next, px(28).toFloat(), card, glass)
    ticker.background = CardDrawable(next, px(32).toFloat(), ticker, glass)
    progress.track = withAlpha(next.text, 0.25f)
    progress.fill = next.accent
    listOf(kicker, title, subtitle, hint, date, nightDate).forEach { it.setTextColor(next.text) }
    clockBox.getChildAt(0)?.let { (it as TextView).setTextColor(next.text) }
    nightClock.setTextColor(next.text)
  }

  private fun text(size: Int, regular: Boolean, alpha: Float = 1f) = TextView(context).apply {
    setTextSize(TypedValue.COMPLEX_UNIT_PX, size * scale)
    typeface = if (regular) regularFace else mediumFace
    setTextColor(theme.text)
    this.alpha = alpha
    includeFontPadding = false
  }

  private fun clock(size: Int, regular: Boolean = false, alpha: Float = 1f) = TextClock(context).apply {
    format24Hour = "HH:mm"
    format12Hour = "h:mm"
    setTextSize(TypedValue.COMPLEX_UNIT_PX, size * scale)
    typeface = if (regular) regularFace else mediumFace
    setTextColor(theme.text)
    this.alpha = alpha
    includeFontPadding = false
    gravity = Gravity.END
  }

  private fun dot() = View(context).apply {
    background = GradientDrawable().apply {
      shape = GradientDrawable.OVAL
      setColor(theme.accent)
    }
  }

  private fun dateLine(): String {
    val locale = snapshot?.locale?.let(Locale::forLanguageTag) ?: Locale.getDefault()
    val pattern = DateFormat.getBestDateTimePattern(locale, "EEEEdMMMM")
    return SimpleDateFormat(pattern, locale).format(Date())
  }

  private fun inter(weight: Int): Typeface = try {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
      Typeface.Builder(context.assets, INTER).setFontVariationSettings("'wght' $weight").build()
    } else {
      Typeface.createFromAsset(context.assets, INTER)
    }
  } catch (e: Exception) {
    Log.w(TAG, "Inter unavailable", e)
    Typeface.DEFAULT
  }

  private fun px(design: Int): Int = (design * scale).toInt().coerceAtLeast(1)

  // Pictures

  private fun loadKey(key: String, width: Int, height: Int): Bitmap? {
    val store = AmbientPlugin.store(context)
    val file = store.artFile(key) ?: return null
    if (!file.isFile) {
      val source = store.source(key) ?: return null
      try {
        ArtworkFetch.fetch(source, file)
      } catch (e: Exception) {
        return null
      }
    }
    return decode(file, width, height)
  }

  private fun loadAddress(address: String, width: Int, height: Int): Bitmap? {
    val file = File(File(context.cacheDir, PAUSE_ART), sha1(address))
    if (!file.isFile) {
      try {
        ArtworkFetch.fetch(address, file)
      } catch (e: Exception) {
        return null
      }
    }
    return decode(file, width, height)
  }

  private fun cleanPauseArt() {
    val cutoff = System.currentTimeMillis() - PAUSE_ART_MAX_AGE_MS
    File(context.cacheDir, PAUSE_ART).listFiles()?.forEach { if (it.lastModified() < cutoff) it.delete() }
  }

  private fun decode(file: File, width: Int, height: Int): Bitmap? = try {
    val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
    BitmapFactory.decodeFile(file.path, bounds)
    var sample = 1
    while (bounds.outWidth / (sample * 2) >= width && bounds.outHeight / (sample * 2) >= height) sample *= 2
    BitmapFactory.decodeFile(file.path, BitmapFactory.Options().apply { inSampleSize = sample })
  } catch (e: Exception) {
    null
  } catch (e: OutOfMemoryError) {
    null
  }

  private fun sha1(text: String): String =
    MessageDigest.getInstance("SHA-1").digest(text.toByteArray()).joinToString("") { "%02x".format(it) }

  private fun frosted(look: AmbientTheme = theme): Boolean = snapshot?.frost == true && look.glass

  /** [picture] small and blurred: once a scene, so nothing is blurred frame by frame. */
  private fun frostOf(picture: Bitmap): Bitmap? = try {
    val height = (picture.height * FROST_WIDTH / picture.width).coerceAtLeast(1)
    val small = Bitmap.createScaledBitmap(picture, FROST_WIDTH, height, true)
    val pixels = IntArray(FROST_WIDTH * height)
    small.getPixels(pixels, 0, FROST_WIDTH, 0, 0, FROST_WIDTH, height)
    AmbientFrost.blur(pixels, FROST_WIDTH, height, FROST_RADIUS)
    Bitmap.createBitmap(pixels, FROST_WIDTH, height, Bitmap.Config.ARGB_8888)
  } catch (e: OutOfMemoryError) {
    null
  }

  // Last, so every view and face above exists before the stage builds itself.
  init {
    scale = context.resources.displayMetrics.widthPixels / 1920f
    build()
  }
}

private fun withAlpha(colour: Int, alpha: Float): Int =
  Color.argb((alpha * 255).toInt().coerceIn(0, 255), Color.red(colour), Color.green(colour), Color.blue(colour))

/** The blurred picture of the scene on show, which the card and the strip show their part of. */
private class FrostPicture {
  var bitmap: Bitmap? = null

  /** The part of [picture] that lies behind [box] of [host], as the stage crops the picture itself. */
  fun behind(picture: Bitmap, host: View, box: Rect): Rect {
    val stage = host.parent as View
    val share = minOf(picture.width.toFloat() / stage.width, picture.height.toFloat() / stage.height)
    val left = (picture.width - stage.width * share) / 2 + (host.left + host.translationX + box.left) * share
    val top = (picture.height - stage.height * share) / 2 + (host.top + host.translationY + box.top) * share
    return Rect(
      left.toInt(),
      top.toInt(),
      (left + box.width() * share).toInt(),
      (top + box.height() * share).toInt()
    )
  }
}

/**
 * The info card and the strip: with [frost], Milchglas — the blurred picture under a veil of the
 * ground, a hairline round it; otherwise Glas's glass without blur — the ground half see-through,
 * its edge lit from the top left and shaded at the foot — or Flach's flat wash of ink.
 */
private class CardDrawable(
  private val theme: AmbientTheme,
  private val radius: Float,
  private val host: View,
  private val frost: FrostPicture?
) : Drawable() {
  private val fill = Paint(Paint.ANTI_ALIAS_FLAG).apply {
    color = if (theme.glass) withAlpha(theme.background, 0.58f) else withAlpha(theme.text, 0.10f)
  }
  private val picturePaint = Paint(Paint.FILTER_BITMAP_FLAG)
  private val outline = Path()
  private val edge = Paint(Paint.ANTI_ALIAS_FLAG).apply {
    style = Paint.Style.STROKE
    strokeWidth = 2f
  }

  override fun draw(canvas: Canvas) {
    val box = RectF(bounds)
    if (frost != null) {
      drawFrost(canvas, frost, box)
      return
    }
    canvas.drawRoundRect(box, radius, radius, fill)
    if (!theme.glass) return
    val line = RectF(box).apply { inset(1f, 1f) }
    fun stroke(colour: Int, left: Float, top: Float, right: Float, bottom: Float) {
      edge.color = colour
      canvas.save()
      canvas.clipRect(left, top, right, bottom)
      canvas.drawRoundRect(line, radius, radius, edge)
      canvas.restore()
    }
    stroke(withAlpha(Color.WHITE, 0.32f), box.left, box.top, box.right, box.top + radius)
    stroke(withAlpha(Color.WHITE, 0.14f), box.left, box.top + radius, box.left + radius, box.bottom - radius)
    stroke(withAlpha(Color.BLACK, 0.40f), box.left, box.bottom - radius, box.right, box.bottom)
  }

  private fun drawFrost(canvas: Canvas, frost: FrostPicture, box: RectF) {
    val picture = frost.bitmap
    if (picture != null) {
      outline.reset()
      outline.addRoundRect(box, radius, radius, Path.Direction.CW)
      canvas.save()
      canvas.clipPath(outline)
      canvas.drawBitmap(picture, frost.behind(picture, host, bounds), box, picturePaint)
      canvas.restore()
    }
    // A game's scene has no picture: the ground alone behind the veil.
    fill.color = withAlpha(theme.background, if (picture != null) 0.5f else 0.34f)
    canvas.drawRoundRect(box, radius, radius, fill)
    edge.color = withAlpha(Color.WHITE, 0.22f)
    canvas.drawRoundRect(RectF(box).apply { inset(1f, 1f) }, radius, radius, edge)
  }

  override fun setAlpha(alpha: Int) = Unit
  override fun setColorFilter(colorFilter: ColorFilter?) = Unit

  @Deprecated("Deprecated in Java")
  override fun getOpacity(): Int = PixelFormat.TRANSLUCENT
}

/** How far into the title: a thin track with the watched part in the accent. */
private class ProgressLine(context: android.content.Context) : View(context) {
  var track: Int = Color.argb(64, 255, 255, 255)
  var fill: Int = Color.WHITE
  var fraction: Float? = null
    set(value) {
      field = value
      invalidate()
    }
  private val paint = Paint(Paint.ANTI_ALIAS_FLAG)

  override fun onDraw(canvas: Canvas) {
    val radius = height / 2f
    paint.color = track
    canvas.drawRoundRect(0f, 0f, width.toFloat(), height.toFloat(), radius, radius, paint)
    val share = fraction ?: return
    paint.color = fill
    canvas.drawRoundRect(0f, 0f, width * share.coerceIn(0f, 1f), height.toFloat(), radius, radius, paint)
  }
}

/** Rounds a poster's corners the way the app's posters are rounded. */
private class RoundedOutline(private val radius: Int) : android.view.ViewOutlineProvider() {
  override fun getOutline(view: View, outline: android.graphics.Outline) {
    outline.setRoundRect(0, 0, view.width, view.height, radius.toFloat())
  }
}
