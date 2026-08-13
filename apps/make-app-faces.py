#!/usr/bin/env python3
r"""Generate the three Quick Office app faces over the shared engine.

One engine, three products. LibreOffice is a single `soffice` binary that
decides which module to open from a command-line switch, so Quick Document,
Quick Spreadsheet and Quick Presentation are not three programs -- they are
three IDENTITIES (name, icon, splash-through-to-window-title, file
associations, Start-menu entry) over one installed engine. That is the shape
the packaging brief settled on: ~390 MB once, ~2 MB per app.

Each face gets:
  * a launcher script     picks the module and sets WM_CLASS so the taskbar
                          groups windows under the right app, not under
                          "soffice"
  * a .desktop entry      Linux / AIQuick app menu + file associations
  * the MIME types        both the ODF native type and the Microsoft type the
                          app is the natural opener for -- a user who
                          double-clicks a .docx expects Quick Document, not a
                          suite launcher

    make-app-faces.py [outdir]      default: alongside this file
"""

import os
import stat
import sys

APPS = [
    {
        "slug": "quick-document",
        "name": "Quick Document",
        "module": "--writer",
        "generic": "Word Processor",
        "comment": "Write letters, reports and books. Opens and saves .docx and .odt.",
        "keywords": "document;word;writer;text;letter;report;docx;odt;",
        "mimes": [
            "application/vnd.oasis.opendocument.text",
            "application/vnd.oasis.opendocument.text-template",
            "application/vnd.oasis.opendocument.text-master",
            "application/msword",
            "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
            "application/vnd.openxmlformats-officedocument.wordprocessingml.template",
            "application/rtf",
            "text/rtf",
        ],
    },
    {
        "slug": "quick-spreadsheet",
        "name": "Quick Spreadsheet",
        "module": "--calc",
        "generic": "Spreadsheet",
        "comment": "Calculate, chart and analyse. Opens and saves .xlsx and .ods.",
        "keywords": "spreadsheet;calc;excel;chart;formula;pivot;xlsx;ods;csv;",
        "mimes": [
            "application/vnd.oasis.opendocument.spreadsheet",
            "application/vnd.oasis.opendocument.spreadsheet-template",
            "application/vnd.ms-excel",
            "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
            "application/vnd.openxmlformats-officedocument.spreadsheetml.template",
            "text/csv",
        ],
    },
    {
        "slug": "quick-presentation",
        "name": "Quick Presentation",
        "module": "--impress",
        "generic": "Presentation",
        "comment": "Build and present slide decks. Opens and saves .pptx and .odp.",
        "keywords": "presentation;slides;impress;powerpoint;deck;pptx;odp;",
        "mimes": [
            "application/vnd.oasis.opendocument.presentation",
            "application/vnd.oasis.opendocument.presentation-template",
            "application/vnd.ms-powerpoint",
            "application/vnd.openxmlformats-officedocument.presentationml.presentation",
            "application/vnd.openxmlformats-officedocument.presentationml.template",
            "application/vnd.openxmlformats-officedocument.presentationml.slideshow",
        ],
    },
]

ENGINE = "/opt/quickoffice"

LAUNCHER = """#!/usr/bin/env bash
# {name} — a face over the shared Quick Office engine.
#
# The engine is one binary; the module switch is what makes this Quick
# {short}. WM_CLASS is forced so the desktop groups these windows under
# {name} rather than under the engine's own class, which is what makes
# three separate taskbar identities out of one program.
#
# Apache-2.0, (c) 2026 QuickOpen. Engine: MPL-2.0, based on LibreOffice.
set -euo pipefail
ENGINE="${{QUICKOFFICE_ENGINE:-{engine}}}"
SOFFICE="$ENGINE/program/soffice"

if [ ! -x "$SOFFICE" ]; then
  echo "{name}: the Quick Office engine is not installed at $ENGINE" >&2
  echo "Install the quickoffice-engine package, or set QUICKOFFICE_ENGINE." >&2
  exit 1
fi

exec "$SOFFICE" {module} \\
  -env:UserInstallation="file://${{XDG_CONFIG_HOME:-$HOME/.config}}/quickoffice" \\
  "$@"
"""

DESKTOP = """[Desktop Entry]
Version=1.0
Type=Application
Name={name}
GenericName={generic}
Comment={comment}
Exec={slug} %U
Icon={slug}
Terminal=false
Categories=Office;{category};
Keywords={keywords}
StartupNotify=true
StartupWMClass={slug}
MimeType={mimes}
"""

CATEGORY = {"quick-document": "WordProcessor",
            "quick-spreadsheet": "Spreadsheet",
            "quick-presentation": "Presentation"}


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.dirname(
        os.path.abspath(__file__))
    for d in ("bin", "applications"):
        os.makedirs(os.path.join(out, d), exist_ok=True)

    for app in APPS:
        slug = app["slug"]
        launcher = os.path.join(out, "bin", slug)
        with open(launcher, "w", encoding="utf-8") as fh:
            fh.write(LAUNCHER.format(
                name=app["name"], short=app["generic"], engine=ENGINE,
                module=app["module"]))
        os.chmod(launcher, os.stat(launcher).st_mode | stat.S_IEXEC
                 | stat.S_IXGRP | stat.S_IXOTH)

        desktop = os.path.join(out, "applications", slug + ".desktop")
        with open(desktop, "w", encoding="utf-8") as fh:
            fh.write(DESKTOP.format(
                name=app["name"], generic=app["generic"],
                comment=app["comment"], slug=slug,
                category=CATEGORY[slug], keywords=app["keywords"],
                mimes=";".join(app["mimes"]) + ";"))
        print("  %-20s launcher + .desktop (%d MIME types)"
              % (app["name"], len(app["mimes"])))
    print("\nwritten to", out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
