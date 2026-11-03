#!/usr/bin/env python3
"""Draw the symbols CupertinoIcons lacks, in its own stroke, as one font.

Plebz draws its glyphs from CupertinoIcons (Flutter's iOS-style set, MIT,
package cupertino_icons). A few things the app shows have no glyph there:
format badges, slashed variants, a server, a remote. This script draws them
on CupertinoIcons' own grid — 56 units across, the SVG box its glyphs were
cut from — and writes them as a font beside it. Slashed glyphs take their base
straight out of CupertinoIcons.ttf and cut Apple's slash through it.

    python3 scripts/brand/make_plebz_symbols.py

Needs fontTools and skia-pathops (pip install fonttools skia-pathops) and
CupertinoIcons.ttf in the pub cache (flutter pub get). Writes, relative to the
repository root:
  assets/fonts/PlebzSymbols.ttf        the font
  lib/widgets/plebz_symbols.g.dart     its code points, by name
Change a glyph here and run it again; never edit the outputs.
"""

from __future__ import annotations

import math
import re
from pathlib import Path

import pathops
from fontTools.fontBuilder import FontBuilder
from fontTools.pens.cu2quPen import Cu2QuPen
from fontTools.pens.transformPen import TransformPen
from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.ttLib import TTFont

ROOT = Path(__file__).resolve().parents[2]
PUB = Path.home() / ".pub-cache/hosted/pub.dev"
FLUTTER_ICONS = Path.home() / "development/flutter/packages/flutter/lib/src/cupertino/icons.dart"

# CupertinoIcons' metrics: 512 units per em, the 56-unit SVG box spanning
# ascender 448 to descender -64. Drawing happens in box units, y down.
UPM = 512
ASCENT = 448
DESCENT = -64
K = UPM / 56

STROKE = 3.8  # the set's regular weight (a ring is 4.0, a box edge 3.8)
LETTER = 3.4  # letters inside a badge, a touch lighter so they stay open
GAP = 2.4  # air either side of a slash
FIRST_CODE_POINT = 0xE000


def cupertino_font() -> TTFont:
    found = sorted(PUB.glob("cupertino_icons-*/assets/CupertinoIcons.ttf"))
    if not found:
        raise SystemExit("CupertinoIcons.ttf not in the pub cache: run flutter pub get")
    return TTFont(found[-1])


def cupertino_code_points() -> dict[str, int]:
    source = FLUTTER_ICONS.read_text()
    return {
        name: int(code, 16)
        for name, code in re.findall(r"static const IconData (\w+) =\s*IconData\(\s*0x([0-9a-fA-F]+)", source)
    }


CUPERTINO = cupertino_font()
CODES = cupertino_code_points()


# --- Paths, in box units ------------------------------------------------------


class Pen:
    """Builds a pathops path in box units (y down)."""

    def __init__(self) -> None:
        self.path = pathops.Path()

    def move(self, x, y):
        self.path.moveTo(x, y)
        return self

    def line(self, x, y):
        self.path.lineTo(x, y)
        return self

    def curve(self, x1, y1, x2, y2, x, y):
        self.path.cubicTo(x1, y1, x2, y2, x, y)
        return self

    def close(self):
        self.path.close()
        return self

    def arc(self, cx, cy, r, start, end):
        """Arc around (cx, cy) from angle [start] to [end], degrees, clockwise on
        screen (y down). Starts a new contour at the arc's start."""
        a0 = math.radians(start)
        a1 = math.radians(end)
        steps = max(1, math.ceil(abs(a1 - a0) / (math.pi / 2)))
        step = (a1 - a0) / steps
        h = 4 / 3 * math.tan(step / 4)
        self.path.moveTo(cx + r * math.cos(a0), cy + r * math.sin(a0))
        for i in range(steps):
            t0 = a0 + i * step
            t1 = t0 + step
            p0 = (cx + r * math.cos(t0), cy + r * math.sin(t0))
            p3 = (cx + r * math.cos(t1), cy + r * math.sin(t1))
            p1 = (p0[0] - h * r * math.sin(t0), p0[1] + h * r * math.cos(t0))
            p2 = (p3[0] + h * r * math.sin(t1), p3[1] - h * r * math.cos(t1))
            self.path.cubicTo(*p1, *p2, *p3)
        return self


