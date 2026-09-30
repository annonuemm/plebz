#!/usr/bin/env python3
"""Draw every Plebz logo file from one geometry.

The mark is a lowercase "p" whose bowl holds a play triangle; the wordmark
"plebz" is built from the same strokes (one weight, round ends). This script is
the source: change a number here and run it again, never edit the outputs.

    python3 scripts/brand/make_brand_assets.py

Needs Pillow for the bitmaps. Writes, relative to the repository root:
  assets/brand/plebz_mark.svg, assets/brand/plebz_wordmark.svg   masters
  assets/plezy_adaptive_foreground.svg   the start screen (path kept for upstream)
  assets/plezy.png                       the sign-in screen (path kept)
  android/.../drawable/ic_launcher_{foreground,monochrome}.xml
  android/.../mipmap-*/ic_launcher.png   launchers before Android 8
  android/.../drawable-*/tv_banner.png   the Android TV banner
  macos/plezy.icon/Assets/plezy-cropped.svg   the Mac icon's layer
  windows/runner/resources/app_icon.ico
"""

from __future__ import annotations

import math
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
RES = ROOT / "android/app/src/main/res"

# --- Geometry, in glyph units. Baseline y=0, up is negative. ---------------
W = 8.0  # the one stroke weight
RM = 15.0  # centre-line radius of every bowl (outer 19, inner 11)
XTOP = -34.0  # centre line of an x-height top cap (outer -38)
ASC = -54.0  # centre line of an ascender cap (outer -58)
BASE = -4.0  # centre line of a baseline cap (outer 0)
DESC = 13.0  # centre line of the descender cap (outer 17)
BOWL_Y = -19.0  # centre of every bowl
GAP = 9.0  # space between letters, outer edge to outer edge
E_OPEN = 40.0  # degrees of the "e"'s opening, below its bar

WHITE = "#FFFFFF"
BLACK = "#000000"


def triangle(cx: float, cy: float) -> list[tuple[float, float]]:
    """The play triangle in a bowl centred at (cx, cy), nudged right so it
    sits optically in the middle."""
    return [(cx - 3.5, cy - 6.0), (cx - 3.5, cy + 6.0), (cx + 6.5, cy)]


def glyphs() -> tuple[list[tuple], tuple[float, float, float, float]]:
    """The wordmark as primitives, and its bounding box (x0, y0, x1, y1)."""
    shapes: list[tuple] = []
    x = 0.0
    # p: a bowl, the stem down its left side, the play inside.
    cx = x + W / 2 + RM
    shapes += [("ring", cx, BOWL_Y), ("line", [(x + W / 2, XTOP), (x + W / 2, DESC)]), ("tri", triangle(cx, BOWL_Y))]
    x += 2 * (RM + W / 2) + GAP
    # l
    shapes.append(("line", [(x + W / 2, ASC), (x + W / 2, BASE)]))
    x += W + GAP
    # e: bar through the middle, bowl open below the bar on the right.
    cx = x + W / 2 + RM
    shapes += [("line", [(cx - RM, BOWL_Y), (cx + RM, BOWL_Y)]), ("e-arc", cx, BOWL_Y)]
    x += 2 * (RM + W / 2) + GAP
    # b: the stem up the left side to the ascender, bowl at x-height.
    cx = x + W / 2 + RM
    shapes += [("ring", cx, BOWL_Y), ("line", [(x + W / 2, ASC), (x + W / 2, BASE)])]
    x += 2 * (RM + W / 2) + GAP
    # z: as wide as a bowl.
    x0, x1 = x + W / 2, x + W / 2 + 2 * RM
    shapes.append(("line", [(x0, XTOP), (x1, XTOP), (x0, BASE), (x1, BASE)]))
    x += 2 * (RM + W / 2)
    return shapes, (0.0, ASC - W / 2, x, DESC + W / 2)


def mark() -> tuple[list[tuple], tuple[float, float, float, float]]:
    """The "p" alone: the first three primitives of the wordmark."""
    shapes, _ = glyphs()
    return shapes[:3], (0.0, XTOP - W / 2, 2 * (RM + W / 2), DESC + W / 2)


def e_arc_end(cx: float, cy: float) -> tuple[float, float]:
    a = math.radians(E_OPEN)
    return cx + RM * math.cos(a), cy + RM * math.sin(a)


# --- SVG and VectorDrawable path data ---------------------------------------
def fmt(v: float) -> str:
    return f"{v:.2f}".rstrip("0").rstrip(".")


def circle_path(cx: float, cy: float, r: float) -> str:
    return (
        f"M{fmt(cx - r)},{fmt(cy)}a{fmt(r)},{fmt(r)} 0 1,0 {fmt(2 * r)},0"
        f"a{fmt(r)},{fmt(r)} 0 1,0 {fmt(-2 * r)},0"
    )


