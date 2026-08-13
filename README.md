# Quick Office

**Quick Document**, **Quick Spreadsheet** and **Quick Presentation** — three
QuickOpen applications over one shared engine, built from the LibreOffice
source code.

> This product is a derivative of LibreOffice. It is not LibreOffice and is not
> endorsed by or affiliated with The Document Foundation. See [NOTICE](NOTICE)
> and [LICENSING.md](LICENSING.md).

## What this is

One engine, three products. LibreOffice is a single `soffice` binary that picks
its module from a command-line switch, so these are not three programs — they
are three **identities** (name, icon, splash, window class, file associations,
menu entry) over one installed engine:

| | module | opens |
|---|---|---|
| Quick Document | `--writer` | `.odt` `.docx` `.doc` `.rtf` |
| Quick Spreadsheet | `--calc` | `.ods` `.xlsx` `.xls` `.csv` |
| Quick Presentation | `--impress` | `.odp` `.pptx` `.ppt` |

Disk cost: the engine once (~390 MB), then ~2 MB per app. Every capability
LibreOffice has is present — this is the whole suite, rebranded and rethemed,
not a reduced re-implementation.

## Layout

```
core/                     the LibreOffice source (upstream + our patches)
quickoffice/
  configure-quickoffice.sh  the one place the build is parameterised
  branding/               splash, About logo, app logo, progress bar
    make-branding.py      regenerates all four from the Aura tokens
  registry/               the Aura config layer (.xcu -> .xcd overlay)
  aura-icons/             Colibre (CC0) -> Aura icon theme derivation
  apps/                   the three app faces: launchers + .desktop entries
    make-app-faces.py     regenerates them
licenses/                 MPL-2.0, LGPL-3.0, GPL-3.0, Apache-2.0
NOTICE                    attribution + where to get the source
LICENSING.md              why all of this is allowed, and what it obliges
```

## The governing rule: don't patch core

Everything that makes this our product is done through hooks upstream already
provides, so that rebasing onto the next LibreOffice release stays a `git
rebase` and not an archaeology project:

| what | how | core edited? |
|---|---|---|
| product name, window titles, install paths | `--with-product-name` | no |
| vendor line in About | `--with-vendor` | no |
| splash, About logo, progress bar | `--with-branding` | no |
| icon theme | `images_aura.zip` dropped in `share/config`, found by the runtime scanner | no |
| ribbon UI, follow-system theme, no phone-home | registry overlay in `share/registry` | no |
| three app identities | launchers + `.desktop` files outside the engine | no |

If something ever *cannot* be done this way, it gets a patch in
`quickoffice/patches/` with a comment saying why the supported route failed —
not an untracked edit inside `core/`.

## Build

```
quickoffice/branding/make-branding.py       # if branding changed
quickoffice/configure-quickoffice.sh        # autogen + configure
make -j$(nproc)                             # in core/, several hours
quickoffice/aura-icons/make-aura-icons.py core/instdir
core/instdir/program/soffice --writer       # run it
```

Two toolchain facts this box learned the hard way, both pinned in the configure
script:

- **GCC 13 or newer.** LibreOffice 26.8 refuses anything older; Ubuntu 22.04
  ships 11.4, so gcc-13 comes from the `ubuntu-toolchain-r/test` PPA.
- **clang 16 or newer, separately.** Skia (the GPU renderer) is built with
  clang, not GCC, and clang-15 cannot parse GCC 13's libstdc++ `<chrono>`. The
  alternative was `--disable-skia`, which would cost GPU-accelerated rendering
  suite-wide; clang-18 from apt.llvm.org is the cheaper price.

The build must **not** run as root — upstream's Makefile refuses, correctly.
This tree builds as the unprivileged `qobuild` user; the caches
(`../.ccache`, `../externals`) live inside the tree so one `chown` covers
everything.

## Product requirements this build satisfies

From the AIQuick requirement list, the ones that are build- or config-time:

- **#2 zero egress** — `--disable-breakpad` (no crash upload),
  `--disable-extension-update`; nothing contacts a remote unprompted.
- **#3 no auto-update** — `--disable-online-update`. Updates arrive through the
  AIQuick apt repo when the user asks for them, like every other app.
- **#10b user-friendly** — no first-run wizard, no tip-of-the-day, no
  what's-new popup.
- **#11 trademark-free** — our own name, splash, logo and icons; the only
  mention of LibreOffice is the factual "based on" attribution the trademark
  policy asks for.
- **#46 Aura everywhere** — the accent, palette and beam come from
  `aura-tokens.json`, the same source the other 36 apps generate from.

## Platform plan

Linux/AIQuick first, because that is where the from-source build runs natively
and where the apt repo already delivers the rest of the fleet.

**Windows needs a decision.** The other 36 apps build on a GitHub-hosted
`windows-latest` runner in minutes. LibreOffice does not: it needs MSVC plus a
Cygwin environment, and a full build runs well past the 6-hour job limit on
GitHub-hosted runners. Realistic options, cheapest first:

1. a self-hosted Windows runner (a QuickPod Windows box) doing the engine build
   on release only, with the three faces built normally in CI;
2. ship Linux/AIQuick first and add Windows when a runner exists;
3. build the engine once by hand per release and cache the artifact.

This does not affect the Linux work in flight, but it does mean "three Windows
installers on the portal" is a separate piece of work with its own lead time.
