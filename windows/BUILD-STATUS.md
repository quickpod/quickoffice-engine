# Quick Office on Windows — build status and how to resume

**Last updated: 2026-08-13.** Written mid-build so work can resume after a
reboot / disk change.

Build host: **STORAGESERVER**, `ssh winbox-direct` (`sansan.dosvak.com:22`,
user Administrator). Build tree `D:\quickoffice\core`, Cygwin at
`D:\quickoffice\cygwin64`.

---

## Where it got to

The Linux side is **done and published** (26.8.1.0.0). This file is only about
Windows.

| Stage | State |
|---|---|
| VS 2022 Build Tools + Cygwin + pkgconf | **done** |
| **ATL component** | **done** — was the hard blocker, see below |
| configure (`autogen.sh`) | **done** — branding + ATL detected |
| `make` | **~90% — soffice.exe built, instdir 313 MB**, still failing on a few external projects |
| Thin `.exe` installers | not started |
| Engine upload to r2.quickopen.ai | not started |
| Windows artifacts on the three portal listings | not started |

## Resume

```bash
ssh winbox-direct
# then, inside Cygwin:
D:\quickoffice\cygwin64\bin\bash.exe --login
cd /cygdrive/d/quickoffice/core
make PARALLELISM=8 -j8            # incremental; safe to re-run
```

Re-running `autogen.sh` is **not** needed and is actively undesirable — it
regenerates `config_host.mk` and undoes the ATL path fixup. If you must
reconfigure, run `windows/fix-config-paths.sh` immediately afterwards
(`build-windows-engine.ps1` already chains the two correctly).

## The two root causes that cost the most, both fixed

### 1. Compiler paths must be Windows-form, not `/cygdrive/...`

`configure` decides how to spell every tool path from one probe
(`configure.ac`, `win_short_path_for_make`):

```
make -v | grep 'Built for Windows'   →  GNUMAKE_WIN_NATIVE=TRUE
    TRUE : C:/PROGRA~2/.../cl.exe      (Windows form)
    else : /cygdrive/c/PROGRA~2/...    (Cygwin only)
```

We build with **Cygwin make**, so everything comes out cygdrive-flavoured.
That is fine for anything consumed *by make*, and fatal for anything pasted
into a **native tool's command line** — `cl.exe` and `link.exe` have never
heard of `/cygdrive`. It fails ~30 min in, inside an external project, as:

```
Error: could not create process ""/cygdrive/c/.../cl.exe" ...": 2
```

because `solenv/gcc-wrappers/wrapper.cxx` is a native Win32 binary doing
`CreateProcess(nullptr, "\"$REAL_BUILD_CC\" ...")`.

Two different fixes, because the variables behave differently:

- `CC` / `CXX` — **preset in `autogen.input`** (8.3 short form).
  configure only derives them `if test -z "$CC"`, so a preset wins.
- `ATL_INCLUDE` / `ATL_LIB` — computed **unconditionally**, so a preset is
  overwritten. `windows/fix-config-paths.sh` rewrites them in the generated
  `config_host.mk` after autogen. This edits a build artifact, not core source,
  so `patches/` stays empty and rebasing stays a plain `git rebase`.

**Why not just use a native Win32 make** (upstream's own answer)? Tried it. It
fixes the spelling globally but breaks the autotools external projects (libffi
dies in its recursive `man`/`testsuite` pass) and, in a non-interactive
session, exhausts the session-0 desktop heap so every spawn fails with
`0xC0000142`. Cygwin make has neither problem.

### 2. ATL was missing — and the install failure was a quoting bug

`extensions/source/activex` is gated only on `OS=WNT` + `COM=MSC`; there is no
`--disable-atl`/`--disable-activex` in this version, so ATL genuinely must be
installed (skipping it would mean patching core).

Installing it failed repeatedly with `87 ERROR_INVALID_PARAMETER` and "An
installed product matching the following parameters cannot be found". Neither
message points at the real cause. The installer log did:

```
Parsed command line options: ... --installPath C:\Program --norestart ...
```

`Start-Process -ArgumentList` **does not quote array elements containing
spaces**, so `C:\Program Files (x86)\...` split at the first space. Quote the
path and it installs first try. (Also: `--wait` is a *bootstrapper* flag;
`setup.exe` rejects it with 87.)

Working command:

```powershell
$a = @("modify","--installPath","`"$path`"",
       "--productId","Microsoft.VisualStudio.Product.BuildTools",
       "--channelId","VisualStudio.17.Release",
       "--add","Microsoft.VisualStudio.Component.VC.ATL",
       "--includeRecommended","--quiet","--norestart")
