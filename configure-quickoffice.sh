#!/usr/bin/env bash
# Configure the Quick Office engine build from the LibreOffice source tree.
#
#   quickoffice/configure-quickoffice.sh
#
# Everything that makes this OUR product rather than a LibreOffice build is
# here, and all of it uses upstream's own supported knobs — no patching of the
# build system, so rebasing onto a newer LibreOffice stays cheap:
#
#   --with-product-name   the name baked into the binaries, window titles,
#                         About box, installer paths and .desktop files
#   --with-vendor         the vendor line in Help > About
#   --with-branding       our splash / About logo / app logo / progress bar
#
# The disable flags are not taste, they are AIQuick product requirements:
#   --disable-online-update   req #3  no auto-update of any kind
#   --disable-breakpad        req #2  no crash-report upload, zero egress
#   --disable-extension-update  ditto — nothing checks a remote on its own
#
# Java is dropped because we ship Writer/Calc/Impress, not Base; it costs a JDK
# dependency and a large slice of build time for features we do not ship.
#
# Skia (the GPU/Vulkan renderer) is the one component LibreOffice insists on
# building with CLANG, not GCC — hence the separate LO_CLANG_* pins. It has to
# be clang 16 or newer: clang 15 cannot parse GCC 13's libstdc++ <chrono>
# (`call to consteval function _S_fractional_width is not a constant
# expression`) and the Skia build dies on it. clang-18 comes from apt.llvm.org.
# The alternative was --disable-skia, which would have cost GPU-accelerated
# rendering across the whole suite; not worth it to dodge one apt line.
#
# CC/CXX are pinned to GCC 13: LibreOffice 26.8 refuses anything older than 13,
# and this box's default is 11.4 (Ubuntu 22.04). gcc-13 comes from the
# ubuntu-toolchain-r/test PPA; it is a build-time dependency only — nothing
# about it reaches the shipped binaries beyond the usual libstdc++ runtime.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CORE="$(cd "$HERE/../core" && pwd)"
BRANDING="$HERE/branding"

PRODUCT_NAME="Quick Office"
VENDOR="QuickOpen (quickopen.ai)"

[ -f "$BRANDING/intro.png" ] || { echo "branding missing — run branding/make-branding.py"; exit 1; }

cd "$CORE"
# Both caches live INSIDE the office tree, not under $HOME. The build runs as
# an unprivileged `qobuild` user (LibreOffice's Makefile refuses to build as
# root, rightly — install steps can scribble outside the tree), and that user
# has no home worth writing to. Keeping them here also means one chown covers
# everything the build touches.
export CCACHE_DIR="${CCACHE_DIR:-$HERE/../.ccache}"
mkdir -p "$CCACHE_DIR"
ccache -M 40G >/dev/null 2>&1 || true

cat > autogen.input <<EOF
--with-product-name=$PRODUCT_NAME
--with-vendor=$VENDOR
--with-branding=$BRANDING
--enable-release-build
--disable-online-update
--disable-breakpad
--disable-extension-update
--without-java
--disable-firebird-sdbc
--disable-postgresql-sdbc
--without-doxygen
--enable-ccache
--with-parallelism=$(nproc)
--disable-dependency-tracking
--without-system-libs
CC=gcc-13
CXX=g++-13
LO_CLANG_CC=clang-18
LO_CLANG_CXX=clang++-18
--with-external-tar=$HERE/../externals
EOF

mkdir -p "$HERE/../externals"
echo "== autogen.input =="
cat autogen.input
echo
exec ./autogen.sh
