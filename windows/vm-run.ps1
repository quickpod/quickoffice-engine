<#
.SYNOPSIS
  Run a command inside the AIQuick VM and get its output back.

.DESCRIPTION
  The AIQuick test VM has no reachable SSH from the host - it sits behind
  VMware's NAT and the guest is a minimal desktop build. VMware Tools guest
  operations are the reliable channel, and this wraps them.

  THE COMMAND IS SHIPPED AS A FILE, NOT AS AN ARGUMENT. Passing a shell line
  through PowerShell -> vmrun -> Windows argument quoting -> bash gets it
  mangled every time (bash exits 2 on the wreckage). Writing the script to a
  file, copying it in, and running bash on that file has no quoting layers at
  all, so anything you can type in a terminal works verbatim.

  vmrun also DROPS the guest's stdout, so the run is redirected into a guest
  file which is copied back out and printed here.

.PARAMETER Command
  Shell to run in the guest. Multi-line is fine.

.PARAMETER Script
  A local .sh file to run instead of -Command.

.PARAMETER User / Password
  Guest credentials. Default aiquick/aiquick, the image's admin account.

.EXAMPLE
  vm-run.ps1 -Command "cat /etc/os-release; quick-document --version"
  vm-run.ps1 -Script .\install-and-verify.sh
#>
[CmdletBinding()]
param(
    [string]$Command,
    [string]$Script,
    [string]$User = "aiquick",
    [string]$Password = "aiquick",
    [string]$Vmx = "C:\AIQuick\AIQuick.vmx",
    [switch]$Interactive
)

$ErrorActionPreference = "Stop"
if (-not $Command -and -not $Script) { throw "give -Command or -Script" }

$vmrun = @("${env:ProgramFiles(x86)}\VMware\VMware Workstation\vmrun.exe",
           "$env:ProgramFiles\VMware\VMware Workstation\vmrun.exe") |
         Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $vmrun) { throw "vmrun not found" }
if (-not (Test-Path $Vmx)) { throw "no VM at $Vmx" }

$stamp    = [guid]::NewGuid().ToString("N").Substring(0, 8)
$guestSh  = "/tmp/qo-$stamp.sh"
$guestOut = "/tmp/qo-$stamp.out"
$hostSh   = Join-Path $env:TEMP "qo-$stamp.sh"
$hostOut  = Join-Path $env:TEMP "qo-$stamp.out"
$hostErr  = Join-Path $env:TEMP "qo-$stamp.err"

# The guest script does its own redirect, so nothing depends on vmrun passing
# shell metacharacters through intact. LF endings only: bash refuses a CRLF
# script with "bad interpreter".
$body = if ($Script) { Get-Content -Raw $Script } else { $Command }
$text = "#!/bin/bash`n" + (($body -replace "`r`n", "`n")) + "`n"
[System.IO.File]::WriteAllText($hostSh, $text,
    (New-Object System.Text.UTF8Encoding $false))

function Vmrun([string[]]$rest) {
    $a = @("-T", "ws", "-gu", $User, "-gp", $Password) + $rest
    $p = Start-Process $vmrun -ArgumentList $a -Wait -PassThru -NoNewWindow `
         -RedirectStandardOutput "$hostErr.out" -RedirectStandardError $hostErr
    return $p.ExitCode
}

$rc = Vmrun @("copyFileFromHostToGuest", $Vmx, $hostSh, $guestSh)
if ($rc -ne 0) {
    Get-Content $hostErr -EA SilentlyContinue
    throw "could not copy the script into the guest (vmrun $rc)"
}

$runArgs = @("runProgramInGuest", $Vmx)
if ($Interactive) { $runArgs += @("-activeWindow", "-interactive") }
$runArgs += @("/bin/bash", "$guestSh")
# stdout is dropped by vmrun, so the guest script's output is captured by
# running it under a wrapper that redirects. Simplest reliable form: run bash
# on the script with the redirect built into a second tiny script.
$wrapSh    = "/tmp/qo-$stamp-wrap.sh"
$hostWrap  = Join-Path $env:TEMP "qo-$stamp-wrap.sh"
[System.IO.File]::WriteAllText($hostWrap,
    "#!/bin/bash`nbash $guestSh > $guestOut 2>&1`necho EXIT=`$? >> $guestOut`n",
    (New-Object System.Text.UTF8Encoding $false))
$rc = Vmrun @("copyFileFromHostToGuest", $Vmx, $hostWrap, $wrapSh)
if ($rc -ne 0) { Get-Content $hostErr -EA SilentlyContinue; throw "copy wrapper failed ($rc)" }

$runArgs = @("runProgramInGuest", $Vmx)
if ($Interactive) { $runArgs += @("-activeWindow", "-interactive") }
$runArgs += @("/bin/bash", $wrapSh)
$rc = Vmrun $runArgs

Vmrun @("copyFileFromGuestToHost", $Vmx, $guestOut, $hostOut) | Out-Null
if (Test-Path $hostOut) {
    Get-Content $hostOut
} else {
    Write-Host "(no output captured; vmrun exit $rc)" -ForegroundColor Yellow
    Get-Content $hostErr -EA SilentlyContinue
}

foreach ($f in @($hostSh, $hostWrap, $hostOut, $hostErr, "$hostErr.out")) {
    Remove-Item $f -Force -EA SilentlyContinue
}
Vmrun @("deleteFileInGuest", $Vmx, $guestSh)  | Out-Null
Vmrun @("deleteFileInGuest", $Vmx, $wrapSh)   | Out-Null
Vmrun @("deleteFileInGuest", $Vmx, $guestOut) | Out-Null
