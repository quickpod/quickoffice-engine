#!/usr/bin/env python3
r"""Generate the Quick Office branding set consumed by `--with-branding`.

LibreOffice's configure walks a FIXED list of files in that directory
(configure.ac, `brand_files`) and, for every one it does NOT find, keeps the
UPSTREAM LibreOffice asset with nothing louder than an AC_MSG_WARN:

    intro.png  intro-highres.png            the splash, normal and HiDPI
    logo.svg  logo_inverted.svg             the application logo, both inks
    logo-sc.svg  logo-sc_inverted.svg       the Start Center logo, both inks
    about.svg                               the logo in Help > About
    donate1.png  donate2.png                the TDF donation banner art
    progress.conf                           splash progress bar geometry

THE SILENT FALLBACK IS THE WHOLE POINT OF THIS FILE. Until 2026-08-21 this
script emitted four of the nine, so the shipped product carried the
LibreOffice green wordmark as its Start Center logo, the LibreOffice splash on
any HiDPI screen, and The Document Foundation's donation art — a trademark
leak (LICENSING.md rule #3) that no build ever failed on, because a warning
buried in a configure log is not a failure. Emit ALL of them, and let
verify_complete() below fail the build rather than the trademark audit.

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


def draw_intro(path, k=1):
    """The splash: deep-space field, accent beam, wordmark, three app marks.

    `k` scales every coordinate AND every font size, so the HiDPI sheet is a
    true 2x render rather than an upscale of the 1x PNG. Keep the geometry
    expressed as `k *` multiples of the 640x400 design grid: progress.conf's
    High values are derived from the same k, and the two must not drift.
    """
    w, h = W * k, H * k
    img = Image.new("RGB", (w, h), BG)
    d = ImageDraw.Draw(img)

    # a soft vertical lift so the panel does not read as flat black
    for y in range(h):
        d.line([(0, y), (w, y)], fill=_mix(BG2, BG, y / h))

    # the Aura signature beam, fading out to the right
    beam_y = 150 * k
    step = 2 * k
    for x in range(0, w, step):
        t = min(1.0, x / (w * 0.8))
        d.rectangle([x, beam_y, x + step, beam_y + step], fill=_mix(ACCENT, BG, t))

    d.text((48 * k, 86 * k), "Quick Office", font=_font(40 * k, bold=True), fill=TEXT)
    d.text((50 * k, 168 * k), "Documents · Spreadsheets · Presentations",
           font=_font(15 * k), fill=MUTED)

    # three line-art marks, one per app, in their own accents
    x0, y0, s = 50 * k, 214 * k, 52 * k
    for i, (slug, col) in enumerate(APP_ACCENTS.items()):
        x = x0 + i * (s + 26 * k)
        d.rounded_rectangle([x, y0, x + s, y0 + s], radius=9 * k, outline=col,
                            width=2 * k)
        if slug == "quick-document":                 # text lines on a page
            for j in range(3):
                d.line([x + 13 * k, y0 + (17 + j * 10) * k,
                        x + s - 13 * k - (j == 2) * 12 * k,
                        y0 + (17 + j * 10) * k], fill=col, width=2 * k)
        elif slug == "quick-spreadsheet":            # a grid
            for j in range(1, 3):
                d.line([x + 10 * k, y0 + (10 + j * 11) * k,
                        x + s - 10 * k, y0 + (10 + j * 11) * k],
                       fill=col, width=2 * k)
                d.line([x + (10 + j * 11) * k, y0 + 10 * k,
                        x + (10 + j * 11) * k, y0 + s - 10 * k],
                       fill=col, width=2 * k)
        else:                                        # a slide with a bar chart
            for dx, top in ((13, 24), (25, 17), (37, 27)):
                d.line([x + dx * k, y0 + 36 * k, x + dx * k, y0 + top * k],
                       fill=col, width=3 * k)

    d.text((50 * k, 330 * k), "quickopen.ai", font=_font(13 * k), fill=MUTED)
    # the attribution the trademark policy asks for, on the very first screen
    d.text((50 * k, 352 * k), "Based on LibreOffice. Not affiliated with "
                              "The Document Foundation.", font=_font(11 * k),
           fill=MUTED)

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

# The application logo, inverted ink. LibreOffice picks the _inverted variant
# whenever the surrounding UI is dark, and falls back to UPSTREAM's — the green
# LibreOffice mark — if we do not ship one. The line art is identical; only the
# strokes and the page fill change.
LOGO_INVERTED_SVG = LOGO_SVG.replace(
    "Quick Office application logo",
    "Quick Office application logo, inverted (dark UI)").replace(
    'fill="#0f1115"', 'fill="#f1f3f7"').replace(
    'stroke="#5b86f7"', 'stroke="#8fb0ff"').replace(
    'stroke="#2f5fe0"', 'stroke="#5b86f7"')


def _logo_sc(ink, sub, label):
    """The Start Center wordmark: a wide lockup, page mark + name + beam.

    Upstream's is 345.611x71.5 and carries the LibreOffice wordmark in TDF
    green; ours keeps the aspect so the Start Center lays it out the same.
    """
    return """<?xml version="1.0" encoding="UTF-8"?>
