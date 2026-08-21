#!/usr/bin/env bash
# Build the Quick Office debs: one engine, three faces.
#
#   packaging/build-debs.sh [instdir] [outdir]
#
# The shared-engine shape in packaging terms:
#
#   quickoffice-engine            ~390 MB   the built LibreOffice-derived suite
#                                           in /opt/quickoffice, plus the Aura
#                                           registry overlay and icon theme
#   quickopen-quick-document      ~40 KB    launcher + .desktop + icon,
#   quickopen-quick-spreadsheet             Depends: quickoffice-engine
#   quickopen-quick-presentation
#
# So the first app a user installs pulls the engine once and the other two are
# free. That is the whole reason apt exists, and it is why these are four
# packages rather than three fat ones.
#
# The app debs are named quickopen-<slug> to match every other app in the
# AIQuick repo; the engine is NOT quickopen-prefixed because it is a runtime,
# not something a user installs on purpose.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENGINE_REPO="$(cd "$HERE/.." && pwd)"
REPOS="$(cd "$ENGINE_REPO/.." && pwd)"
INSTDIR="${1:-$REPOS/../office/core/instdir}"
OUT="${2:-$ENGINE_REPO/dist}"

VERSION="$(awk -F= '/^version=/{print $2}' "$ENGINE_REPO/pin.txt" | tr -d ' ')"
[ -n "$VERSION" ] || { echo "no version in pin.txt"; exit 1; }
# LibreOffice's own version is the engine's version; our packaging revision is
# appended so a rebuild with no upstream change is still a new deb.
REV="${QUICKOFFICE_DEB_REV:-1}"
DEB_VERSION="${VERSION}-${REV}"

[ -x "$INSTDIR/program/soffice" ] || { echo "no engine at $INSTDIR - build first"; exit 1; }
command -v dpkg-deb >/dev/null || { echo "dpkg-deb missing"; exit 1; }
rm -rf "$OUT" && mkdir -p "$OUT"

say() { printf '== %s\n' "$*"; }

# ---------------------------------------------------------------- the engine
say "quickoffice-engine $DEB_VERSION"
STAGE="$OUT/stage-engine"
OPT="$STAGE/opt/quickoffice"
mkdir -p "$OPT" "$STAGE/DEBIAN" "$STAGE/usr/share/doc/quickoffice-engine"

cp -a "$INSTDIR/." "$OPT/"
# The Aura layer: registry overlay + icon theme. Both are just files in the
# install tree - no build integration, which is what makes them survive an
# engine rebase untouched.
#
# The .xcd compilation lives in registry/install-registry.sh, NOT inline here.
# It has to emit <dependency file="main"/>, and a second copy of that logic is
# exactly how you end up shipping an overlay that upstream silently overrides.
"$ENGINE_REPO/registry/install-registry.sh" "$OPT"

# The brand layer, applied to the STAGED tree rather than trusted from the
# source build. configure's --with-branding silently keeps the upstream asset
# for any brand file the branding dir lacks, and the splash geometry in
# progress.conf only ever reached the packaged installer's sofficerc, never
# the instdir we cp -a from. Both were true of every deb shipped before
# 2026-08-21. Running it here makes the deb's branding a property of the
# package, and it is idempotent when the build did get it right.
"$ENGINE_REPO/branding/install-branding.sh" "$OPT" "Quick Office" "$VERSION"

INSTALLED_SIZE=$(du -sk "$STAGE" | cut -f1)
cat > "$STAGE/DEBIAN/control" <<EOF
Package: quickoffice-engine
Version: $DEB_VERSION
Section: editors
Priority: optional
Architecture: amd64
Maintainer: QuickOpen <help@quickpod.io>
Installed-Size: $INSTALLED_SIZE
Depends: libc6, libstdc++6, libx11-6, libxext6, libxrender1, libcairo2, libcups2, libfontconfig1, libfreetype6, libglib2.0-0, libnss3, libdbus-1-3
Recommends: fonts-liberation, fonts-dejavu-core
Provides: quickoffice
Description: Quick Office engine (shared runtime)
 The shared document engine behind Quick Document, Quick Spreadsheet and
 Quick Presentation. Installing any one of those pulls this in once.
 .
 This is a derivative of LibreOffice, rebranded and rethemed by QuickOpen.
 It is not LibreOffice and is not endorsed by or affiliated with The Document
 Foundation. Engine licence: MPL-2.0. Source and attribution:
 https://github.com/quickpod/quickoffice-engine