def stroked(pen: Pen, width: float = STROKE) -> pathops.Path:
    path = pathops.Path(pen.path)
    path.stroke(width, pathops.LineCap.ROUND_CAP, pathops.LineJoin.ROUND_JOIN, 4)
    # Round caps and joins come out as conics, which the boolean ops refuse.
    path.convertConicsToQuads()
    return path


def filled(pen: Pen) -> pathops.Path:
    return pathops.Path(pen.path)


def union(*paths: pathops.Path) -> pathops.Path:
    return pathops.op(paths[0], union(*paths[1:]), pathops.PathOp.UNION) if len(paths) > 1 else simplify(paths[0])


def minus(a: pathops.Path, b: pathops.Path) -> pathops.Path:
    return pathops.op(a, b, pathops.PathOp.DIFFERENCE)


def simplify(path: pathops.Path) -> pathops.Path:
    return pathops.simplify(path, fix_winding=True)


def rounded_rect(x0, y0, x1, y1, r) -> Pen:
    """A rounded rectangle as one contour."""
    c = 0.5523 * r
    return (
        Pen()
        .move(x0 + r, y0)
        .line(x1 - r, y0)
        .curve(x1 - r + c, y0, x1, y0 + r - c, x1, y0 + r)
        .line(x1, y1 - r)
        .curve(x1, y1 - r + c, x1 - r + c, y1, x1 - r, y1)
        .line(x0 + r, y1)
        .curve(x0 + r - c, y1, x0, y1 - r + c, x0, y1 - r)
        .line(x0, y0 + r)
        .curve(x0, y0 + r - c, x0 + r - c, y0, x0 + r, y0)
        .close()
    )


def circle(cx, cy, r) -> Pen:
    c = 0.5523 * r
    return (
        Pen()
        .move(cx + r, cy)
        .curve(cx + r, cy + c, cx + c, cy + r, cx, cy + r)
        .curve(cx - c, cy + r, cx - r, cy + c, cx - r, cy)
        .curve(cx - r, cy - c, cx - c, cy - r, cx, cy - r)
        .curve(cx + c, cy - r, cx + r, cy - c, cx + r, cy)
        .close()
    )


def dot(cx, cy, r=2.4) -> pathops.Path:
    return filled(circle(cx, cy, r))


def cupertino(name: str) -> pathops.Path:
    """A CupertinoIcons glyph, back in box units."""
    glyph_name = CUPERTINO.getBestCmap()[CODES[name]]
    path = pathops.Path()
    # Font units (y up) to box units (y down).
    pen = TransformPen(path.getPen(), (1 / K, 0, 0, -1 / K, 0, ASCENT / K))
    CUPERTINO.getGlyphSet()[glyph_name].draw(pen)
    return simplify(path)


def slashed(base: pathops.Path) -> pathops.Path:
    """Apple's slash, top left to bottom right, cut through [base] with air on
    both sides."""
    line = Pen().move(9, 7.5).line(47, 48.5)
    return union(minus(base, stroked(line, STROKE + 2 * GAP)), stroked(line))


def badged(base: pathops.Path, badge: pathops.Path, cx: float, cy: float, r: float) -> pathops.Path:
    """[badge] in the corner of [base], the base cut back round it."""
    return union(minus(base, filled(circle(cx, cy, r))), badge)


# --- Letters, for the format badges -------------------------------------------
# Each takes its left edge and returns (path, width). Cap height 16, top at y.


