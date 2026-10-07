#!/usr/bin/env python3
"""Draw every Plebz logo file from one geometry.

The mark is a play triangle drawn as one thick round-ended stroke: the stem
runs down the left like a "p", the triangle stays open at the bottom, and a
violet-to-pink gradient runs across it. The wordmark is "Plebz" set in Poppins
Bold beside it. Icons and the TV banner sit on black. This script is the
source: change a number here and run it again, never edit the outputs.

    python3 scripts/brand/make_brand_assets.py

Needs Pillow and Poppins Bold (Poppins-Bold.ttf in ~/Library/Fonts or
/Library/Fonts, or the file named by PLEBZ_WORDMARK_FONT). Writes, relative to
the repository root:
  assets/brand/plebz_mark.svg                 the mark, master
  assets/brand/plebz_logo_on_{black,white}.png   mark and wordmark, 2048 wide
  assets/plezy_adaptive_foreground.svg   the start screen (path kept for upstream)
  assets/plezy.png                       the sign-in screen (path kept)
  assets/plebz_wordmark.png              "Plebz" in white, for the start animation
  android/.../drawable/ic_launcher_{foreground,monochrome}.xml
  android/.../mipmap-*/ic_launcher.png   launchers before Android 8
  android/.../drawable-*/tv_banner.png   the Android TV banner
  macos/plezy.icon/Assets/plezy-cropped.svg   the Mac icon's layer
  windows/runner/resources/app_icon.ico
"""

from __future__ import annotations

import os
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
RES = ROOT / "android/app/src/main/res"

# --- Geometry, in mark units. y grows downwards. ----------------------------
W = 27.0  # the stroke weight
STEM_BOTTOM = 104.0  # centre line of the stem's round end
TIP = (90.0, 50.0)  # the triangle's point
OPEN_END = (32.0, 90.0)  # centre line of the open stroke's round end
CORNER = 11.0  # how far each corner's curve reaches along its two edges

# The gradient runs corner to corner across the centre line's box.
STOPS = [(0.0, "#7356F5"), (0.55, "#A866EE"), (1.0, "#EE8BD2")]

WHITE = "#FFFFFF"
BLACK = "#000000"
INK = "#16151D"  # the wordmark on white

# The wordmark beside the mark: the mark is this many times the height of
# "Plebz" (cap top to baseline), and stands this far from it, in that height.
MARK_TO_TEXT = 1.42
TEXT_GAP = 0.61


def _toward(a: tuple[float, float], b: tuple[float, float], d: float) -> tuple[float, float]:
    dx, dy = b[0] - a[0], b[1] - a[1]
    length = (dx * dx + dy * dy) ** 0.5
    return a[0] + dx / length * d, a[1] + dy / length * d


def segments() -> list[tuple]:
    """The centre line: ("M", p), ("L", p), ("Q", control, p)."""
    top = (0.0, 0.0)
    return [
        ("M", (0.0, STEM_BOTTOM)),
        ("L", (0.0, CORNER)),
        ("Q", top, _toward(top, TIP, CORNER)),
        ("L", _toward(TIP, top, CORNER)),
        ("Q", TIP, _toward(TIP, OPEN_END, CORNER)),
        ("L", OPEN_END),
    ]


def box() -> tuple[float, float, float, float]:
    """The stroke's outer box, sampled from the outline (x0, y0, x1, y1)."""
    pts = polyline()
    r = W / 2
    return (
        min(x for x, _ in pts) - r,
        min(y for _, y in pts) - r,
        max(x for x, _ in pts) + r,
        max(y for _, y in pts) + r,
    )


def gradient_box() -> tuple[float, float, float, float]:
    """Where the gradient starts and ends: the centre line's box, so the
    stroke reaches both end colours."""
    pts = polyline()
    return min(x for x, _ in pts), min(y for _, y in pts), max(x for x, _ in pts), max(y for _, y in pts)


def polyline(steps: int = 48) -> list[tuple[float, float]]:
    """The centre line as dense points, for drawing bitmaps."""
    pts: list[tuple[float, float]] = []
    for seg in segments():
        if seg[0] in ("M", "L"):
            pts.append(seg[1])
        else:
            (x0, y0), (cx, cy), (x1, y1) = pts[-1], seg[1], seg[2]
            for i in range(1, steps + 1):
                t = i / steps
                u = 1 - t
                pts.append((u * u * x0 + 2 * u * t * cx + t * t * x1, u * u * y0 + 2 * u * t * cy + t * t * y1))
    return pts


