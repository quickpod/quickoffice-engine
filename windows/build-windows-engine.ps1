<#
.SYNOPSIS
  Build the Quick Office engine on Windows, from source.

.DESCRIPTION
  The Windows twin of configure-quickoffice.sh. Same product, same branding,
  same AIQuick product rules - a different toolchain underneath, because
  LibreOffice on Windows is MSVC + Cygwin and nothing else.

  This script is the Windows-side wrapper: it locates Cygwin, writes the
  autogen input, and hands off to bash. The actual build must run inside a
  Cygwin login shell, so everything after the handoff is POSIX.

  Three Windows-only differences from the Linux build, each with a reason:

    * NO CCACHE. ccache does not usefully wrap MSVC; leaving it on just adds a
      layer that misses every time.
    * --with-package-format=installed. We do NOT want LibreOffice's own MSI:
      the QuickOpen fleet ships Inno Setup installers signed with our CA, and
      Inno wants a plain installed tree to package. This produces exactly that.
    * A SHORT, SPACE-FREE PATH. The build shells out constantly and MSVC still
      trips over long paths; D:\quickoffice\core keeps us clear of both.

.PARAMETER DataDrive
  Where the build tree lives. Must match provision-windows-build.ps1. Default D.

.PARAMETER Jobs
  Parallelism. Defaults to the logical processor count.

.PARAMETER ConfigureOnly
  Stop after configure - useful for checking the branding actually took before
  committing hours to a compile.
