#!/usr/bin/env python3
r"""Generate the Quick Office branding set consumed by `--with-branding`.

LibreOffice's build takes a directory and looks for four things in it:

    intro.png      the splash screen
    about.svg      the logo in Help > About
    logo.svg       the application logo
    progress.conf  where the progress bar sits on the splash, and its colours

Anything missing falls back to the upstream (LibreOffice-branded) asset, which
for us would be a trademark violation as well as ugly — so all four are
generated here, from the Aura tokens, with nothing borrowed from upstream.

Everything is drawn from scratch: a deep-space field, the Aura accent beam, a
line-art page/grid/deck mark and the wordmark. No LibreOffice or Microsoft
asset is used, referenced or traced (AIQuick product requirement #11).

    make-branding.py [outdir]        default: the directory holding this file
"""

import os
import sys

from PIL import Image, ImageDraw, ImageFont

# Aura tokens (branding/aura-design-system/aura-tokens.json v1.0.0)
BG = (15, 17, 21)               # #0f1115  deep-space canvas
BG2 = (20, 23, 28)              # #14171c
TEXT = (241, 243, 247)          # #f1f3f7
MUTED = (154, 164, 178)         # #9aa4b2
ACCENT = (91, 134, 247)         # #5b86f7  Aura brand accent (the suite)

# per-app accents, from the fleet palette in quickopen/gen_icons.py
APP_ACCENTS = {
    "quick-document": (47, 95, 224),        # #2f5fe0
    "quick-spreadsheet": (23, 145, 75),     # #17914b
    "quick-presentation": (194, 65, 12),    # #c2410c
}

W, H = 640, 400                 # splash size; progress.conf is written to match


def _font(size, bold=False):
    """A real UI face if the box has one, else PIL's bitmap default."""
    for path in ("/usr/share/fonts/truetype/dejavu/DejaVuSans%s.ttf"
                 % ("-Bold" if bold else ""),
                 "/usr/share/fonts/truetype/liberation/LiberationSans%s.ttf"
                 % ("-Bold" if bold else "-Regular")):
        if os.path.isfile(path):
            try:
                return ImageFont.truetype(path, size)
            except OSError:
                pass
    return ImageFont.load_default()


def _mix(a, b, t):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(3))


def draw_intro(path):
    """The splash: deep-space field, accent beam, wordmark, three app marks."""
    img = Image.new("RGB", (W, H), BG)
    d = ImageDraw.Draw(img)

    # a soft vertical lift so the panel does not read as flat black
    for y in range(H):
        d.line([(0, y), (W, y)], fill=_mix(BG2, BG, y / H))

    # the Aura signature beam, fading out to the right
    beam_y = 150
    for x in range(0, W, 2):
        t = min(1.0, x / (W * 0.8))
        d.rectangle([x, beam_y, x + 2, beam_y + 2], fill=_mix(ACCENT, BG, t))

    d.text((48, 86), "Quick Office", font=_font(40, bold=True), fill=TEXT)
    d.text((50, 168), "Documents · Spreadsheets · Presentations",
           font=_font(15), fill=MUTED)

    # three line-art marks, one per app, in their own accents
    x0, y0, s = 50, 214, 52
    for i, (slug, col) in enumerate(APP_ACCENTS.items()):
        x = x0 + i * (s + 26)
        d.rounded_rectangle([x, y0, x + s, y0 + s], radius=9, outline=col, width=2)
        if slug == "quick-document":                 # text lines on a page
            for j in range(3):
                d.line([x + 13, y0 + 17 + j * 10, x + s - 13 - (j == 2) * 12,
                        y0 + 17 + j * 10], fill=col, width=2)
        elif slug == "quick-spreadsheet":            # a grid
            for j in range(1, 3):
                d.line([x + 10, y0 + 10 + j * 11, x + s - 10, y0 + 10 + j * 11],
                       fill=col, width=2)
                d.line([x + 10 + j * 11, y0 + 10, x + 10 + j * 11, y0 + s - 10],
                       fill=col, width=2)
        else:                                        # a slide with a bar chart
            d.line([x + 13, y0 + 36, x + 13, y0 + 24], fill=col, width=3)
            d.line([x + 25, y0 + 36, x + 25, y0 + 17], fill=col, width=3)
            d.line([x + 37, y0 + 36, x + 37, y0 + 27], fill=col, width=3)

    d.text((50, 330), "quickopen.ai", font=_font(13), fill=MUTED)
    # the attribution the trademark policy asks for, on the very first screen
    d.text((50, 352), "Based on LibreOffice. Not affiliated with "
                      "The Document Foundation.", font=_font(11), fill=MUTED)

    img.save(path)
    return path