# --- SVG and VectorDrawable path data ---------------------------------------
def fmt(v: float) -> str:
    return f"{v:.2f}".rstrip("0").rstrip(".")


def path_data() -> str:
    out = []
    for seg in segments():
        if seg[0] == "Q":
            out.append(f"Q{fmt(seg[1][0])},{fmt(seg[1][1])} {fmt(seg[2][0])},{fmt(seg[2][1])}")
        else:
            out.append(f"{seg[0]}{fmt(seg[1][0])},{fmt(seg[1][1])}")
    return " ".join(out)


def svg(*, pad: float = 1.0, size=None, canvas=None, tile=None, transform=None) -> str:
    """The mark in its gradient. [canvas] (x, y, w, h) overrides the viewBox
    when the mark is placed with [transform] inside a larger frame; [tile]
    (x, y, width, radius) puts a black rounded square behind it."""
    x0, y0, x1, y1 = box()
    if canvas:
        vb = " ".join(fmt(v) for v in canvas)
    else:
        vb = f"{fmt(x0 - pad)} {fmt(y0 - pad)} {fmt(x1 - x0 + 2 * pad)} {fmt(y1 - y0 + 2 * pad)}"
    dims = f' width="{size[0]}" height="{size[1]}"' if size else ""
    gx0, gy0, gx1, gy1 = gradient_box()
    out = [f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="{vb}"{dims}>']
    out.append("<defs>")
    out.append(
        f'<linearGradient id="plebz" gradientUnits="userSpaceOnUse" x1="{fmt(gx0)}" y1="{fmt(gy0)}"'
        f' x2="{fmt(gx1)}" y2="{fmt(gy1)}">'
    )
    out += [f'<stop offset="{fmt(o)}" stop-color="{c}"/>' for o, c in STOPS]
    out.append("</linearGradient>")
    out.append("</defs>")
    if tile:
        tx, ty, tw, radius = tile
        out.append(
            f'<rect x="{fmt(tx)}" y="{fmt(ty)}" width="{fmt(tw)}" height="{fmt(tw)}" rx="{fmt(radius)}" fill="{BLACK}"/>'
        )
    out.append(f'<g transform="{transform}">' if transform else "<g>")
    out.append(
        f'<path d="{path_data()}" fill="none" stroke="url(#plebz)" stroke-width="{fmt(W)}"'
        ' stroke-linecap="round" stroke-linejoin="round"/>'
    )
    out.append("</g>")
    out.append("</svg>")
    return "\n".join(out) + "\n"


def vector_drawable(*, height_dp: float, gradient: bool) -> str:
    """An adaptive-icon layer: 108dp, the mark [height_dp] tall in the middle.
    The monochrome layer is the same stroke in white."""
    x0, y0, x1, y1 = box()
    scale = height_dp / (y1 - y0)
    tx = 54 - (x0 + x1) / 2 * scale
    ty = 54 - (y0 + y1) / 2 * scale
    lines = [
        '<?xml version="1.0" encoding="utf-8"?>',
        "<!-- Generated by scripts/brand/make_brand_assets.py; edit the script, not this file. -->",
        '<vector xmlns:android="http://schemas.android.com/apk/res/android"',
        '    xmlns:aapt="http://schemas.android.com/aapt"' if gradient else None,
        '    android:width="108dp"',
        '    android:height="108dp"',
        '    android:viewportWidth="108"',
        '    android:viewportHeight="108">',
        f'    <group android:scaleX="{fmt(scale)}" android:scaleY="{fmt(scale)}"'
        f' android:translateX="{fmt(tx)}" android:translateY="{fmt(ty)}">',
        "        <path",
        f'            android:pathData="{path_data()}"',
        None if gradient else '            android:strokeColor="#FFFFFFFF"',
        f'            android:strokeWidth="{fmt(W)}"',
        '            android:strokeLineCap="round"',
        '            android:strokeLineJoin="round"' + ("" if gradient else " />"),
    ]
    if gradient:
        gx0, gy0, gx1, gy1 = gradient_box()
        lines[-1] += ">"
        lines += [
            '            <aapt:attr name="android:strokeColor">',
            '                <gradient android:type="linear"',
            f'                    android:startX="{fmt(gx0)}" android:startY="{fmt(gy0)}"',
            f'                    android:endX="{fmt(gx1)}" android:endY="{fmt(gy1)}">',
        ]
        lines += [
            f'                    <item android:offset="{fmt(o)}" android:color="#FF{c[1:]}" />' for o, c in STOPS
        ]
        lines += ["                </gradient>", "            </aapt:attr>", "        </path>"]
    lines += ["    </group>", "</vector>"]
    return "\n".join(line for line in lines if line is not None) + "\n"


# --- Bitmaps ---------------------------------------------------------------
SS = 8  # supersampling


def _rgb(hex_colour: str) -> tuple[int, int, int]:
    return int(hex_colour[1:3], 16), int(hex_colour[3:5], 16), int(hex_colour[5:7], 16)


def _gradient_palette() -> list[int]:
    palette = []
    for i in range(256):
        t = i / 255
        for (o0, c0), (o1, c1) in zip(STOPS, STOPS[1:]):
            if o0 <= t <= o1:
                f = (t - o0) / (o1 - o0)
                a, b = _rgb(c0), _rgb(c1)
                palette += [round(a[k] + (b[k] - a[k]) * f) for k in range(3)]
                break
    return palette


def draw_mark(canvas: Image.Image, *, height: float, centre: tuple[float, float], colour: str | None = None) -> None:
    """Paint the mark [height] pixels tall around [centre]: in its gradient,
    or in [colour]."""
    x0, y0, x1, y1 = box()
    s = height / (y1 - y0)
    ox = centre[0] - (x0 + x1) / 2 * s
    oy = centre[1] - (y0 + y1) / 2 * s
    mask = Image.new("L", canvas.size, 0)
    d = ImageDraw.Draw(mask)
    pts = [(ox + x * s, oy + y * s) for x, y in polyline()]
    r = W * s / 2
    # Thick segments plus a disc at every point: round ends and round joins.
    for a, b in zip(pts, pts[1:]):
        d.line([a, b], fill=255, width=round(W * s))
    for cx, cy in pts:
        d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=255)

    if colour:
        fill = Image.new("RGBA", canvas.size, colour)
    else:
        # t along the corner-to-corner line, as a grey ramp, then coloured.
        # The stroke reaches past both ends of the line, where the end colours
        # hold: the ramp is padded with 256 rows of each.
        bx0, by0, bx1, by1 = gradient_box()
        gx0, gy0, gx1, gy1 = ox + bx0 * s, oy + by0 * s, ox + bx1 * s, oy + by1 * s
        dx, dy = gx1 - gx0, gy1 - gy0
        l2 = dx * dx + dy * dy
        padded = Image.new("L", (1, 768))
        padded.putdata([0] * 256 + list(range(256)) + [255] * 256)
        ramp = padded.transform(
            canvas.size,
            Image.Transform.AFFINE,
            (0, 0, 0, 255 * dx / l2, 255 * dy / l2, 256 - 255 * (gx0 * dx + gy0 * dy) / l2),
            resample=Image.Resampling.BILINEAR,
        )
        ramp.putpalette(_gradient_palette())
        fill = ramp.convert("RGBA")
    canvas.paste(fill, (0, 0), mask)


