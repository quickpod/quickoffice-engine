#!/usr/bin/env python3
r"""Derive the Aura icon theme from Colibre.

WHY COLIBRE
LibreOffice bundles six icon themes. Their licences differ and it matters:

    colibre       CC0 1.0        public domain, commercial adaptation explicit
    sifr          CC BY-SA 3.0   share-alike -> would infect our theme
    breeze        LGPL/CC BY-SA  KDE's, same problem
    elementary    GPL
    karasa_jaga   LGPL-3.0
    sukapura      MPL-2.0

CC0 is the only one that lets our derivative stay Apache-2.0 like the rest of
the QuickOpen fleet, and Colibre happens to be the theme deliberately drawn to
sit alongside a Fluent/Office-style UI -- which is exactly the look the brief
asks for. Credit is given in NOTICE anyway; CC0 does not require it.

WHAT IS CHANGED, AND WHAT IS DELIBERATELY NOT
Only the BLUE ACCENT FAMILY and the neutral ink move. Colibre's blues are its
"this is interactive / this is the subject" colour, and that is the one thing
that should be the app's accent instead. The semantic hues -- red for delete,
green for insert, orange for chart/presentation -- are LEFT ALONE. They are not
decoration, they are how somebody finds the right button in a 200-icon ribbon,
and repainting them Aura-blue would flatten the ribbon into an unreadable
monochrome field. A design system should be recognisable, not totalitarian.

HOW IT WORKS
Operates on the PACKED theme (`images_colibre.zip`) that the build produces,
not on the SVG sources, so it needs no hook into the LibreOffice build at all:
recolour PNGs in place, rewrite the zip under a new name, drop it in
share/config/. LibreOffice discovers any `images_<id>.zip` on that path at
runtime (vcl/source/app/IconThemeInfo.cxx, ICON_THEME_PACKAGE_PREFIX), so the
theme registers itself with zero edits to core/.

    make-aura-icons.py <instdir>          e.g. core/instdir
"""

import os
import shutil
import sys
import zipfile

from PIL import Image

# ---------------------------------------------------------------- the mapping
# Colibre source colour -> Aura token. Sampled from the theme's own SVG census
# (icon-themes/colibre_svg/cmd/32/*.svg), most-used first.
ACCENT_MAP = {
    (0x1e, 0x8b, 0xcd): (0x5b, 0x86, 0xf7),   # primary accent  -> aura accent
    (0x00, 0x63, 0xb1): (0x3a, 0x5f, 0xd0),   # accent strong   -> aura strong
    (0x83, 0xbe, 0xec): (0xa9, 0xc0, 0xfb),   # accent light    -> aura light
}
# The neutral ink. Nudged toward the Aura text token so glyphs sit in the same
# family as every other QuickOpen surface, without going so dark they smear.
INK_MAP = {
    (0x3a, 0x3a, 0x38): (0x2b, 0x31, 0x3b),   # glyph ink   -> aura border2-ish
    (0x79, 0x77, 0x74): (0x5b, 0x65, 0x7a),   # muted grey  -> aura muted
    (0xc8, 0xc6, 0xc4): (0xc8, 0xd0, 0xdc),   # hairline    -> aura border2
}
# The dark-theme variant needs the ink to go the other way: light glyphs on a
# dark surface.
INK_MAP_DARK = {
    (0xff, 0xff, 0xff): (0xf1, 0xf3, 0xf7),   # glyph       -> aura text (dark)
    (0xde, 0xde, 0xde): (0x9a, 0xa4, 0xb2),   # muted       -> aura muted (dark)
}
TOLERANCE = 10          # channel distance treated as "the same colour"


def _near(a, b):
    return all(abs(a[i] - b[i]) <= TOLERANCE for i in range(3))


def recolour(data, mapping):
    """Recolour one PNG's flat fills, preserving alpha and anti-aliasing.

    Anti-aliased edges are blends of a fill and transparency, not separate
    colours, so mapping the fills and leaving alpha untouched keeps the edges
    correct for free.
    """
    import io
    try:
        im = Image.open(io.BytesIO(data)).convert("RGBA")
    except Exception:
        return data                        # not an image we can touch
    px = im.load()
    w, h = im.size
    hits = 0
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if a == 0:
                continue
            for src, dst in mapping.items():
                if _near((r, g, b), src):
                    px[x, y] = (dst[0], dst[1], dst[2], a)
                    hits += 1
                    break
    if not hits:
        return data
    out = io.BytesIO()
    im.save(out, format="PNG", optimize=True)
    return out.getvalue()


def build_theme(src_zip, dst_zip, mapping):
    n_changed = 0
    with zipfile.ZipFile(src_zip) as zin, \
            zipfile.ZipFile(dst_zip, "w", zipfile.ZIP_DEFLATED) as zout:
        for item in zin.infolist():
            data = zin.read(item.filename)
            if item.filename.lower().endswith(".png"):
                new = recolour(data, mapping)
                if new is not data:
                    n_changed += 1
                data = new
            zout.writestr(item, data)
    return n_changed


def main():
    instdir = sys.argv[1] if len(sys.argv) > 1 else \
        "/home/ubuntu/quickopen/office/core/instdir"
    cfg = os.path.join(instdir, "share", "config")
    if not os.path.isdir(cfg):
        print("no share/config in", instdir, "- has the build finished?")
        return 1

    jobs = [("images_colibre.zip", "images_aura.zip",
             {**ACCENT_MAP, **INK_MAP}),
            ("images_colibre_dark.zip", "images_aura_dark.zip",
             {**ACCENT_MAP, **INK_MAP_DARK})]
    made = 0
    for src, dst, mapping in jobs:
        s = os.path.join(cfg, src)
        if not os.path.isfile(s):
            print("  skip", src, "(not built)")
            continue
        d = os.path.join(cfg, dst)
        n = build_theme(s, d, mapping)
        print("  %-24s -> %-22s %5d icons recoloured, %.1f MB"
              % (src, dst, n, os.path.getsize(d) / 1e6))
        made += 1
    if not made:
        print("nothing built")
        return 1
    print("\nThemes register themselves: LibreOffice scans share/config for")
    print("images_*.zip at runtime. Select with Misc/SymbolStyle = 'aura'.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
