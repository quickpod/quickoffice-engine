#!/usr/bin/env bash
# Compile the Aura registry overlay into share/registry/*.xcd.
#
#   registry/install-registry.sh <instdir>
#
# THE DEPENDENCY LINE IS THE WHOLE TRICK. LibreOffice merges every .xcd in
# share/registry, but the merge ORDER decides who wins, and a file with no
# declared dependency is processed BEFORE main.xcd - so upstream's defaults
# land on top of ours and the overlay silently does nothing. That is exactly
# what happened the first time: the ribbon UI and the follow-the-system theme
# were configured correctly and simply never appeared.
#
# Upstream's own writer.xcd / calc.xcd all carry <dependency file="main"/>.
# Ours must too.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTDIR="${1:?usage: install-registry.sh <instdir>}"
DEST="$INSTDIR/share/registry"
[ -d "$DEST" ] || { echo "no share/registry under $INSTDIR"; exit 1; }

for xcu in "$HERE"/*.xcu; do
  base="$(basename "$xcu" .xcu)"
  out="$DEST/$base.xcd"
  {
    printf '<?xml version="1.0" encoding="UTF-8"?>\n'
    printf '<oor:data xmlns:oor="http://openoffice.org/2001/registry" '
    printf 'xmlns:xs="http://www.w3.org/2001/XMLSchema">\n'
    printf '  <dependency file="main"/>\n'
    tail -n +2 "$xcu"
    printf '</oor:data>\n'
  } > "$out"
  python3 -c "import xml.dom.minidom,sys; xml.dom.minidom.parse('$out')" \
    || { echo "!! $out is not well-formed"; exit 1; }
  printf '   %-34s %6d B\n' "$base.xcd" "$(stat -c%s "$out")"
done
echo "== overlay installed into $DEST"