def letter(ch: str, x: float, y: float) -> tuple[pathops.Path, float]:
    b = y + 16
    m = y + 8
    if ch == "H":
        w = 9.5
        p = Pen().move(x, y).line(x, b).move(x + w, y).line(x + w, b).move(x, m).line(x + w, m)
    elif ch == "D":
        w = 10.5
        p = Pen().move(x, y).line(x + w - 8, y).curve(x + w + 2.6, y, x + w + 2.6, b, x + w - 8, b).line(x, b).close()
        w += 0.6
    elif ch == "R":
        w = 10
        p = (
            Pen()
            .move(x, b)
            .line(x, y)
            .line(x + w - 4.6, y)
            .curve(x + w + 1.4, y, x + w + 1.4, m + 1, x + w - 4.6, m + 1)
            .line(x, m + 1)
            .move(x + w - 4.2, m + 1)
            .line(x + w, b)
        )
    elif ch == "Q":
        w = 12.5
        rx, ry = w / 2, 8
        cx, cy = x + rx, m
        kx, ky = 0.5523 * rx, 0.5523 * ry
        c = (
            Pen()
            .move(cx + rx, cy)
            .curve(cx + rx, cy + ky, cx + kx, cy + ry, cx, cy + ry)
            .curve(cx - kx, cy + ry, cx - rx, cy + ky, cx - rx, cy)
            .curve(cx - rx, cy - ky, cx - kx, cy - ry, cx, cy - ry)
            .curve(cx + kx, cy - ry, cx + rx, cy - ky, cx + rx, cy)
            .close()
        )
        tail = Pen().move(cx + 2.2, m + 4).line(x + w + 1.2, b + 1.2)
        return union(stroked(c, LETTER), stroked(tail, LETTER)), w + 1
    elif ch == "K":
        w = 10
        p = Pen().move(x, y).line(x, b).move(x + w, y).line(x + 0.6, m + 2).move(x + 3.8, m - 0.6).line(x + w, b)
    elif ch == "4":
        w = 11
        p = Pen().move(x + w - 3, b).line(x + w - 3, y).line(x, y + 11).line(x + w, y + 11)
    elif ch == "5":
        w = 10.5
        p = (
            Pen()
            .move(x + w - 0.5, y)
            .line(x + 1.2, y)
            .line(x + 0.6, m - 0.8)
            .curve(x + 2.4, m - 2.4, x + w + 0.4, m - 2.6, x + w + 0.4, m + 2.6)
            .curve(x + w + 0.4, b + 1.4, x + 2, b + 1.2, x, b - 2.2)
        )
    elif ch == "9":
        w = 10.5
        r = w / 2
        ring = circle(x + r, y + r, r)
        stem = Pen().move(x + w, y + r).line(x + w, m + 2).curve(x + w, b + 0.6, x + 3, b + 1, x + 0.4, b - 2.4)
        return union(stroked(ring, LETTER), stroked(stem, LETTER)), w
    elif ch == "+":
        w = 9
        p = Pen().move(x, m).line(x + w, m).move(x + w / 2, m - 4.5).line(x + w / 2, m + 4.5)
    else:
        raise ValueError(ch)
    return stroked(p, LETTER), w


def word(text: str, cx: float, y: float, spacing: float = 3.6) -> pathops.Path:
    widths = [letter(ch, 0, 0)[1] for ch in text]
    total = sum(widths) + spacing * (len(text) - 1)
    x = cx - total / 2
    parts = []
    for ch, w in zip(text, widths):
        parts.append(letter(ch, x, y)[0])
        x += w + spacing
    return union(*parts)


def badge(text: str, square: bool = False) -> pathops.Path:
    """Letters in a rounded frame: Apple's way of naming a format."""
    frame = rounded_rect(10, 10, 46, 46, 8) if square else rounded_rect(3.5, 11, 52.5, 45, 8)
    return union(stroked(frame), word(text, 28, 20))


# --- The glyphs ---------------------------------------------------------------


def server() -> pathops.Path:
    top = rounded_rect(5, 7.5, 51, 25.5, 5.5)
    bottom = rounded_rect(5, 30.5, 51, 48.5, 5.5)
    lamps = [dot(13.5, 16.5), dot(13.5, 39.5)]
    slots = Pen().move(30, 16.5).line(42.5, 16.5).move(30, 39.5).line(42.5, 39.5)
    return union(stroked(top), stroked(bottom), stroked(slots), *lamps)


def history() -> pathops.Path:
    """clock.arrow.circlepath: an anticlockwise circle with hands."""
    cx, cy, r = 29, 28, 20.5
    ring = Pen().arc(cx, cy, r, 160, 160 + 330)
    # The arrow head at the ring's open end, pointing back along it.
    end = math.radians(160)
    ex, ey = cx + r * math.cos(end), cy + r * math.sin(end)
    head = Pen().move(ex - 6.2, ey - 5.4).line(ex, ey + 0.6).line(ex + 6.6, ey - 4.6)
    hands = Pen().move(cx, cy - 11).line(cx, cy).line(cx + 7.5, cy + 5)
    return union(stroked(ring), stroked(head), stroked(hands))


def remote() -> pathops.Path:
    body = rounded_rect(17, 3.5, 39, 52.5, 9)
    pad = circle(28, 15.5, 6)
    return union(stroked(body), stroked(pad, 3.2), dot(28, 30.5, 2.3), dot(28, 38.5, 2.3), dot(28, 46.5 - 1.5, 2.3))