#>
[CmdletBinding()]
param(
    [string]$DataDrive = "D",
    [int]$Jobs = 0,
    [switch]$ConfigureOnly
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

function Say($m) { Write-Host "== $m" -ForegroundColor Cyan }
function Ok($m)  { Write-Host "   $m" -ForegroundColor Green }

$Root    = "${DataDrive}:\quickoffice"
$CygRoot = Join-Path $Root "cygwin64"
$CygBash = Join-Path $CygRoot "bin\bash.exe"
$Core    = Join-Path $Root "core"
$Engine  = Join-Path $Root "quickoffice-engine"
if (-not (Test-Path $CygBash)) { throw "Cygwin missing - run provision-windows-build.ps1 first" }
if (-not (Test-Path $Engine))  { throw "engine repo not at $Engine - clone quickpod/quickoffice-engine there" }
if ($Jobs -le 0) { $Jobs = [int]$env:NUMBER_OF_PROCESSORS }

# ---------------------------------------------------------------- 1. source
Say "LibreOffice source (pinned)"
$pin = @{}
Get-Content (Join-Path $Engine "pin.txt") | Where-Object { $_ -match "^\s*([a-z]+)=(.*)$" } | ForEach-Object {
    if ($_ -match "^\s*([a-z]+)=(.*)$") { $pin[$Matches[1]] = $Matches[2].Trim() }
}
Ok ("branch " + $pin.branch + " @ " + $pin.commit.Substring(0,12) + "  (LibreOffice " + $pin.version + ")")

# No null-conditional (?.) here: that is PowerShell 7 syntax and Windows ships
# 5.1, where it is a parse error - the script dies before it runs a line.
$gitCmd = Get-Command git -ErrorAction SilentlyContinue
if ($gitCmd) { $git = $gitCmd.Source } else { $git = "$env:ProgramFiles\Git\cmd\git.exe" }
if (-not (Test-Path $git)) { throw "git not found - run provision-windows-build.ps1" }
if (-not (Test-Path $Core)) {
    Ok "cloning (about 2 GB)"
    # -c core.autocrlf=false -c core.eol=lf: without these Git for Windows
    # checks the tree out with CRLF and every build script becomes unrunnable.
    & $git -c core.autocrlf=false -c core.eol=lf clone --depth 1 `
      --branch $pin.branch $pin.upstream $Core
    & $git -C $Core config core.autocrlf false
    & $git -C $Core config core.eol lf
}
& $git -C $Core fetch --depth 1 origin $pin.branch | Out-Null
& $git -C $Core checkout -q -B quickoffice $pin.commit
Ok ("core at " + (& $git -C $Core log --oneline -1))

$patches = Get-ChildItem (Join-Path $Engine "patches") -Filter *.patch -ErrorAction SilentlyContinue
if ($patches) { foreach ($p in $patches) { & $git -C $Core apply $p.FullName; Ok ("patch " + $p.Name) } }
else { Ok "no patches - every customisation is in the overlay" }

# THE COMPILER PATH MUST BE WINDOWS-FORM. This is the fix for the failure that
# killed the build ~30 min in, inside libgpg-error:
#
#     Error: could not create process ""/cygdrive/c/.../cl.exe" ...": 2
#
# solenv/gcc-wrappers/wrapper.cxx is a NATIVE Win32 binary and does
# CreateProcess(nullptr, "\"$REAL_BUILD_CC\" ..."). REAL_BUILD_CC comes from
# CC_FOR_BUILD, and Win32 cannot resolve a /cygdrive path, so it fails with
# error 2 while printing a command line that looks perfectly fine.
#
# configure normally derives CC itself and spells it /cygdrive/... whenever
# make is Cygwin's (configure.ac, win_short_path_for_make). Upstream's answer
# is a native Win32 make, which flips that to C:/PROGRA~2/... - but a native
# make then breaks the autotools external projects (libffi dies in its
# recursive man/testsuite pass) and, under a non-interactive session, exhausts
# the session-0 desktop heap at high -j and every spawn fails with 0xC0000142.
# Cygwin make has neither problem.
#
# So: keep Cygwin make, and preset CC/CXX in 8.3 Windows form. configure only
# derives them `if test -z "$CC"`, so presetting is explicitly supported and is
# a far smaller deviation than swapping the build's make.
$clExe = Get-ChildItem "${env:ProgramFiles(x86)}\Microsoft Visual Studio\2022\BuildTools\VC\Tools\MSVC" `
            -Filter cl.exe -Recurse -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -match '\\bin\\Hostx64\\x64\\cl\.exe$' } |
            Select-Object -First 1
if (-not $clExe) { throw "cl.exe not found - run provision-windows-build.ps1" }
# 8.3 short path: the real path has spaces, and these values are pasted into
# command lines all over the build where quoting is not guaranteed.
$fso = New-Object -ComObject Scripting.FileSystemObject
$clShort = ($fso.GetFile($clExe.FullName).ShortPath) -replace '\\','/'
Say "compiler: $clShort"

# ------------------------------------------------------------- 2. autogen.input
# Written from Windows but consumed by Cygwin, so paths are POSIX. Everything
# here mirrors configure-quickoffice.sh; see that file for why each flag exists.
Say "configure input"
$cygEngine = "/cygdrive/" + $DataDrive.ToLower() + "/quickoffice/quickoffice-engine"
$cygRootP  = "/cygdrive/" + $DataDrive.ToLower() + "/quickoffice"
$lines = @(
    "--with-product-name=Quick Office",
    "--with-vendor=QuickOpen (quickopen.ai)",
    "--with-branding=$cygEngine/branding",
    "--enable-release-build",
    "--disable-online-update",
    "--disable-breakpad",
    "--disable-extension-update",
    "--without-java",
    # The CLI (.NET) UNO bindings need al.exe, the .NET Framework assembly
    # linker, which is a separate Visual Studio component. We do not ship .NET
    # bindings - Quick Office is three launchers over the engine - so the
    # dependency buys nothing but build time and another thing to install.
    "--disable-cli",
    "--disable-firebird-sdbc",
    "--disable-postgresql-sdbc",
    "--without-doxygen",
    "--disable-ccache",
    "--with-visual-studio=2022",
    "--with-package-format=installed",
    "--with-parallelism=$Jobs",
    "--disable-dependency-tracking",
    "--with-external-tar=$cygRootP/externals"
)

# PKG_CONFIG must point at the NATIVE pkgconf. Preset here rather than relying
# on configure's search, which looks only for the literal name
# "pkgconf-2.4.3.exe" that upstream's LODE toolchain ships and no release
# publishes.
$pk = Get-ChildItem "$env:ProgramFiles","${env:ProgramFiles(x86)}" -Filter "pkgconf*" `
          -Directory -ErrorAction SilentlyContinue |
          ForEach-Object { Get-ChildItem $_.FullName -Filter pkgconf.exe -Recurse -ErrorAction SilentlyContinue } |
          Select-Object -First 1
if (-not $pk) { throw "native pkgconf missing - run provision-windows-build.ps1" }
# C:\Program Files\... -> /cygdrive/c/Program Files/...
$pkCyg = "/cygdrive/" + $pk.FullName.Substring(0,1).ToLower() +
         ($pk.FullName.Substring(2) -replace "\\","/")
$lines += "PKG_CONFIG=$pkCyg"
$lines += "CC=$clShort"
$lines += "CXX=$clShort"
$inputPath = Join-Path $Core "autogen.input"
# LF, not CRLF: Set-Content would write CRLF, autogen.sh would read each option
# with a trailing carriage return, and configure would reject the lot.
[System.IO.File]::WriteAllText($inputPath, (($lines -join "`n") + "`n"),
    (New-Object System.Text.UTF8Encoding $false))
$lines | ForEach-Object { "   $_" }

# ------------------------------------------------------------------ 3. build
$cygCore = "/cygdrive/" + $DataDrive.ToLower() + "/quickoffice/core"


# A tree configured with cygdrive-style paths cannot be reused once the paths
# become Windows-style, so the derived output has to go. Do it ONLY when that
# stale spelling is actually on disk, so an ordinary re-run still resumes an
# interrupted build instead of starting over. externals/ is never touched: it
# is downloaded tarballs, unaffected by path format and slow to refetch.
$wipe = "if [ -f config_host.mk ] && ! grep -q '^export CC=C:' config_host.mk; then " +
        "echo '== stale cygdrive-format tree, clearing workdir/instdir'; rm -rf workdir instdir; fi"

# After autogen, rewrite the config_host.mk entries that a NATIVE tool consumes
# (ATL_INCLUDE -> cl.exe -I, ATL_LIB -> link.exe -LIBPATH). Cygwin make makes
# configure spell those /cygdrive/..., which cl.exe cannot resolve; the build
# then fails an hour in on a header that is plainly present. See
# fix-config-paths.sh for the full reasoning. Must run AFTER every autogen.
$fixPaths = " && $cygEngine/windows/fix-config-paths.sh $cygCore"
$make = if ($ConfigureOnly) { "" } else { " && make -j$Jobs" }
$cmd  = "mkdir -p $cygRootP/externals" +
        " && cd $cygCore && $wipe && ./autogen.sh$fixPaths$make"

Say $(if ($ConfigureOnly) { "running autogen only" } else { "running autogen + make -j$Jobs (hours)" })
$started = Get-Date
& $CygBash --login -c $cmd
$code = $LASTEXITCODE
$mins = [math]::Round(((Get-Date) - $started).TotalMinutes, 1)
if ($code -ne 0) { throw "build failed after $mins min (exit $code)" }

Say "done in $mins min"
if (-not $ConfigureOnly) {
    $inst = Join-Path $Core "instdir"
    if (Test-Path $inst) {
        $sz = [math]::Round(((Get-ChildItem $inst -Recurse -File -ErrorAction SilentlyContinue |
              Measure-Object Length -Sum).Sum / 1GB), 2)
        Ok "engine tree: $inst ($sz GB)"
        Ok "next: package with Inno (packaging\), then sign off-box"
    }
}
