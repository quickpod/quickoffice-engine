#!/usr/bin/env python3
r"""Dual-theme screenshots of Quick Document / Spreadsheet / Presentation.

Unlike the Python apps in the fleet, these are one native binary wearing three
faces, so the capture is X-level rather than tk-level: seed a throwaway user
profile with the theme we want, launch the engine into the right module with a
sample document, wait for a real window, and grab it.

Two details that are easy to get wrong and cost an afternoon each:

  * THE PROFILE IS THE THEME SWITCH. LibreOffice reads appearance from the user
    profile, not from an argument. A fresh profile per (app, theme) is seeded
    with registrymodifications.xcu before launch — which also guarantees the
    shots are of first-run state, not of whatever a previous run left behind.
  * WAIT FOR A WINDOW, NOT FOR A CLOCK. The first launch of a fresh profile
    builds caches and can take 20s; a later one takes 2s. Polling xdotool for
    the window id and then for it to stop resizing is the only reliable gate.

    capture-quickoffice.py [instdir] [outdir]
"""

import os
import shutil
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_INSTDIR = "/home/ubuntu/quickopen/office/core/instdir"
DEFAULT_OUT = "/home/ubuntu/quickopen/publish/screenshots"
DISPLAY = ":96"
SCREEN = "1680x1050x24"

APPS = [
    ("quick-document", "--writer", "survey-report.fodt"),
    ("quick-spreadsheet", "--calc", "revenue-by-region.fods"),
    ("quick-presentation", "--impress", "survey-findings.fodp"),
]

# 1 = Light, 2 = Dark (officecfg .../Common/Appearance/ApplicationAppearance).
# The shipped default is 0, Automatic — we pin it here only to photograph both
# sides of it deterministically.
APPEARANCE = {"light": 1, "dark": 2}

PROFILE = """<?xml version="1.0" encoding="UTF-8"?>
<oor:items xmlns:oor="http://openoffice.org/2001/registry"
 xmlns:xs="http://www.w3.org/2001/XMLSchema"
 xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
 <item oor:path="/org.openoffice.Office.Common/Appearance"><prop
  oor:name="ApplicationAppearance" oor:op="fuse"><value>{appearance}</value></prop></item>
 <item oor:path="/org.openoffice.Office.Common/Misc"><prop
  oor:name="SymbolStyle" oor:op="fuse"><value>{icons}</value></prop></item>
 <item oor:path="/org.openoffice.Office.Common/Misc"><prop
  oor:name="FirstRun" oor:op="fuse"><value>false</value></prop></item>
 <item oor:path="/org.openoffice.Office.Common/Misc"><prop
  oor:name="ShowTipOfTheDay" oor:op="fuse"><value>false</value></prop></item>
 <item oor:path="/org.openoffice.Office.UI.ToolbarMode"><prop
  oor:name="ActiveWriter" oor:op="fuse"><value>notebookbar.ui</value></prop></item>
 <item oor:path="/org.openoffice.Office.UI.ToolbarMode"><prop
  oor:name="ActiveCalc" oor:op="fuse"><value>notebookbar.ui</value></prop></item>
 <item oor:path="/org.openoffice.Office.UI.ToolbarMode"><prop
  oor:name="ActiveImpress" oor:op="fuse"><value>notebookbar.ui</value></prop></item>
 <item oor:path="/org.openoffice.Setup/Office"><prop
  oor:name="ooSetupInstCompleted" oor:op="fuse"><value>true</value></prop></item>
</oor:items>
"""


def sh(cmd, **kw):
    return subprocess.run(cmd, shell=isinstance(cmd, str),
                          capture_output=True, text=True, **kw)