def _font_path() -> Path:
    named = os.environ.get("PLEBZ_WORDMARK_FONT")
    candidates = [Path(named)] if named else []
    candidates += [Path.home() / "Library/Fonts/Poppins-Bold.ttf", Path("/Library/Fonts/Poppins-Bold.ttf")]
    for path in candidates:
        if path.is_file():
            return path
    raise SystemExit("Poppins Bold not found: install Poppins-Bold.ttf or set PLEBZ_WORDMARK_FONT")


def icon(px: int, *, mark_height: float, tile_radius: float | None) -> Image.Image:
    """The mark on a black square, or on a black rounded tile on transparency."""
    size = px * SS
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0) if tile_radius is not None else BLACK)
    if tile_radius is not None:
        ImageDraw.Draw(img).rounded_rectangle([0, 0, size - 1, size - 1], radius=tile_radius * SS, fill=BLACK)
    draw_mark(img, height=mark_height * SS, centre=(size / 2, size / 2))
    return img.resize((px, px), Image.Resampling.LANCZOS)


def lockup(width: int, height: int, *, span: float, background, text: str) -> Image.Image:
    """Mark and "Plebz" side by side, [span] of the width, centred."""
    w_, h_ = width * SS, height * SS
    img = Image.new("RGBA", (w_, h_), background)
    font_path = _font_path()
    probe = ImageFont.truetype(str(font_path), 1000)
    l, t, r, b = probe.getbbox("Plebz")
    # Sizes per unit of text height (cap top to baseline).
    x0, y0, x1, y1 = box()
    mark_w = MARK_TO_TEXT * (x1 - x0) / (y1 - y0)
    text_w = (r - l) / (b - t)
    unit = span * w_ / (mark_w + TEXT_GAP + text_w)
    left = (w_ - unit * (mark_w + TEXT_GAP + text_w)) / 2
    draw_mark(img, height=MARK_TO_TEXT * unit, centre=(left + mark_w * unit / 2, h_ / 2))
    font = ImageFont.truetype(str(font_path), round(1000 * unit / (b - t)))
    l, t, r, b = font.getbbox("Plebz")
    tx = left + (mark_w + TEXT_GAP) * unit - l
    ty = h_ / 2 - (t + b) / 2
    ImageDraw.Draw(img).text((tx, ty), "Plebz", font=font, fill=text)
    return img.resize((width, height), Image.Resampling.LANCZOS)


