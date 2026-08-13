#!/usr/bin/env python3
r"""Aura wizard artwork for the Quick Office Windows installers.

Inno Setup wants two bitmaps, at sizes fixed by the wizard layout:

    wizard-large.bmp   164x314   the panel down the left of the welcome page
    wizard-small.bmp    55x58    the badge in the header of every other page

Both must be plain 24-bit BMP; Inno will not read a PNG. They are generated
here from the Aura tokens rather than drawn by hand so that a palette change
is one edit, and so the three apps can share one generator while each getting
its own accent.

    make-installer-branding.py <outdir> [accent-hex] [glyph]
    make-installer-branding.py packaging/branding "#2f5fe0" document
"""

import os
import sys

from PIL import Image, ImageDraw, ImageFont

BG = (15, 17, 21)          # #0f1115
BG2 = (20, 23, 28)         # #14171c
TEXT = (241, 243, 247)     # #f1f3f7
MUTED = (154, 164, 178)    # #9aa4b2
BRAND = (91, 134, 247)     # #5b86f7

LARGE = (164, 314)
SMALL = (55, 58)


def _font(size, bold=False):
    for p in ("/usr/share/fonts/truetype/dejavu/DejaVuSans%s.ttf"
              % ("-Bold" if bold else ""),
              "/usr/share/fonts/truetype/liberation/LiberationSans%s.ttf"
              % ("-Bold" if bold else "-Regular")):
        if os.path.isfile(p):
            try:
                return ImageFont.truetype(p, size)
            except OSError:
                pass
    return ImageFont.load_default()


def _mix(a, b, t):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(3))


def _glyph(d, box, accent, kind, w=2):
    """The same three line-art marks as the app icons, drawn small."""
    x0, y0, x1, y1 = box
    d.rounded_rectangle(box, radius=max(3, (x1 - x0) // 7), outline=accent, width=w)
    pad = (x1 - x0) // 5
    if kind == "document":
        for i in range(3):
            y = y0 + pad + i * ((y1 - y0 - 2 * pad) // 2.5)
            d.line([x0 + pad, y, x1 - pad - (i == 2) * pad, y], fill=accent, width=w)
    elif kind == "spreadsheet":
        for i in (1, 2):
            d.line([x0 + pad // 2, y0 + i * (y1 - y0) / 3,
                    x1 - pad // 2, y0 + i * (y1 - y0) / 3], fill=accent, width=w)
            d.line([x0 + i * (x1 - x0) / 3, y0 + pad // 2,
                    x0 + i * (x1 - x0) / 3, y1 - pad // 2], fill=accent, width=w)
    else:                                       # presentation
        base = y1 - pad
        for i, h in enumerate((0.45, 0.75, 0.6)):
            x = x0 + pad + i * ((x1 - x0 - 2 * pad) / 2.2)
            d.line([x, base, x, base - (y1 - y0) * h * 0.6], fill=accent, width=w + 1)


def large(path, accent, kind, title):
    img = Image.new("RGB", LARGE, BG)
    d = ImageDraw.Draw(img)
    for y in range(LARGE[1]):
        d.line([(0, y), (LARGE[0], y)], fill=_mix(BG2, BG, y / LARGE[1]))
    # the Aura beam, vertical here because the panel is tall
    for y in range(LARGE[1]):
        t = min(1.0, y / (LARGE[1] * 0.8))
        d.rectangle([0, y, 2, y + 1], fill=_mix(accent, BG, t))
    _glyph(d, (44, 78, 120, 154), accent, kind, w=3)
    # The panel is 164 px wide and "Quick Presentation" does not fit on one
    # line at a readable weight, so the product name is always stacked:
    # "Quick" over the noun. Shrinking the type to make it fit instead would
    # have made the widest name set the size for all three.
    head, tail = (title.split(" ", 1) + [""])[:2]
    f_head, f_tail = _font(14, bold=True), _font(15, bold=True)
    d.text((22, 180), head, font=f_head, fill=MUTED)
    d.text((22, 197), tail, font=f_tail, fill=TEXT)
    d.text((22, 222), "Quick Office", font=_font(10), fill=MUTED)
    d.text((22, 276), "quickopen.ai", font=_font(9), fill=MUTED)
    img.save(path, "BMP")


def small(path, accent, kind):
    img = Image.new("RGB", SMALL, BG)
    d = ImageDraw.Draw(img)
    _glyph(d, (10, 8, 45, 48), accent, kind, w=2)
    img.save(path, "BMP")


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else "."
    accent_hex = (sys.argv[2] if len(sys.argv) > 2 else "#5b86f7").lstrip("#")
    kind = sys.argv[3] if len(sys.argv) > 3 else "document"
    title = {"document": "Quick Document", "spreadsheet": "Quick Spreadsheet",
             "presentation": "Quick Presentation",
             "suite": "Quick Office"}.get(kind, "Quick Office")
    accent = tuple(int(accent_hex[i:i + 2], 16) for i in (0, 2, 4))
    os.makedirs(out, exist_ok=True)
    large(os.path.join(out, "wizard-large.bmp"), accent, kind, title)
    small(os.path.join(out, "wizard-small.bmp"), accent, kind)
    print("  %-28s %s / %s" % (out, "wizard-large.bmp", "wizard-small.bmp"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