Start-Process $setup -ArgumentList $a -Wait -PassThru -NoNewWindow
```

`Microsoft.VisualStudio.Component.VC.ATL` is now in
`provision-windows-build.ps1`, so a fresh host gets it from the start.

*Note for the record:* the host was rebooted on the theory that pending-reboot
flags were blocking the installer. They were set, but that was **not** the
cause — the quoting was. The reboot was harmless but unnecessary.

## Open issue — `Error 127` on python3/gpgmepp/liblangtag

Still failing at the tail of the build:

```
make[1]: *** [external/python3/ExternalPackage_python3.mk:186: .../Lib/unittest/suite.py] Error 127
```

The recipe is just `chmod 644 <file> && touch <file>`. Both binaries exist, the
file exists, and **the identical command succeeds when run by hand** — so this
is not tooling.

Best current explanation: **Cygwin's `ulimit -u` is 256** on this host and each
parallel job spawns a shell *plus* a tool, so bursts exhaust the process table;
the failed fork surfaces as "command not found" (127). This is very likely the
same underlying cause as the earlier `0xC0000142` spawn failures.

Dropping to `-j8` reduced but did not eliminate it. **`ulimit -u unlimited` and
`ulimit -u 4096` both silently failed to raise the limit (still 256)** — that is
the next thing to attack. Options not yet tried:

- Raise Cygwin's process limit properly (`CYGWIN` env / registry
  `max_procs`-style tuning), or run the build from a real interactive session
  rather than over the OpenSSH service (session 0).
- `make PARALLELISM=1 -j1` for the remaining external projects — slow but it
  sidesteps the limit entirely, and only a handful of targets remain.
- Retry-loop the tail: these targets are idempotent, so simply re-running
  `make` repeatedly makes progress each time.

Note `LibreOffice`'s top-level Makefile re-invokes the gbuild submake with
`-j $(PARALLELISM)` (fixed at 28 by `--with-parallelism`), so `-j8` alone is
ignored — **`PARALLELISM=8` must be passed on the command line**.

## Other things already paid for

- **Long builds must not run over a plain ssh command.** Windows OpenSSH kills
  the process tree on disconnect. A scheduled task with PowerShell `*>>`
  redirection *deadlocks* (0% CPU, no `workdir`). `setsid` breaks Cygwin process
  creation outright (`0xC0000142`). What works: `nohup bash -c '...' &` +
  `disown` from a Cygwin login shell, output redirected to a file.
- **Do not judge success by exit code alone.** Running the build through
  `powershell.exe` redirected with no console throws a
  `SetConsoleWindowTitle` HostException *after* the build, reporting failure for
  a build that succeeded. The resume path records `SOFFICE=yes|no` alongside
  `EXIT=` in `D:\quickoffice\make.done`.
- `git config --global --add safe.directory /cygdrive/d/quickoffice/core` —
  otherwise git-driven build steps hit "dubious ownership".

## Next after the build lands

1. `make PARALLELISM=8 -j8` to completion, confirm `instdir/program/soffice.exe`
   runs and reports **Quick Office**.
2. `packaging/make-installers.py` → three thin `.exe` installers that download
   the engine from r2.quickopen.ai, SHA-256 + Authenticode verified, refcounted
   under `HKLM\Software\QuickOpen\QuickOffice\Apps`.
3. Upload the engine payload to r2.quickopen.ai.
4. Add the Windows artifacts to the three quickopen.ai listings.
