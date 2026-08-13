#!/bin/bash
# Install Quick Office on the AIQuick VM and prove it actually works.
#
# Runs INSIDE the guest, shipped there by vm-run.ps1. Expects the four debs to
# already be in /tmp/quickoffice.
#
# This is a real acceptance test, not a smoke test: apt has to resolve the
# engine dependency, the launchers have to exist on PATH, the engine has to
# start headless and convert a document, and the desktop entries and file
# associations have to be registered. Anything less and "it installed" would
# be the only thing we learned.
set -uo pipefail
DEBS=/tmp/quickoffice
PASS=0; FAIL=0
ok()   { echo "  PASS  $*"; PASS=$((PASS+1)); }
bad()  { echo "  FAIL  $*"; FAIL=$((FAIL+1)); }
section() { echo; echo "== $*"; }

section "before"
echo "  free on /: $(df -h / | awk 'NR==2{print $4}')"
echo "  $(cat /etc/os-release | grep PRETTY_NAME | cut -d= -f2- | tr -d '\"')"

section "install"
ls -1 "$DEBS"/*.deb 2>/dev/null || { echo "  no debs in $DEBS"; exit 2; }
# apt install of local files resolves inter-deb dependencies; dpkg -i alone
# would fail on the engine dependency and leave a half-configured system.
sudo apt-get install -y --no-install-recommends "$DEBS"/*.deb 2>&1 | tail -12

section "packages"
for p in quickoffice-engine quickopen-quick-document quickopen-quick-spreadsheet quickopen-quick-presentation; do
  v=$(dpkg-query -W -f='${Version} ${Status}' "$p" 2>/dev/null)
  case "$v" in
    *"install ok installed") ok "$p ${v%% *}" ;;
    *) bad "$p not installed ($v)" ;;
  esac
done

section "launchers on PATH"
for c in quick-document quick-spreadsheet quick-presentation; do
  command -v "$c" >/dev/null && ok "$c -> $(command -v $c)" || bad "$c missing"
done

section "engine"
SO=/opt/quickoffice/program/soffice
[ -x "$SO" ] && ok "engine present at $SO" || bad "engine missing"
# The product name is what the rebrand is FOR: if this says LibreOffice the
# --with-product-name build flag did not take.
VER=$("$SO" --version 2>/dev/null | head -1)
echo "  version string: ${VER:-<none>}"
case "$VER" in
  *"Quick Office"*) ok "rebranded product name" ;;
  *LibreOffice*)    bad "still says LibreOffice - branding did not take" ;;
  *)                bad "no version string" ;;
esac

section "headless conversion (the engine really runs)"
WORK=$(mktemp -d)
printf 'Quick Office acceptance test\nSecond paragraph.\n' > "$WORK/in.txt"
timeout 180 "$SO" --headless --norestore \
  -env:UserInstallation="file://$WORK/profile" \
  --convert-to pdf --outdir "$WORK" "$WORK/in.txt" >/dev/null 2>&1
if [ -s "$WORK/in.pdf" ]; then
  ok "converted txt -> pdf ($(stat -c%s "$WORK/in.pdf") bytes)"
else
  bad "headless conversion produced nothing"
fi
printf 'Region,Q1,Q2\nNorth,41200,44211\nSouth,38600,42474\n' > "$WORK/data.csv"
timeout 180 "$SO" --headless --norestore \
  -env:UserInstallation="file://$WORK/profile" \
  --convert-to xlsx --outdir "$WORK" "$WORK/data.csv" >/dev/null 2>&1
[ -s "$WORK/data.xlsx" ] && ok "csv -> xlsx ($(stat -c%s "$WORK/data.xlsx" 2>/dev/null) bytes, Microsoft filter works)" \
                        || bad "xlsx filter failed"

section "desktop integration"
for s in quick-document quick-spreadsheet quick-presentation; do
  f=/usr/share/applications/$s.desktop
  [ -f "$f" ] && ok "$s.desktop" || bad "$s.desktop missing"
done
for mime in application/vnd.openxmlformats-officedocument.wordprocessingml.document \
            application/vnd.openxmlformats-officedocument.spreadsheetml.sheet \
            application/vnd.openxmlformats-officedocument.presentationml.presentation; do
  d=$(xdg-mime query default "$mime" 2>/dev/null)
  case "$d" in
    quick-*) ok "$(echo $mime | sed 's/.*\.//') -> $d" ;;
    *)       bad "$(echo $mime | sed 's/.*\.//') -> ${d:-unassigned}" ;;
  esac
done

section "aura theme layer"
for x in /opt/quickoffice/share/registry/quickoffice.xcd \
         /opt/quickoffice/share/registry/quickoffice-toolbarmode.xcd; do
  [ -f "$x" ] && ok "$(basename $x)" || bad "$(basename $x) missing"
done
[ -f /opt/quickoffice/share/config/images_aura.zip ] \
  && ok "aura icon theme packed" || bad "images_aura.zip missing"

section "footprint"
echo "  engine on disk: $(du -sh /opt/quickoffice 2>/dev/null | cut -f1)"
echo "  free on /:      $(df -h / | awk 'NR==2{print $4}')"

rm -rf "$WORK"
# The debs are 200 MB on a 9.8 GB disk; they have served their purpose.
rm -f "$DEBS"/*.deb 2>/dev/null
echo "  free after cleanup: $(df -h / | awk 'NR==2{print $4}')"
echo
echo "== $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