def stroke_paths(shapes: list[tuple]) -> tuple[list[str], list[str]]:
    """(stroked centre lines, filled triangles) as path data."""
    strokes, fills = [], []
    for s in shapes:
        if s[0] == "ring":
            strokes.append(circle_path(s[1], s[2], RM))
        elif s[0] == "line":
            pts = s[1]
            strokes.append("M" + "L".join(f"{fmt(px)},{fmt(py)}" for px, py in pts))
        elif s[0] == "e-arc":
            cx, cy = s[1], s[2]
            ex, ey = e_arc_end(cx, cy)
            strokes.append(f"M{fmt(cx + RM)},{fmt(cy)}A{fmt(RM)},{fmt(RM)} 0 1,0 {fmt(ex)},{fmt(ey)}")
        elif s[0] == "tri":
            fills.append("M" + "L".join(f"{fmt(px)},{fmt(py)}" for px, py in s[1]) + "Z")
    return strokes, fills


def svg(shapes, box, *, color=WHITE, pad=0.0, size=None, canvas=None, tile=None, transform=None) -> str:
    """[box] is the glyph's box; [canvas] (x, y, w, h) overrides the viewBox
    when the glyph is placed with [transform] inside a larger frame."""
    x0, y0, x1, y1 = box
    if canvas:
        vb = " ".join(fmt(v) for v in canvas)
    else:
        vb = f"{fmt(x0 - pad)} {fmt(y0 - pad)} {fmt(x1 - x0 + 2 * pad)} {fmt(y1 - y0 + 2 * pad)}"
    strokes, fills = stroke_paths(shapes)
    dims = f' width="{size[0]}" height="{size[1]}"' if size else ""
    out = [f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="{vb}"{dims}>']
    if tile:
        tx, ty, tw, radius = tile
        out.append(
            f'<rect x="{fmt(tx)}" y="{fmt(ty)}" width="{fmt(tw)}" height="{fmt(tw)}" rx="{fmt(radius)}" fill="{BLACK}"/>'
        )
    out.append(f'<g transform="{transform}">' if transform else "<g>")
    out.append(
        f'<g fill="none" stroke="{color}" stroke-width="{fmt(W)}" stroke-linecap="round" stroke-linejoin="round">'
    )
    out += [f'<path d="{d}"/>' for d in strokes]
    out.append("</g>")
    out += [f'<path d="{d}" fill="{color}" stroke="{color}" stroke-width="2" stroke-linejoin="round"/>' for d in fills]
    out.append("</g>")
    out.append("</svg>")
    return "\n".join(out) + "\n"


def vector_drawable(shapes, box, *, scale: float) -> str:
    """An adaptive-icon layer: 108dp, the mark centred in the 66dp safe zone."""
    x0, y0, x1, y1 = box
    tx = 54 - (x0 + x1) / 2 * scale
    ty = 54 - (y0 + y1) / 2 * scale
    strokes, fills = stroke_paths(shapes)
    lines = [
        '<?xml version="1.0" encoding="utf-8"?>',
        "<!-- Generated by scripts/brand/make_brand_assets.py; edit the script, not this file. -->",
        '<vector xmlns:android="http://schemas.android.com/apk/res/android"',
        '    android:width="108dp"',
        '    android:height="108dp"',
        '    android:viewportWidth="108"',
        '    android:viewportHeight="108">',
        f'    <group android:scaleX="{fmt(scale)}" android:scaleY="{fmt(scale)}"'
        f' android:translateX="{fmt(tx)}" android:translateY="{fmt(ty)}">',
    ]
    for d in strokes:
        lines += [
            "        <path",
            f'            android:pathData="{d}"',
            '            android:strokeColor="#FFFFFFFF"',
            f'            android:strokeWidth="{fmt(W)}"',
            '            android:strokeLineCap="round"',
            '            android:strokeLineJoin="round" />',
        ]
    for d in fills:
        lines += [
            "        <path",
            f'            android:pathData="{d}"',
            '            android:fillColor="#FFFFFFFF"',
            '            android:strokeColor="#FFFFFFFF"',
            '            android:strokeWidth="2"',
            '            android:strokeLineJoin="round" />',
        ]
    lines += ["    </group>", "</vector>"]
    return "\n".join(lines) + "\n"


# --- Bitmaps ---------------------------------------------------------------
SS = 8  # supersampling


def render(shapes, box, *, width: int, height: int, glyph_height: float, tile_radius: float | None = None,
           background: str | None = BLACK) -> Image.Image:
    """Draw [shapes] centred, [glyph_height] pixels tall, on a black canvas or
    a black rounded tile on transparency."""
    W_, H_ = width * SS, height * SS
    img = Image.new("RGBA", (W_, H_), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    if tile_radius is not None:
        d.rounded_rectangle([0, 0, W_ - 1, H_ - 1], radius=tile_radius * SS, fill=BLACK)
    elif background:
        d.rectangle([0, 0, W_, H_], fill=background)
    x0, y0, x1, y1 = box
    s = glyph_height / (y1 - y0) * SS
    ox = W_ / 2 - (x0 + x1) / 2 * s
    oy = H_ / 2 - (y0 + y1) / 2 * s

    def p(x: float, y: float) -> tuple[float, float]:
        return ox + x * s, oy + y * s

    w = W * s
    r = w / 2

    def cap(x: float, y: float) -> None:
        cx, cy = p(x, y)
        d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=WHITE)

    for sh in shapes:
        if sh[0] == "ring":
            cx, cy = p(sh[1], sh[2])
            ro = RM * s + r
            d.ellipse([cx - ro, cy - ro, cx + ro, cy + ro], outline=WHITE, width=round(w))
        elif sh[0] == "line":
            pts = [p(*pt) for pt in sh[1]]
            d.line(pts, fill=WHITE, width=round(w), joint="curve")
            cap(*sh[1][0])
            cap(*sh[1][-1])
        elif sh[0] == "e-arc":
            cx, cy = p(sh[1], sh[2])
            ro = RM * s + r
            d.arc([cx - ro, cy - ro, cx + ro, cy + ro], start=E_OPEN, end=360, fill=WHITE, width=round(w))
            cap(*e_arc_end(sh[1], sh[2]))
        elif sh[0] == "tri":
            # Rounded corners the way the SVG's round-joined 2-unit stroke
            # draws them: each edge as a thick line, a disc on every corner.
            pts = [p(*pt) for pt in sh[1]]
            d.polygon(pts, fill=WHITE)
            for a, b in zip(pts, pts[1:] + pts[:1]):
                d.line([a, b], fill=WHITE, width=round(2 * s))
            for cx, cy in pts:
                d.ellipse([cx - s, cy - s, cx + s, cy + s], fill=WHITE)
    return img.resize((width, height), Image.LANCZOS)


def main() -> None:
    m_shapes, m_box = mark()
    w_shapes, w_box = glyphs()

    brand = ROOT / "assets/brand"
    brand.mkdir(parents=True, exist_ok=True)
    (brand / "plebz_mark.svg").write_text(svg(m_shapes, m_box, pad=1))
    (brand / "plebz_wordmark.svg").write_text(svg(w_shapes, w_box, pad=1))

    # Start screen: the app icon (black tile, white p) in the adaptive-icon
    # canvas it replaces, so the call sites keep their sizes.
    mx0, my0, mx1, my1 = m_box
    scale = 0.6
    tx, ty = 54 - (mx0 + mx1) / 2 * scale, 54 - (my0 + my1) / 2 * scale
    start = svg(
        m_shapes,
        m_box,
        canvas=(0, 0, 108, 108),
        tile=(27, 27, 54, 12),
        transform=f"translate({fmt(tx)} {fmt(ty)}) scale({fmt(scale)})",
    )
    (ROOT / "assets/plezy_adaptive_foreground.svg").write_text(start)

    fg = vector_drawable(m_shapes, m_box, scale=0.85)
    (RES / "drawable/ic_launcher_foreground.xml").write_text(fg)
    (RES / "drawable/ic_launcher_monochrome.xml").write_text(fg)

    # Legacy launcher bitmaps (before adaptive icons): a rounded black tile.
    for folder, px in {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}.items():
        render(m_shapes, m_box, width=px, height=px, glyph_height=px * 0.58, tile_radius=px * 0.22).save(
            RES / f"mipmap-{folder}/ic_launcher.png"
        )

    # Android TV banner: the wordmark on black.
    for folder, (bw, bh) in {"xhdpi": (320, 180), "xxhdpi": (480, 270), "xxxhdpi": (640, 360)}.items():
        render(w_shapes, w_box, width=bw, height=bh, glyph_height=bh * 0.42).convert("RGB").save(
            RES / f"drawable-{folder}/tv_banner.png"
        )

    # Sign-in screen logo.
    render(m_shapes, m_box, width=512, height=512, glyph_height=300, tile_radius=112).save(ROOT / "assets/plezy.png")

    # Mac icon layer: the white p alone, sized like the layer it replaces.
    (ROOT / "macos/plezy.icon/Assets/plezy-cropped.svg").write_text(
        svg(m_shapes, m_box, pad=1, size=(round(38 * 5.1), round(55 * 5.1)))
    )

    # Windows icon.
    sizes = [16, 24, 32, 48, 64, 128, 256]
    big = render(m_shapes, m_box, width=256, height=256, glyph_height=150, tile_radius=56)
    big.save(ROOT / "windows/runner/resources/app_icon.ico", sizes=[(n, n) for n in sizes])


if __name__ == "__main__":
    main()