def hard_drive() -> pathops.Path:
    body = rounded_rect(4, 15, 52, 41, 7)
    line = Pen().move(4.5, 31).line(51.5, 31)
    return union(stroked(body), stroked(line), dot(43.5, 36, 2.1))


def usb() -> pathops.Path:
    plug = rounded_rect(18, 20, 38, 40, 4.5)
    head = Pen().move(21.5, 20).line(21.5, 8).line(34.5, 8).line(34.5, 20)
    pins = [filled(rounded_rect(24.2, 11.5, 26.6, 15.5, 0.8)), filled(rounded_rect(29.4, 11.5, 31.8, 15.5, 0.8))]
    cable = Pen().move(28, 40).line(28, 52)
    return union(stroked(plug), stroked(head), stroked(cable), *pins)


def door() -> pathops.Path:
    frame = Pen().move(14, 49).line(14, 10).curve(14, 7.5, 15.5, 6, 18, 6).line(38, 6).curve(40.5, 6, 42, 7.5, 42, 10).line(42, 49)
    floor = Pen().move(8, 49.5).line(48, 49.5)
    return union(stroked(frame), stroked(floor), dot(35.5, 29, 2.6))


def key() -> pathops.Path:
    head = circle(17, 28, 9.5)
    shaft = Pen().move(26.5, 28).line(51, 28)
    teeth = Pen().move(44, 28).line(44, 36.5).move(50.5, 28).line(50.5, 34)
    return union(stroked(head), stroked(shaft), stroked(teeth), dot(13.5, 28, 2.4))


def space() -> pathops.Path:
    return stroked(Pen().move(7, 26).line(7, 36).line(49, 36).line(49, 26))


def link_plus() -> pathops.Path:
    base = cupertino("link")
    small = pathops.Path()
    # The link drawn a fifth smaller toward the top left, as Apple's badges do.
    base.draw(TransformPen(small.getPen(), (0.8, 0, 0, 0.8, 1, 1)))
    plus = Pen().move(37, 44).line(51, 44).move(44, 37).line(44, 51)
    return badged(simplify(small), stroked(plus), 44, 44, 11)


def cloud_check() -> pathops.Path:
    tick = Pen().move(20, 32).line(25.5, 37.5).line(36, 26)
    return union(cupertino("cloud"), stroked(tick))


def arrows_exclaim() -> pathops.Path:
    mark = Pen().move(28, 20).line(28, 30)
    return union(cupertino("arrow_2_circlepath"), stroked(mark, 4.2), dot(28, 36.2, 2.5))


def skip_five(base: str) -> pathops.Path:
    return union(cupertino(base), letter("5", 23, 22)[0])


def dashed_square() -> pathops.Path:
    """A frame of dashes: corners and the middle of each side."""
    x0, y0, x1, y1, r = 6.5, 6.5, 49.5, 49.5, 8
    c = 0.5523 * r
    corners = (
        Pen()
        .move(x0, y0 + r + 5)
        .line(x0, y0 + r)
        .curve(x0, y0 + r - c, x0 + r - c, y0, x0 + r, y0)
        .line(x0 + r + 5, y0)
        .move(x1 - r - 5, y0)
        .line(x1 - r, y0)
        .curve(x1 - r + c, y0, x1, y0 + r - c, x1, y0 + r)
        .line(x1, y0 + r + 5)
        .move(x1, y1 - r - 5)
        .line(x1, y1 - r)
        .curve(x1, y1 - r + c, x1 - r + c, y1, x1 - r, y1)
        .line(x1 - r - 5, y1)
        .move(x0 + r + 5, y1)
        .line(x0 + r, y1)
        .curve(x0 + r - c, y1, x0, y1 - r + c, x0, y1 - r)
        .line(x0, y1 - r - 5)
    )
    m = 28
    sides = Pen().move(m - 3, y0).line(m + 3, y0).move(m - 3, y1).line(m + 3, y1)
    sides.move(x0, m - 3).line(x0, m + 3).move(x1, m - 3).line(x1, m + 3)
    return union(stroked(corners), stroked(sides))


