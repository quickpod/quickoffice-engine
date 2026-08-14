<#
.SYNOPSIS
  Provision a Windows machine to build the Quick Office engine from source.

.DESCRIPTION
  LibreOffice does not cross-compile. A Windows build needs MSVC and a Cygwin
  shell ON Windows, which is why this script exists: it turns a bare Windows 11
  box into a build host without anybody clicking through installers.

  It installs, all unattended:

    * Visual Studio 2022 Build Tools   -  MSVC v143 + Windows 11 SDK. Build Tools
      rather than the full IDE: same compiler, a fraction of the download, and
      nobody is going to open Visual Studio on a build box.
    * Cygwin (64-bit) + the package set LibreOffice's own build docs require.
      The build driver is GNU make under bash; that is not optional.
    * Git, on the Windows side, for checking out this repo.

  Everything bulky lands on the DATA drive (default D:) because a LibreOffice
  work tree is 40-60 GB and Windows system drives are usually the small one.

  Safe to re-run: every step checks for what it installs first.

.PARAMETER DataDrive
  Drive letter for the build tree and Cygwin. Default D.

.PARAMETER SkipVS
  Skip the Visual Studio Build Tools step (if you already have MSVC).

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File provision-windows-build.ps1
#>
[CmdletBinding()]
param(
    [string]$DataDrive = "D",
    [switch]$SkipVS
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"   # progress bars over SSH are noise

function Say($msg) { Write-Host "== $msg" -ForegroundColor Cyan }
function Ok($msg)  { Write-Host "   $msg" -ForegroundColor Green }
function Warn($msg){ Write-Host "   $msg" -ForegroundColor Yellow }

if (-not (Test-Path "${DataDrive}:\")) { throw "drive ${DataDrive}: not found" }
$Root    = "${DataDrive}:\quickoffice"
$Dl      = Join-Path $Root "downloads"
$CygRoot = Join-Path $Root "cygwin64"
New-Item -ItemType Directory -Force -Path $Root, $Dl | Out-Null
Say "build root: $Root"

# --------------------------------------------------------------- 1. Git
Say "Git for Windows"
if (Get-Command git -ErrorAction SilentlyContinue) {
    Ok "already installed: $((Get-Command git).Source)"
} elseif (Test-Path "$env:ProgramFiles\Git\cmd\git.exe") {
    Ok "already installed (not on this session PATH): $env:ProgramFiles\Git\cmd\git.exe"
} else {
    # winget is NOT reachable from an SSH session on a stock Windows 11 box:
    # it lives under the per-user WindowsApps alias directory, which a
    # non-interactive logon does not get. Resolve it properly, and if it still
    # is not there, fetch the official installer and run it silently. Cygwin
    # ships git too, but the GitHub runner wants a Windows-side one.
    $winget = Get-Command winget -ErrorAction SilentlyContinue
    if (-not $winget) {
        $cand = Get-ChildItem "$env:ProgramFiles\WindowsApps" -Filter winget.exe `
                -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($cand) { $winget = $cand.FullName }
    } else { $winget = $winget.Source }

    if ($winget) {
        $r = Start-Process $winget -ArgumentList @(
            "install","--id","Git.Git","-e","--source","winget",
            "--accept-package-agreements","--accept-source-agreements",
            "--disable-interactivity") -Wait -PassThru -NoNewWindow
        if ($r.ExitCode -ne 0) { Warn "winget returned $($r.ExitCode)" } else { Ok "installed via winget" }
    } else {
        Ok "winget unavailable  -  installing Git for Windows directly"
        $api = Invoke-RestMethod "https://api.github.com/repos/git-for-windows/git/releases/latest" `
               -Headers @{ "User-Agent" = "quickoffice-provision" }
        $asset = $api.assets | Where-Object { $_.name -match "^Git-.*-64-bit\.exe$" } | Select-Object -First 1
        if (-not $asset) { throw "could not find a Git for Windows installer asset" }
        $gitExe = Join-Path $Dl $asset.name
        if (-not (Test-Path $gitExe)) { Invoke-WebRequest $asset.browser_download_url -OutFile $gitExe }
        $p = Start-Process $gitExe -ArgumentList @("/VERYSILENT","/NORESTART","/NOCANCEL","/SP-",
             "/COMPONENTS=gitlfs","/o:PathOption=CmdTools") -Wait -PassThru -NoNewWindow
        if ($p.ExitCode -ne 0) { throw "Git installer failed: $($p.ExitCode)" }
        Ok "installed: $($asset.name)"
    }
}

# ------------------------------------------ 2. Visual Studio 2022 Build Tools
if ($SkipVS) {
    Say "Visual Studio  -  skipped by request"
} else {
    Say "Visual Studio 2022 Build Tools (MSVC v143 + Windows 11 SDK)"
    $vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
    $have = $false
    if (Test-Path $vswhere) {
        $found = & $vswhere -latest -products * `
            -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 `
            -property installationPath 2>$null
        if ($found) {
            # Present is not enough: an install from before clang-cl was added
            # to the component list would sail through this check and then fail
            # in configure. Look for the compiler itself.
            $clang = Get-ChildItem $found -Filter "clang-cl.exe" -Recurse -ErrorAction SilentlyContinue |
                     Select-Object -First 1
            if ($clang) { $have = $true; Ok "already installed with clang-cl: $found" }
            else { Ok "installed at $found but WITHOUT clang-cl - adding it" }
        }
    }
    if (-not $have) {
        $bootstrap = Join-Path $Dl "vs_BuildTools.exe"
        if (-not (Test-Path $bootstrap)) {
            Ok "downloading bootstrapper"
            Invoke-WebRequest "https://aka.ms/vs/17/release/vs_BuildTools.exe" `
                -OutFile $bootstrap
        }
        Ok "installing (this takes a while and prints nothing)"
        # --quiet --wait: no UI, and the call actually blocks until done.
        $args = @(
            "--quiet","--wait","--norestart","--nocache",
            "--add","Microsoft.VisualStudio.Workload.VCTools",
            "--add","Microsoft.VisualStudio.Component.VC.Tools.x86.x64",
            "--add","Microsoft.VisualStudio.Component.Windows11SDK.22621",
            # Skia is built with clang-cl, not MSVC - the same rule as the
            # Linux build, where Skia is the one component that insists on
            # clang. Without these two, configure stops at "cannot determine
            # the -showIncludes prefix" and the only alternative is
            # --disable-skia, which costs GPU-accelerated rendering across the
            # whole suite.
            "--add","Microsoft.VisualStudio.Component.VC.Llvm.Clang",
            "--add","Microsoft.VisualStudio.Component.VC.Llvm.ClangToolset",
            # ATL. extensions/source/activex is the ActiveX control that lets
            # other Windows applications embed the office suite, and it
            # #includes <atlbase.h>. Without ATL the build runs for well over
            # an hour and then dies at the very end with
            #     fatal error C1083: Cannot open include file: 'atlbase.h'
            # LibreOffice does offer --disable-activex, but the brief here is
            # "all possible capabilities", and dropping OLE/ActiveX embedding
            # to save one VS component is the wrong trade.
            "--add","Microsoft.VisualStudio.Component.VC.ATL",
            "--includeRecommended")
        $p = Start-Process $bootstrap -ArgumentList $args -Wait -PassThru -NoNewWindow
        # 3010 = success, reboot required. Not an error.
        if ($p.ExitCode -notin 0,3010) { throw "VS Build Tools failed: $($p.ExitCode)" }
        Ok ("installed (exit $($p.ExitCode))" + $(if ($p.ExitCode -eq 3010) { "  -  reboot pending" } else { "" }))
    }
}

# --------------------------------------------------------------- 3. Cygwin
# The package list is LibreOffice's own Windows build requirement. nasm is for
# the bundled assembly; python3/perl drive parts of the build itself; the rest
# is the ordinary autotools set. gperf and flex/bison are hard requirements.
$CygPackages = @(
    "autoconf","automake","bison","cabextract","flex","gnupg","gperf",
    "libtool","make","mintty","nasm","openssh","openssl","patch","perl",
    "perl-Archive-Zip","pkg-config","python39","python39-devel","python3",
    "rsync","unzip","wget","zip","git","zstd","diffutils","curl"
) -join ","

Say "Cygwin 64-bit + LibreOffice build packages"
$cygBash = Join-Path $CygRoot "bin\bash.exe"
$setup = Join-Path $Dl "setup-x86_64.exe"
if (-not (Test-Path $setup)) {
    Ok "downloading Cygwin setup"
    Invoke-WebRequest "https://www.cygwin.com/setup-x86_64.exe" -OutFile $setup
}
Ok $(if (Test-Path $cygBash) { "updating existing install" } else { "installing to $CygRoot" })
$cygArgs = @(
    "--quiet-mode","--no-shortcuts","--no-startmenu","--no-desktop",
    "--upgrade-also",
    "--root", $CygRoot,
    "--local-package-dir", (Join-Path $Dl "cygpkg"),
    "--site","https://mirrors.kernel.org/sourceware/cygwin/",
    "--packages", $CygPackages)
$p = Start-Process $setup -ArgumentList $cygArgs -Wait -PassThru -NoNewWindow
if ($p.ExitCode -ne 0) { throw "Cygwin setup failed: $($p.ExitCode)" }
if (-not (Test-Path $cygBash)) { throw "Cygwin installed but $cygBash is missing" }
Ok "cygwin ready: $cygBash"

# ------------------------------------------------------------- 4. sanity pass
# --------------------------------------------------------------- 3b. pkgconf
# LibreOffice's Windows build needs a NATIVE pkgconf - one that emits
# Windows-style paths - for harfbuzz's meson build. Cygwin's pkg-config is not
# it. configure looks for the exact name "pkgconf-2.4.3.exe" because that is
# what upstream's LODE toolchain ships, but no such MSI is published; the real
# requirement is any recent native pkgconf, and presetting PKG_CONFIG makes
# autoconf use it directly instead of searching for that filename.
Say "pkgconf (native Windows, for harfbuzz/meson)"
$existing = Get-ChildItem "$env:ProgramFiles" -Filter "pkgconf*" -Directory -ErrorAction SilentlyContinue
if ($existing) {
    Ok "already installed: $($existing[0].FullName)"
} else {
    $rel = Invoke-RestMethod "https://api.github.com/repos/pkgconf/pkgconf/releases/latest" `
           -Headers @{ "User-Agent" = "quickoffice-provision" }
    $asset = $rel.assets | Where-Object { $_.name -like "*x64*.msi" } | Select-Object -First 1
    if (-not $asset) { throw "no x64 pkgconf MSI in release $($rel.tag_name)" }
    $msi = Join-Path $Dl $asset.name
    if (-not (Test-Path $msi)) { Invoke-WebRequest $asset.browser_download_url -OutFile $msi }
    $p = Start-Process msiexec -ArgumentList @("/i","`"$msi`"","/quiet","/norestart") -Wait -PassThru
    if ($p.ExitCode -notin 0,3010) { throw "pkgconf MSI failed: $($p.ExitCode)" }
    Ok "installed $($asset.name)"
}
$found = Get-ChildItem "$env:ProgramFiles","${env:ProgramFiles(x86)}" -Filter "pkgconf*" `
          -Directory -ErrorAction SilentlyContinue |
          ForEach-Object { Get-ChildItem $_.FullName -Filter pkgconf.exe -Recurse -ErrorAction SilentlyContinue } |
          Select-Object -First 1
if ($found) { Ok ("pkgconf: " + $found.FullName) } else { throw "pkgconf.exe not found after install" }

# ------------------------------------------------ 3b2. native Windows GNU make
# NOT a preference - the build is wrong without it, in a way that surfaces
# half an hour in.
#
# configure decides how to spell every tool path from ONE test (configure.ac,
# win_short_path_for_make):
#
#     make -v | grep 'Built for Windows'  ->  GNUMAKE_WIN_NATIVE=TRUE
#         TRUE : cygpath -sm  ->  C:/PROGRA~2/.../cl.exe    (Windows form)
#         else : cygpath -u   ->  /cygdrive/c/PROGRA~2/...  (Cygwin only)
#
# Cygwin's own make reports "Built for x86_64-pc-cygwin", so the whole tree
# gets cygdrive paths. That is survivable for most of the build, because
# Cygwin make and Cygwin bash both understand them - which is exactly why it
# gets 30 minutes in before anything complains.
#
# Then an external project reaches solenv/gcc-wrappers/wrapper.cxx, a NATIVE
# Win32 binary that does CreateProcess(nullptr, "\"$REAL_BUILD_CC\" ...").
# Win32 has never heard of /cygdrive, so it fails with error 2 and prints a
# cl.exe command line that looks perfectly reasonable:
#
#     Error: could not create process ""/cygdrive/c/PROGRA~2/.../cl.exe" ...": 2
#
# The fix is upstream's: use the native make LibreOffice publishes for this.
Say "native Windows GNU make (decides Windows vs Cygwin path spelling)"
$makeExe = Join-Path $Root "bin\make.exe"
if (Test-Path $makeExe) {
    Ok "already present: $makeExe"
} else {
    New-Item -ItemType Directory -Force -Path (Split-Path $makeExe) | Out-Null
    Invoke-WebRequest "https://dev-www.libreoffice.org/bin/cygwin/make-4.2.1-msvc.exe" `
        -OutFile $makeExe
    Ok "downloaded make-4.2.1-msvc.exe"
}
# Prove it is the native one; a silently-Cygwin make here costs another
# half-hour build to discover.
$mv = & $makeExe -v 2>&1 | Select-Object -First 2
if (($mv -join " ") -notmatch "Built for Windows") {
    throw "make.exe at $makeExe is not a native Win32 build: $($mv -join ' ')"
}
Ok ("make: " + ($mv | Select-Object -First 1))

# ------------------------------------------------------- 3c. AV exclusions
# LibreOffice's configure REFUSES to run while real-time scanning covers the
# build tree, and it is right to: an AV that quarantines an intermediate object
# mid-build produces failures that look like compiler bugs. It proves the point
# by writing an EICAR test file and checking whether it survives.
#
# The exclusion is SCOPED TO THE BUILD DIRECTORY - Defender stays on for the
# rest of the machine. This is what upstream's own Windows build instructions
# ask for, and it also stops Defender from scanning 40 GB of intermediates on
# every build.
Say "Windows Defender exclusion for the build tree"
try {
    $existing = (Get-MpPreference).ExclusionPath
    foreach ($p in @($Root, $CygRoot)) {
        if ($existing -contains $p) { Ok "already excluded: $p" }
        else { Add-MpPreference -ExclusionPath $p -ErrorAction Stop; Ok "excluded: $p" }
    }
} catch {
    Warn "could not set an exclusion ($($_.Exception.Message))"
    Warn "configure will refuse to run - add $Root manually in Windows Security"
}

Say "verifying the toolchain"
# Ask CYGWIN, in one shell, rather than shelling out per-tool through cmd.
# The previous version built a `cmd /c "<windows path with spaces> ..."` string
# per tool; cmd never parsed it, every probe came back empty, and a perfectly
# good install reported eight tools MISSING. One bash -lc, one round trip.
$probe = 'for t in bash make perl flex bison nasm gperf python3 autoconf pkg-config; do ' +
         'if command -v "$t" >/dev/null 2>&1; then echo "OK $t"; else echo "MISSING $t"; fi; done'
$out = & $cygBash --login -c $probe 2>&1
$out | Where-Object { $_ -match '^OK ' }      | ForEach-Object { "   {0,-11} present" -f $_.Substring(3) }
$bad = @($out | Where-Object { $_ -match '^MISSING ' } | ForEach-Object { $_.Substring(8) })
if ($bad.Count) { throw ("missing after install: " + ($bad -join ", ")) }

Say "done"
Ok "build root : $Root"
Ok "cygwin     : $CygRoot"
Ok "next       : windows\build-windows-engine.ps1"
