#!/usr/bin/env bash
# Rewrite the config_host.mk paths that MUST be Windows-form, not Cygwin.
#
#   fix-config-paths.sh [core-dir]        default /cygdrive/d/quickoffice/core
#
# Run from inside Cygwin, AFTER autogen.sh and BEFORE make. Idempotent.
#
# WHY
# configure decides how to spell tool paths from one probe (configure.ac,
# win_short_path_for_make): if `make -v` says "Built for Windows" it emits
# C:/PROGRA~2/..., otherwise /cygdrive/c/PROGRA~2/... . We build with CYGWIN
# make on purpose - a native Win32 make breaks the autotools external projects
# (libffi dies in its recursive man/testsuite pass) and, in a non-interactive
# session, exhausts the session-0 desktop heap so every spawn fails with
# 0xC0000142. The cost of that choice is that everything through
# win_short_path_for_make comes out cygdrive-flavoured.
#
# That is harmless for anything consumed BY MAKE - Cygwin make and Cygwin bash
# both understand /cygdrive. It is fatal for anything pasted into a NATIVE tool's
# command line, because cl.exe and link.exe have never heard of /cygdrive:
#
#   ATL_INCLUDE -> cl.exe  -I...      "fatal error C1083: Cannot open include
#                                      file: 'atlbase.h'" - while the header is
#                                      demonstrably on disk, which is what makes
#                                      this so confusing to chase.
#   ATL_LIB     -> link.exe -LIBPATH:...
#
# CC/CXX have the same problem and are fixed differently, by presetting them in
# autogen.input (configure only derives those `if test -z "$CC"`). ATL_INCLUDE
# and ATL_LIB are computed unconditionally, so a preset is simply overwritten -
# the generated file has to be edited after the fact.
#
# This edits a BUILD ARTIFACT, not core source, so `patches/` stays empty and
# rebasing onto the next LibreOffice remains a plain git rebase.
#
# NOTE: re-running autogen.sh regenerates config_host.mk and undoes this. Any
# reconfigure must be followed by another run of this script.
set -euo pipefail

CORE="${1:-/cygdrive/d/quickoffice/core}"
cd "$CORE" || { echo "no core dir at $CORE"; exit 1; }
[ -f config_host.mk ] || { echo "config_host.mk missing - run autogen.sh first"; exit 1; }

changed=0
for v in ATL_INCLUDE ATL_LIB; do
  cur="$(sed -n "s|^export $v=||p" config_host.mk | head -1)"
  [ -n "$cur" ] || { echo "   $v not set (ATL may be disabled)"; continue; }
  case "$cur" in
    /cygdrive/*)
      # -ms: 8.3 short form. These land in command lines unquoted, and the real
      # paths contain spaces ("Program Files (x86)").
      new="$(cygpath -ms "$cur")"
      sed -i "s|^export $v=.*|export $v=$new|" config_host.mk
      echo "   $v -> $new"
      changed=$((changed + 1))
      ;;
    *) echo "   $v already Windows-form" ;;
  esac
done

# Prove the header is actually reachable through the value we just wrote,
# rather than trusting the rewrite.
inc="$(sed -n 's|^export ATL_INCLUDE=||p' config_host.mk | head -1)"
if [ -n "$inc" ]; then
  if [ -f "$(cygpath -u "$inc")/atlbase.h" ]; then
    echo "   atlbase.h reachable"
  else
    echo "!! atlbase.h NOT reachable via $inc"
    echo "   install ATL: setup.exe modify --installPath \"<path>\" --add Microsoft.VisualStudio.Component.VC.ATL --quiet --norestart"
    echo "   (quote the install path - Start-Process does not, and the VS"
    echo "    installer then reports a missing product for C:\\Program)"
    exit 1
  fi
fi

echo "   $changed path(s) rewritten"