<!-- Quick Office Start Center logo (%s). Aura tokens only; nothing here is
     derived from any third-party mark. Apache-2.0, (c) 2026 QuickOpen. -->
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 346 72" width="346"
     height="72" fill="none">
  <defs>
    <linearGradient id="scbeam" x1="0" y1="0" x2="1" y2="0">
      <stop offset="0" stop-color="#5b86f7"/>
      <stop offset="0.9" stop-color="#5b86f7" stop-opacity="0"/>
    </linearGradient>
  </defs>
  <rect x="8" y="14" width="34" height="44" rx="6" stroke="#5b86f7"
        stroke-width="4"/>
  <path d="M17 27h16M17 36h16M17 45h9" stroke="#5b86f7" stroke-width="4"
        stroke-linecap="round"/>
  <text x="58" y="44" font-family="DejaVu Sans, Segoe UI, sans-serif"
        font-size="27" font-weight="700" fill="%s">Quick Office</text>
  <rect x="58" y="52" width="256" height="2" fill="url(#scbeam)"/>
  <text x="58" y="66" font-family="DejaVu Sans, Segoe UI, sans-serif"
        font-size="9" fill="%s">based on LibreOffice</text>
</svg>
""" % (label, ink, sub)


LOGO_SC_SVG = _logo_sc("#0f1115", "#5a6472", "light UI")
LOGO_SC_INVERTED_SVG = _logo_sc("#f1f3f7", "#9aa4b2", "dark UI")


def draw_donation(path, size):
    """Displace TDF's donation art with a neutral Aura mark.

    The Start Center's donation banner is switched OFF in the registry overlay
    (Office/Common Misc/ShowDonation=false) — it solicits donations to The
    Document Foundation from inside a QuickOpen product and opens an outbound
    URL, which requirement #2 forbids. These files therefore never render; they
    exist so that no Document Foundation asset ships in the tree at all.
    """
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    m = size // 8
    d.rounded_rectangle([m, m, size - m, size - m], radius=size // 10,
                        outline=ACCENT, width=max(2, size // 40))
    d.line([size // 2, m * 2, size // 2, size - m * 2], fill=ACCENT,
           width=max(2, size // 40))
    d.line([m * 2, size // 2, size - m * 2, size // 2], fill=ACCENT,
           width=max(2, size // 40))
    img.save(path)
    return path


# Splash progress bar: sits under the app marks, in the Aura accent, on the
# deep-space field. Values are px on the 640x400 intro.png above; the *HIGH
# pair is the same geometry times HIDPI_SCALE, for intro-highres.png.
#
# The HIGH keys are NOT read by configure (its progress section AC_SUBSTs only
# the six unscaled ones) — install-branding.sh writes them straight into the
# install tree's sofficerc / soffice.ini, which is also the only path by which
# ANY of these values reach a shipped build. Keep them here anyway: this file
# is the one place the splash geometry is defined.
HIDPI_SCALE = 2

PROGRESS_CONF = """PROGRESSBARCOLOR="91,134,247"
PROGRESSFRAMECOLOR="43,49,59"
PROGRESSTEXTCOLOR="154,164,178"
PROGRESSSIZE="540,6"
PROGRESSPOSITION="50,296"
PROGRESSTEXTBASELINE="288"
PROGRESSSIZEHIGH="1080,12"
PROGRESSPOSITIONHIGH="100,592"
"""

# configure.ac's `brand_files`, verbatim. Anything on this list that we do not
# emit is silently served from upstream — see the module docstring.
BRAND_FILES = ("intro.png", "intro-highres.png", "logo.svg",
               "logo_inverted.svg", "logo-sc.svg", "logo-sc_inverted.svg",
               "about.svg", "donate1.png", "donate2.png")


def verify_complete(out):
    """Fail loudly if the emitted set does not cover every brand file.

    A missing file costs no build error and no test — only a LibreOffice
    asset quietly shipping under our name. This is the check that turns that
    into an exit code.
    """
    missing = [f for f in BRAND_FILES + ("progress.conf",)
               if not os.path.isfile(os.path.join(out, f))]
    if missing:
        raise SystemExit("branding INCOMPLETE, upstream would be used for: "
                         + " ".join(missing))


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.dirname(
        os.path.abspath(__file__))
    os.makedirs(out, exist_ok=True)
    draw_intro(os.path.join(out, "intro.png"))
    draw_intro(os.path.join(out, "intro-highres.png"), k=HIDPI_SCALE)
    draw_donation(os.path.join(out, "donate1.png"), 200)
    draw_donation(os.path.join(out, "donate2.png"), 150)
    for name, body in (("logo.svg", LOGO_SVG),
                       ("logo_inverted.svg", LOGO_INVERTED_SVG),
                       ("logo-sc.svg", LOGO_SC_SVG),
                       ("logo-sc_inverted.svg", LOGO_SC_INVERTED_SVG),
                       ("about.svg", ABOUT_SVG),
                       ("progress.conf", PROGRESS_CONF)):
        with open(os.path.join(out, name), "w", encoding="utf-8") as fh:
            fh.write(body)
    verify_complete(out)
    print("branding written to", out)
    for f in BRAND_FILES + ("progress.conf",):
        p = os.path.join(out, f)
        print("  %-22s %7d B" % (f, os.path.getsize(p)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