def start_xvfb():
    if sh(["xdpyinfo", "-display", DISPLAY]).returncode == 0:
        return None
    p = subprocess.Popen(["Xvfb", DISPLAY, "-screen", "0", SCREEN, "-dpi", "96"],
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(2)
    return p


def seed_profile(root, theme, icons):
    user = os.path.join(root, "user")
    os.makedirs(user, exist_ok=True)
    with open(os.path.join(user, "registrymodifications.xcu"), "w",
              encoding="utf-8") as fh:
        fh.write(PROFILE.format(appearance=APPEARANCE[theme], icons=icons))


def wait_for_window(env, timeout=90):
    """Return the window id once one exists AND has stopped changing size."""
    end, last, stable = time.time() + timeout, None, 0
    while time.time() < end:
        r = subprocess.run(["xdotool", "search", "--onlyvisible", "--name", "."],
                           capture_output=True, text=True, env=env)
        ids = [i for i in r.stdout.split() if i.strip()]
        if ids:
            wid = ids[-1]
            g = subprocess.run(["xdotool", "getwindowgeometry", wid],
                               capture_output=True, text=True, env=env).stdout
            if g == last and g.strip():
                stable += 1
                if stable >= 3:
                    return wid
            else:
                stable = 0
            last = g
        time.sleep(1)
    return None


def capture(instdir, outdir, icons="aura"):
    soffice = os.path.join(instdir, "program", "soffice")
    if not os.path.isfile(soffice):
        print("no engine at", soffice, "- has the build finished?")
        return 1
    base_env = dict(os.environ, DISPLAY=DISPLAY, SAL_USE_VCLPLUGIN="gtk3",
                    LANG="en_US.UTF-8")
    # The shipped default is ApplicationAppearance=Automatic - follow the
    # desktop. So the two shots are taken under a light and a dark GTK theme
    # respectively, which photographs the behaviour we actually ship rather
    # than an override the user will never have set.
    GTK = {"dark": "Adwaita:dark", "light": "Adwaita"}
    rc = 0
    for slug, module, sample in APPS:
        dest = os.path.join(outdir, slug)
        os.makedirs(dest, exist_ok=True)
        for theme in ("dark", "light"):
            prof = tempfile.mkdtemp(prefix="qo-prof-")
            seed_profile(prof, theme, icons)
            doc = os.path.join(prof, sample)
            shutil.copy2(os.path.join(HERE, sample), doc)
            env = dict(base_env, GTK_THEME=GTK[theme])
            proc = subprocess.Popen(
                [soffice, module, "--norestore", "--nolockcheck",
                 "-env:UserInstallation=file://" + prof, doc],
                env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            wid = wait_for_window(env)
            if wid:
                subprocess.run(["xdotool", "windowsize", wid, "1600", "1000"],
                               env=env, capture_output=True)
                time.sleep(3)                    # let the ribbon lay out
                out = os.path.join(dest, "shot-1-%s.png" % theme)
                subprocess.run(["xdotool", "windowmove", wid, "0", "0"],
                               env=env, capture_output=True)
                time.sleep(1)
                g = subprocess.run(["import", "-display", DISPLAY,
                                    "-window", wid, out],
                                   capture_output=True, text=True)
                if g.returncode == 0 and os.path.isfile(out):
                    print("  wrote %s/%s" % (slug, os.path.basename(out)),
                          flush=True)
                else:
                    print("  !! grab failed for", slug, theme, g.stderr[:120])
                    rc = 1
            else:
                print("  !! no window for", slug, theme)
                rc = 1
            proc.terminate()
            try:
                proc.wait(timeout=20)
            except subprocess.TimeoutExpired:
                proc.kill()
            shutil.rmtree(prof, ignore_errors=True)
    return rc


def main():
    instdir = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_INSTDIR
    outdir = sys.argv[2] if len(sys.argv) > 2 else DEFAULT_OUT
    if not os.path.isfile(os.path.join(HERE, "survey-report.fodt")):
        subprocess.run([sys.executable, os.path.join(HERE, "make-samples.py")])
    x = start_xvfb()
    try:
        return capture(instdir, outdir)
    finally:
        if x is not None:
            x.terminate()


if __name__ == "__main__":
    sys.exit(main())
