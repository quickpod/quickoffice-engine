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

$git = (Get-Command git -ErrorAction SilentlyContinue)?.Source
if (-not $git) { $git = "$env:ProgramFiles\Git\cmd\git.exe" }
if (-not (Test-Path $Core)) {
    Ok "cloning (about 2 GB)"
    & $git clone --depth 1 --branch $pin.branch $pin.upstream $Core
}
& $git -C $Core fetch --depth 1 origin $pin.branch | Out-Null
& $git -C $Core checkout -q -B quickoffice $pin.commit
Ok ("core at " + (& $git -C $Core log --oneline -1))

$patches = Get-ChildItem (Join-Path $Engine "patches") -Filter *.patch -ErrorAction SilentlyContinue
if ($patches) { foreach ($p in $patches) { & $git -C $Core apply $p.FullName; Ok ("patch " + $p.Name) } }
else { Ok "no patches - every customisation is in the overlay" }

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
$inputPath = Join-Path $Core "autogen.input"
Set-Content -Path $inputPath -Value $lines -Encoding ASCII
$lines | ForEach-Object { "   $_" }

# ------------------------------------------------------------------ 3. build
$cygCore = "/cygdrive/" + $DataDrive.ToLower() + "/quickoffice/core"
$make = if ($ConfigureOnly) { "" } else { " && make -j$Jobs" }
$cmd  = "mkdir -p $cygRootP/externals && cd $cygCore && ./autogen.sh$make"

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
