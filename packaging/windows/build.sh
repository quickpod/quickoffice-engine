#!/usr/bin/env bash
# Build the three Quick Office Windows installers (v1: upstream-MSI repack).
#
#   packaging/windows/build.sh [downloads_dir] [outdir]
#
# See make-windows-installers.py for the whole design. This script:
#   1. verifies + extracts the pinned LibreOffice stable win64 MSI (msiextract)
#   2. dresses the tree with the Aura layer — the SAME registry overlay the
#      Linux debs get (../../registry/install-registry.sh) plus the Aura icon
#      theme zips (platform-independent, taken from the Linux engine build)
#   3. ships our NOTICE/LICENSING/licenses inside the engine dir
#   4. compiles QuickDocument/QuickSpreadsheet/QuickPresentation-Setup.exe
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENGINE_REPO="$(cd "$HERE/../.." && pwd)"
REPOS="$(cd "$ENGINE_REPO/.." && pwd)"
ROOT="$(cd "$REPOS/.." && pwd)"
DL="${1:-$ROOT/winbuild/downloads}"
OUT="${2:-$ROOT/winbuild/dist}"
WORK="$ROOT/winbuild/work/quickoffice"

pin(){ awk -F= -v k="$1" '$1==k{print $2}' "$HERE/windows-pin.txt" | tr -d ' \r'; }
LOVER="$(pin libreoffice_version)"        # e.g. 26.2.5
SHA256="$(pin sha256)"
REV="${QUICKOFFICE_WIN_REV:-1}"
DISPLAYVER="$LOVER-$REV"
MSI="$DL/LibreOffice_${LOVER}_Win_x86-64.msi"

command -v makensis   >/dev/null || { echo "makensis missing (apt install nsis)" >&2; exit 1; }
command -v msiextract >/dev/null || { echo "msiextract missing (apt install msitools)" >&2; exit 1; }
command -v convert    >/dev/null || { echo "ImageMagick convert missing" >&2; exit 1; }
[ -f "$MSI" ] || { echo "missing $MSI — download the pinned upstream MSI first" >&2; exit 1; }

echo "== Quick Office Windows installers  $DISPLAYVER  (engine: LibreOffice $LOVER MSI)"
echo "$SHA256  $MSI" | sha256sum -c - >/dev/null || { echo "!! sha256 mismatch on $MSI" >&2; exit 1; }
echo "   upstream sha256 ok (TDF .sha256)"

rm -rf "$WORK" && mkdir -p "$WORK" "$OUT"

# ---- 1. extract ------------------------------------------------------------
msiextract -C "$WORK/msi" "$MSI" >/dev/null
ENGINE="$(find "$WORK/msi" -type f -name soffice.exe -printf '%h\n' | head -1)"
[ -n "$ENGINE" ] || { echo "no soffice.exe in extracted MSI" >&2; exit 1; }
ENGINE="$(dirname "$ENGINE")"      # tree root: contains program/, share/, ...
echo "   engine tree: $ENGINE"

# NO app-local VC++ runtime — FIELD DEFECT: the MSI carries merge modules for
# SEVERAL architectures and msiextract dumps them all, so the "vcruntime" DLLs
# grabbed from the extracted tree were ARM64 (PE machine 0xAA64); putting them
# in program\ crashed soffice on launch (AV in VCRUNTIME140_1.dll). The x64
# runtime comes from Microsoft's own vc_redist.x64.exe instead, which the
# installers chain-install silently when the machine lacks VC14 >= 14.30
# (pin + sha256 in windows-pin.txt). Strip ANY stray CRT DLLs the extraction
# may have left inside program\ for the same reason.
find "$ENGINE/program" -maxdepth 1 -type f \( -iname 'vcruntime*.dll' -o -iname 'msvcp*.dll' -o -iname 'concrt*.dll' -o -iname 'vccorlib*.dll' \) -delete
VCREDIST="$DL/vc_redist.x64.exe"
if [ ! -f "$VCREDIST" ]; then
  curl -sL -o "$VCREDIST" "$(pin vcredist_url)"
fi
echo "$(pin vcredist_sha256)  $VCREDIST" | sha256sum -c - >/dev/null || { echo "!! vc_redist.x64.exe sha mismatch" >&2; exit 1; }
echo "   vc_redist.x64.exe ok ($(du -h "$VCREDIST" | cut -f1))"

# ---- 2. the Aura layer -----------------------------------------------------
"$ENGINE_REPO/registry/install-registry.sh" "$ENGINE"
AURA_SRC="${QUICKOFFICE_AURA_DIR:-$ROOT/office/core/instdir/share/config}"
naura=0
for z in "$AURA_SRC"/images_aura.zip "$AURA_SRC"/images_aura_dark.zip; do
  [ -f "$z" ] && cp "$z" "$ENGINE/share/config/" && naura=$((naura+1))
done
if [ "$naura" -lt 2 ]; then
  echo "!! Aura icon theme zips not found under $AURA_SRC — SymbolStyle=aura would" >&2
  echo "!! silently fall back. Set QUICKOFFICE_AURA_DIR or build the Linux engine." >&2
  exit 1
fi
echo "   aura layer: registry overlay + $naura icon theme zips"

# ---- 3. licences -----------------------------------------------------------
mkdir -p "$ENGINE/licenses"
cp "$ENGINE_REPO/NOTICE" "$ENGINE_REPO/LICENSING.md" "$ENGINE/"
cp "$ENGINE_REPO"/licenses/* "$ENGINE/licenses/"

# ---- 4. the three installers ----------------------------------------------
python3 "$HERE/make-windows-installers.py" "$WORK/nsi"
EST_KB="$(du -sk "$ENGINE" | cut -f1)"
for slug in quick-document quick-spreadsheet quick-presentation; do
  EXE="$(python3 -c "print(''.join(w.capitalize() for w in '$slug'.split('-')))")"
  ICO="$WORK/$slug.ico"
  convert "$ROOT/publish/icons/$slug.png" -define icon:auto-resize=256,128,64,48,32,16 "$ICO"
  makensis -V2 \
    -DENGINE_PAYLOAD="$ENGINE" \
    -DENGINE_VERSION="$LOVER" \
    -DDISPLAYVERSION="$DISPLAYVER" \
    -DVIVERSION="$LOVER.0" \
    -DESTSIZE_KB="$EST_KB" \
    -DVCREDIST="$VCREDIST" \
    -DICOFILE="$ICO" \
    -DLAUNCHER="$ENGINE_REPO/packaging/launchers/$slug.cmd" \
    -DLICENSEFILE="$ENGINE_REPO/licenses/MPL-2.0.txt" \
    -DNOTICEFILE="$ENGINE_REPO/NOTICE" \
    -DOUTFILE="$OUT/$EXE-Setup.exe" \
    "$WORK/nsi/$EXE.nsi"
  echo "   $(du -h "$OUT/$EXE-Setup.exe" | cut -f1)  $OUT/$EXE-Setup.exe"
done