EOF
cp "$ENGINE_REPO/NOTICE" "$STAGE/usr/share/doc/quickoffice-engine/NOTICE"
cp "$ENGINE_REPO/LICENSING.md" "$STAGE/usr/share/doc/quickoffice-engine/"
cp -a "$ENGINE_REPO/licenses" "$STAGE/usr/share/doc/quickoffice-engine/"
dpkg-deb --build --root-owner-group -Zxz "$STAGE" \
  "$OUT/quickoffice-engine_${DEB_VERSION}_amd64.deb" >/dev/null
rm -rf "$STAGE"
echo "   $(du -h "$OUT/quickoffice-engine_${DEB_VERSION}_amd64.deb" | cut -f1)"

# ------------------------------------------------------------- the three faces
for slug in quick-document quick-spreadsheet quick-presentation; do
  APP="$REPOS/$slug"
  [ -d "$APP" ] || { echo "!! missing app repo $APP"; continue; }
  name="$(python3 -c "import json;print(json.load(open('$APP/.quickopen.json'))['name'])")"
  tagline="$(python3 -c "import json;print(json.load(open('$APP/.quickopen.json'))['tagline'])")"
  say "quickopen-$slug $DEB_VERSION  ($name)"

  S="$OUT/stage-$slug"
  mkdir -p "$S/DEBIAN" "$S/usr/bin" "$S/usr/share/applications" \
           "$S/usr/share/icons/hicolor/512x512/apps" \
           "$S/usr/share/icons/hicolor/scalable/apps" \
           "$S/usr/share/doc/quickopen-$slug"
  install -m 0755 "$APP/bin/$slug" "$S/usr/bin/$slug"
  install -m 0644 "$APP/applications/$slug.desktop" "$S/usr/share/applications/"
  # Both names. The desktop entry says Icon=quickopen-<slug> (the themed name
  # AIQuick ships), and the OS build used to sed that in AFTER install — which
  # meant any package upgrade silently reverted it, along with anything else
  # patched into these package-owned files. Ship the alias from the package
  # instead: the icon resolves on Quick OS and on stock Ubuntu alike, and an
  # upgrade cannot undo it.
  for n in "$slug" "quickopen-$slug"; do
    [ -f "$APP/$slug.png" ] && install -m 0644 "$APP/$slug.png" \
        "$S/usr/share/icons/hicolor/512x512/apps/$n.png"
    [ -f "$APP/$slug.svg" ] && install -m 0644 "$APP/$slug.svg" \
        "$S/usr/share/icons/hicolor/scalable/apps/$n.svg"
  done
  install -m 0644 "$ENGINE_REPO/NOTICE" "$S/usr/share/doc/quickopen-$slug/NOTICE"

  cat > "$S/DEBIAN/control" <<EOF
Package: quickopen-$slug
Version: $DEB_VERSION
Section: editors
Priority: optional
Architecture: all
Maintainer: QuickOpen <help@quickpod.io>
Installed-Size: $(du -sk "$S" | cut -f1)
Depends: quickoffice-engine (>= $VERSION)
Description: $name
 $tagline
 .
 A face over the shared Quick Office engine, which is a derivative of
 LibreOffice. Not endorsed by or affiliated with The Document Foundation.
EOF
  # Refresh the desktop + icon + MIME caches so the app appears and its file
  # types bind without a logout. Failure is never fatal: a package that breaks
  # `apt install` because a cache tool is absent is worse than a stale cache.
  cat > "$S/DEBIAN/postinst" <<'EOF'
#!/bin/sh
set -e
if [ "$1" = "configure" ]; then
  update-desktop-database -q /usr/share/applications 2>/dev/null || true
  gtk-update-icon-cache -qf /usr/share/icons/hicolor 2>/dev/null || true
fi
exit 0
EOF
  cp "$S/DEBIAN/postinst" "$S/DEBIAN/postrm"
  chmod 0755 "$S/DEBIAN/postinst" "$S/DEBIAN/postrm"

  dpkg-deb --build --root-owner-group -Zxz "$S" \
    "$OUT/quickopen-${slug}_${DEB_VERSION}_all.deb" >/dev/null
  rm -rf "$S"
  echo "   $(du -h "$OUT/quickopen-${slug}_${DEB_VERSION}_all.deb" | cut -f1)"
done

say "built into $OUT"
ls -1 "$OUT"/*.deb | while read -r f; do printf '   %-46s %s\n' "$(basename "$f")" "$(du -h "$f" | cut -f1)"; done
cat <<EOF

Next:
  lintian $OUT/*.deb                     sanity (optional)
  ca/scripts/build-usi.sh                wrap each app deb as a signed .usi
  ca/scripts/build-apt-repo.sh --publish push all four into the AIQuick repo
EOF
