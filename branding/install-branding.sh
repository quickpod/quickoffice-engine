#!/usr/bin/env bash
# Apply the Quick Office branding set to a built install tree.
#
#   branding/install-branding.sh <tree> [product-name] [version]
#
# WHY THIS EXISTS AT ALL, given `--with-branding` already points configure at
# branding/:  because --with-branding covers ONE of the two trees we ship, and
# covers it only partially.
#
#   * Windows is a REPACK of the official LibreOffice MSI (packaging/windows/),
#     so configure never runs. Every brand asset in that tree was TDF's:
#     the splash a user saw at startup said "LibreOffice — The Document
#     Foundation". That is the defect this script was written for.
#   * Linux is a source build, but configure FALLS BACK to the upstream asset
#     for every brand file the branding dir does not contain, warning only into
#     a log. Four of the nine were missing, so the Start Center wore the green
#     LibreOffice wordmark and any HiDPI screen got the LibreOffice splash.
#   * The progress-bar geometry in progress.conf reaches only the packaged
#     INSTALLER's sofficerc (scp2/common_brand.scp). We ship instdir directly
#     — cp -a into the deb — so those values never applied on either platform,
#     and the bar drew black-on-black at upstream's coordinates.
#
# Running it on both trees makes the branding a property of what we SHIP rather
# than of how it happened to be built, and keeps one copy of the file list.
# It is idempotent: re-running on an already-branded tree changes nothing.
#
# Deliberately NOT a patch to core/: same rule as registry/install-registry.sh
# — the overlay is ours, the engine stays upstream, and a LibreOffice rebase
# stays a two-line change to pin.txt.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENGINE_REPO="$(cd "$HERE/.." && pwd)"
TREE="${1:?usage: install-branding.sh <tree> [product-name] [version]}"
PRODUCT="${2:-Quick Office}"
VERSION="${3:-$(awk -F= '/^version=/{print $2}' "$ENGINE_REPO/pin.txt" | tr -d ' ')}"

PROG="$TREE/program"
[ -d "$PROG" ] || { echo "!! no program/ under $TREE — not an install tree" >&2; exit 1; }

# LIBO_ETC_FOLDER is "program" on both Linux and Windows, so only the rc file
# SUFFIX differs: sofficerc/bootstraprc on Unix, soffice.ini/bootstrap.ini on
# Windows. Pick by what is actually there rather than by uname: this script
# runs on Linux in both cases (the Windows tree is an extracted MSI).
if   [ -f "$PROG/sofficerc"   ]; then SOFFICERC="$PROG/sofficerc";   BOOTRC="$PROG/bootstraprc"
elif [ -f "$PROG/soffice.ini" ]; then SOFFICERC="$PROG/soffice.ini"; BOOTRC="$PROG/bootstrap.ini"
else echo "!! neither sofficerc nor soffice.ini under $PROG" >&2; exit 1
fi

# ---------------------------------------------------------------- the assets
# configure.ac's `brand_files`, split by where the install tree wants them.
# intro*.png sit in program/, everything else in program/shell/ (upstream's
# Package_branding.mk makes exactly this split with BRAND_INTRO_IMAGES).
INTRO_IMAGES="intro.png intro-highres.png"
SHELL_IMAGES="logo.svg logo_inverted.svg logo-sc.svg logo-sc_inverted.svg about.svg donate1.png donate2.png"

for f in $INTRO_IMAGES $SHELL_IMAGES progress.conf; do
  [ -f "$HERE/$f" ] || { echo "!! branding/$f missing — run branding/make-branding.py" >&2; exit 1; }
done

mkdir -p "$PROG/shell"
n=0
for f in $INTRO_IMAGES;  do install -m 644 "$HERE/$f" "$PROG/$f";        n=$((n+1)); done
for f in $SHELL_IMAGES;  do install -m 644 "$HERE/$f" "$PROG/shell/$f";  n=$((n+1)); done
echo "   branding: $n asset(s) -> program/ + program/shell/"