LOGO_SVG = """<?xml version="1.0" encoding="UTF-8"?>
<!-- Quick Office application logo. Original Aura line-art: a page, a grid and
     a slide sharing one accent. Nothing here is derived from any third-party
     mark. Apache-2.0, (c) 2026 QuickOpen. -->
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512" width="512"
     height="512" fill="none">
  <rect x="96" y="64" width="240" height="312" rx="18"
        stroke="#5b86f7" stroke-width="14"/>
  <path d="M148 148h136M148 208h136M148 268h88" stroke="#5b86f7"
        stroke-width="14" stroke-linecap="round"/>
  <rect x="176" y="176" width="240" height="272" rx="18" fill="#0f1115"
        stroke="#2f5fe0" stroke-width="14"/>
  <path d="M176 248h240M176 320h240M176 392h240M248 176v272M320 176v272"
        stroke="#2f5fe0" stroke-width="10" stroke-linecap="round"/>
</svg>
"""

ABOUT_SVG = """<?xml version="1.0" encoding="UTF-8"?>
<!-- Help > About logo. Wordmark + accent beam, Aura tokens only.
     Apache-2.0, (c) 2026 QuickOpen. -->
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 440 120" width="440"
     height="120" fill="none">
  <defs>
    <linearGradient id="beam" x1="0" y1="0" x2="1" y2="0">
      <stop offset="0" stop-color="#5b86f7"/>
      <stop offset="0.85" stop-color="#5b86f7" stop-opacity="0"/>
    </linearGradient>
  </defs>
  <rect x="18" y="26" width="52" height="64" rx="8" stroke="#5b86f7"
        stroke-width="5"/>
  <path d="M32 46h24M32 60h24M32 74h14" stroke="#5b86f7" stroke-width="5"
        stroke-linecap="round"/>
  <text x="92" y="66" font-family="DejaVu Sans, Segoe UI, sans-serif"
        font-size="34" font-weight="700" fill="#f1f3f7">Quick Office</text>
  <rect x="92" y="80" width="330" height="2" fill="url(#beam)"/>
  <text x="92" y="102" font-family="DejaVu Sans, Segoe UI, sans-serif"
        font-size="12" fill="#9aa4b2">quickopen.ai  ·  based on LibreOffice</text>
</svg>
"""

# Splash progress bar: sits under the app marks, in the Aura accent, on the
# deep-space field. Values are px on the 640x400 intro.png above.
PROGRESS_CONF = """PROGRESSBARCOLOR="91,134,247"
PROGRESSFRAMECOLOR="43,49,59"
PROGRESSTEXTCOLOR="154,164,178"
PROGRESSSIZE="540,6"
PROGRESSPOSITION="50,296"
PROGRESSTEXTBASELINE="288"
"""


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.dirname(
        os.path.abspath(__file__))
    os.makedirs(out, exist_ok=True)
    draw_intro(os.path.join(out, "intro.png"))
    for name, body in (("logo.svg", LOGO_SVG), ("about.svg", ABOUT_SVG),
                       ("progress.conf", PROGRESS_CONF)):
        with open(os.path.join(out, name), "w", encoding="utf-8") as fh:
            fh.write(body)
    print("branding written to", out)
    for f in ("intro.png", "about.svg", "logo.svg", "progress.conf"):
        p = os.path.join(out, f)
        print("  %-14s %6d B" % (f, os.path.getsize(p)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