# Name → glyph. The names are the Plebz ones the Dart side asks for.
GLYPHS = {
    "server_rack": server,
    "clock_arrow_circlepath": history,
    "tv_remote": remote,
    "externaldrive": hard_drive,
    "cable_connector": usb,
    "door_left": door,
    "key": key,
    "space": space,
    "link_badge_plus": link_plus,
    "checkmark_cloud": cloud_check,
    "exclamationmark_arrow_circlepath": arrows_exclaim,
    "gobackward_5": lambda: skip_five("gobackward"),
    "goforward_5": lambda: skip_five("goforward"),
    "square_dashed": dashed_square,
    "badge_hdr": lambda: badge("HDR"),
    "badge_hdr_slash": lambda: slashed(badge("HDR")),
    "badge_hq": lambda: badge("HQ"),
    "badge_4k": lambda: badge("4K"),
    "badge_5": lambda: badge("5", square=True),
    "badge_9plus": lambda: badge("9+", square=True),
    "arrow_2_circlepath_slash": lambda: slashed(cupertino("arrow_2_circlepath")),
    "link_slash": lambda: slashed(cupertino("link")),
    "cloud_slash": lambda: slashed(cupertino("cloud")),
    "search_slash": lambda: slashed(cupertino("search")),
    "line_horizontal_3_decrease_slash": lambda: slashed(cupertino("line_horizontal_3_decrease")),
    "bookmark_slash": lambda: slashed(cupertino("bookmark")),
    "timer_slash": lambda: slashed(cupertino("timer")),
    "captions_bubble_slash": lambda: slashed(cupertino("captions_bubble")),
    "tag_slash": lambda: slashed(cupertino("tag")),
    "photo_slash": lambda: slashed(cupertino("photo")),
}


# --- Output -------------------------------------------------------------------


def build() -> dict[str, int]:
    names = list(GLYPHS)
    codes = {name: FIRST_CODE_POINT + i for i, name in enumerate(names)}
    glyph_order = [".notdef", *names]
    fb = FontBuilder(UPM, isTTF=True)
    fb.setupGlyphOrder(glyph_order)
    fb.setupCharacterMap({code: name for name, code in codes.items()})
    glyphs = {".notdef": TTGlyphPen(None).glyph()}
    metrics = {".notdef": (UPM, 0)}
    for name in names:
        path = simplify(GLYPHS[name]())
        tt = TTGlyphPen(None)
        # Box units (y down) to font units (y up), cubics to quadratics.
        path.draw(TransformPen(Cu2QuPen(tt, 0.5, reverse_direction=True), (K, 0, 0, -K, 0, ASCENT)))
        glyph = tt.glyph()
        glyph.recalcBounds(None)
        # As CupertinoIcons: no side bearings, the advance is the ink's width.
        x_min = getattr(glyph, "xMin", 0)
        x_max = getattr(glyph, "xMax", UPM)
        if x_min:
            glyph.coordinates.translate((-x_min, 0))
            glyph.recalcBounds(None)
        glyphs[name] = glyph
        metrics[name] = (x_max - x_min, 0)
    fb.setupGlyf(glyphs)
    fb.setupHorizontalMetrics(metrics)
    fb.setupHorizontalHeader(ascent=ASCENT, descent=DESCENT)
    fb.setupNameTable(
        {
            "familyName": "PlebzSymbols",
            "styleName": "Regular",
            "copyright": "Drawn for Plebz on CupertinoIcons (MIT, the Flutter authors; Framework7 Icons, Vladimir Kharlampidi)",
        }
    )
    fb.setupOS2(sTypoAscender=ASCENT, sTypoDescender=DESCENT, usWinAscent=ASCENT, usWinDescent=-DESCENT)
    fb.setupPost()
    out = ROOT / "assets/fonts/PlebzSymbols.ttf"
    fb.save(out)
    return codes


def write_dart(codes: dict[str, int]) -> None:
    lines = [
        "// Generated by scripts/brand/make_plebz_symbols.py — do not edit.",
        "",
        "import 'package:flutter/widgets.dart';",
        "",
        "/// The glyphs CupertinoIcons lacks, drawn in its stroke (PlebzSymbols.ttf).",
        "abstract final class PlebzSymbols {",
        "  static const String family = 'PlebzSymbols';",
        "",
    ]
    for name, code in codes.items():
        lines.append(f"  static const IconData {name} = IconData(0x{code:x}, fontFamily: family);")
    lines.append("}")
    (ROOT / "lib/widgets/plebz_symbols.g.dart").write_text("\n".join(lines) + "\n")


if __name__ == "__main__":
    write_dart(build())