# ------------------------------------------------------- the splash geometry
# progress.conf is shell-sourceable by design (configure does the same).
# shellcheck source=/dev/null
. "$HERE/progress.conf"

# Rewrite one key in a [Bootstrap] rc, appending it if absent. sed -i in place:
# these are small generated files, and an rc that loses a key silently reverts
# the splash to upstream's black bar at upstream's coordinates.
set_key() {
  local file="$1" key="$2" val="$3"
  if grep -q "^$key=" "$file"; then
    sed -i "s|^$key=.*|$key=$val|" "$file"
  else
    printf '%s=%s\n' "$key" "$val" >> "$file"
  fi
  grep -q "^$key=$val$" "$file" || { echo "!! failed to set $key in $file" >&2; exit 1; }
}

set_key "$SOFFICERC" Logo 1
set_key "$SOFFICERC" ProgressBarColor      "$PROGRESSBARCOLOR"
set_key "$SOFFICERC" ProgressFrameColor    "$PROGRESSFRAMECOLOR"
set_key "$SOFFICERC" ProgressTextColor     "$PROGRESSTEXTCOLOR"
set_key "$SOFFICERC" ProgressTextBaseline  "$PROGRESSTEXTBASELINE"
set_key "$SOFFICERC" ProgressSize          "$PROGRESSSIZE"
set_key "$SOFFICERC" ProgressPosition      "$PROGRESSPOSITION"
# The *High pair is read only by the X11 splash (desktop/unx/source/splashx.c)
# and only when it actually loaded intro-highres.png. Harmless on Windows,
# whose SplashScreen has no HiDPI sheet at all.
set_key "$SOFFICERC" ProgressSizeHigh      "$PROGRESSSIZEHIGH"
set_key "$SOFFICERC" ProgressPositionHigh  "$PROGRESSPOSITIONHIGH"
echo "   splash geometry: $(basename "$SOFFICERC") bar=$PROGRESSSIZE@$PROGRESSPOSITION high=$PROGRESSSIZEHIGH@$PROGRESSPOSITIONHIGH"

# ------------------------------------------------------------ the identity
# ProductKey shows in window titles and crash paths; UserInstallation is where
# the user profile lives. The Linux source build already gets both from
# --with-product-name; the Windows repack inherited "LibreOffice 26.2" and
# $SYSUSERCONFIG/LibreOffice/4, so a Quick Office user's settings were being
# written into a folder named after a product they did not install.
#
# NOTE FOR WINDOWS UPGRADES: changing UserInstallation moves the profile, so a
# machine that ran the pre-2026-08-21 build starts from defaults. Accepted —
# the Windows installers are five days old, and the alternative is shipping the
# LibreOffice name in every user's AppData indefinitely.
if [ -f "$BOOTRC" ]; then
  set_key "$BOOTRC" ProductKey "$PRODUCT ${VERSION%%.*}.$(echo "$VERSION" | cut -d. -f2)"
  # %20 for the space: this value is a URL-ish path expression, and an
  # unescaped space truncates the profile directory at "quick".
  set_key "$BOOTRC" UserInstallation "\$SYSUSERCONFIG/$(echo "$PRODUCT" | tr 'A-Z' 'a-z' | sed 's/ /%20/g')/4"
  echo "   identity: $(basename "$BOOTRC") $(grep '^ProductKey=' "$BOOTRC")"
fi

# ------------------------------------------------------------------- verify
# Assert the tree now carries OUR bytes. This is the check that would have
# caught the original defect: it compares content, not "did cp exit 0".
bad=""
for f in $INTRO_IMAGES; do
  cmp -s "$HERE/$f" "$PROG/$f" || bad="$bad program/$f"
done
for f in $SHELL_IMAGES; do
  cmp -s "$HERE/$f" "$PROG/shell/$f" || bad="$bad program/shell/$f"
done
[ -z "$bad" ] || { echo "!! branding did not take for:$bad" >&2; exit 1; }
echo "== branding installed into $TREE (verified $n file(s))"