def wordmark(height: int) -> Image.Image:
    """"Plebz" in white on transparency, cut to its ink: [height] pixels from
    cap top to baseline."""
    font = ImageFont.truetype(str(_font_path()), 1000)
    l, t, r, b = font.getbbox("Plebz")
    size = round(1000 * height / (b - t))
    font = ImageFont.truetype(str(_font_path()), size)
    l, t, r, b = font.getbbox("Plebz")
    img = Image.new("RGBA", (r - l + 2 * size, b - t + size), (255, 255, 255, 0))
    ImageDraw.Draw(img).text((size - l, size // 2 - t), "Plebz", font=font, fill=WHITE)
    return img.crop(img.getbbox())


def main() -> None:
    x0, y0, x1, y1 = box()
    brand = ROOT / "assets/brand"
    brand.mkdir(parents=True, exist_ok=True)
    (brand / "plebz_mark.svg").write_text(svg())
    lockup(2048, 640, span=0.84, background=BLACK, text=WHITE).convert("RGB").save(brand / "plebz_logo_on_black.png")
    lockup(2048, 640, span=0.84, background=WHITE, text=INK).convert("RGB").save(brand / "plebz_logo_on_white.png")

    # Start screen: the app icon (black tile, the mark) in the adaptive-icon
    # canvas it replaces, so the call sites keep their sizes.
    scale = 32 / (y1 - y0)
    tx, ty = 54 - (x0 + x1) / 2 * scale, 54 - (y0 + y1) / 2 * scale
    start = svg(
        canvas=(0, 0, 108, 108),
        tile=(27, 27, 54, 12),
        transform=f"translate({fmt(tx)} {fmt(ty)}) scale({fmt(scale)})",
    )
    (ROOT / "assets/plezy_adaptive_foreground.svg").write_text(start)

    # Adaptive icon: the launcher masks the 108dp layer to its middle 72dp.
    (RES / "drawable/ic_launcher_foreground.xml").write_text(vector_drawable(height_dp=44, gradient=True))
    (RES / "drawable/ic_launcher_monochrome.xml").write_text(vector_drawable(height_dp=44, gradient=False))

    # Legacy launcher bitmaps (before adaptive icons): a rounded black tile.
    for folder, px in {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}.items():
        icon(px, mark_height=px * 0.6, tile_radius=px * 0.22).save(RES / f"mipmap-{folder}/ic_launcher.png")

    # Android TV banner: mark and wordmark on black.
    for folder, (bw, bh) in {"xhdpi": (320, 180), "xxhdpi": (480, 270), "xxxhdpi": (640, 360)}.items():
        lockup(bw, bh, span=0.7, background=BLACK, text=WHITE).convert("RGB").save(
            RES / f"drawable-{folder}/tv_banner.png"
        )

    # The start animation's name, revealed beside the drawn mark.
    wordmark(256).save(ROOT / "assets/plebz_wordmark.png", optimize=True)

    # Sign-in screen logo.
    icon(512, mark_height=300, tile_radius=112).save(ROOT / "assets/plezy.png")

    # Mac icon layer: the mark alone, as tall as the layer it replaces.
    h = 281
    (ROOT / "macos/plezy.icon/Assets/plezy-cropped.svg").write_text(
        svg(size=(round(h * (x1 - x0 + 2) / (y1 - y0 + 2)), h))
    )

    # Windows icon.
    sizes = [16, 24, 32, 48, 64, 128, 256]
    icon(256, mark_height=156, tile_radius=56).save(
        ROOT / "windows/runner/resources/app_icon.ico", sizes=[(n, n) for n in sizes]
    )


if __name__ == "__main__":
    main()
