<#
.SYNOPSIS
  Copy the Quick Office debs into the AIQuick VM.

.DESCRIPTION
  The VM has no reachable SSH (VMware NAT), so the debs go in over VMware Tools
  guest operations, one file at a time. The engine deb is ~200 MB and vmrun has
  no progress output, so each file is timed and its size verified in the guest
  afterwards - a truncated copy would otherwise only show up as a baffling dpkg
  error much later.

.EXAMPLE
  push-debs-to-vm.ps1
#>
[CmdletBinding()]
param(
    [string]$Source = "D:\quickoffice\debs",
    [string]$GuestDir = "/tmp/quickoffice",
    [string]$User = "aiquick",
    [string]$Password = "aiquick",
    [string]$Vmx = "C:\AIQuick\AIQuick.vmx"
)

$ErrorActionPreference = "Stop"
$vmrun = @("${env:ProgramFiles(x86)}\VMware\VMware Workstation\vmrun.exe",
           "$env:ProgramFiles\VMware\VMware Workstation\vmrun.exe") |
         Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $vmrun) { throw "vmrun not found" }

function Vmrun([string[]]$rest) {
    $p = Start-Process $vmrun -ArgumentList (@("-T","ws","-gu",$User,"-gp",$Password) + $rest) `
         -Wait -PassThru -NoNewWindow
    return $p.ExitCode
}

# mkdir in the guest via a tiny script, for the same no-quoting-layers reason
# vm-run.ps1 exists.
$mk = Join-Path $env:TEMP "qo-mkdir.sh"
[System.IO.File]::WriteAllText($mk, "#!/bin/bash`nrm -rf $GuestDir`nmkdir -p $GuestDir`n",
    (New-Object System.Text.UTF8Encoding $false))
if ((Vmrun @("copyFileFromHostToGuest", $Vmx, $mk, "/tmp/qo-mkdir.sh")) -ne 0) { throw "guest copy failed" }
if ((Vmrun @("runProgramInGuest", $Vmx, "/bin/bash", "/tmp/qo-mkdir.sh")) -ne 0) { throw "guest mkdir failed" }

$files = Get-ChildItem $Source -Filter *.deb | Sort-Object Length -Descending
foreach ($f in $files) {
    $t0 = Get-Date
    $rc = Vmrun @("copyFileFromHostToGuest", $Vmx, $f.FullName, "$GuestDir/$($f.Name)")
    $secs = [math]::Round(((Get-Date) - $t0).TotalSeconds, 1)
    if ($rc -ne 0) { throw "copy failed for $($f.Name) ($rc)" }
    "{0,-52} {1,10:n0} B  {2,6}s" -f $f.Name, $f.Length, $secs
}

# Verify sizes IN THE GUEST. vmrun reports success on a partial write.
$chk = Join-Path $env:TEMP "qo-check.sh"
[System.IO.File]::WriteAllText($chk,
    "#!/bin/bash`ncd $GuestDir && ls -l *.deb > /tmp/qo-sizes.txt 2>&1; df -h / >> /tmp/qo-sizes.txt`n",
    (New-Object System.Text.UTF8Encoding $false))
Vmrun @("copyFileFromHostToGuest", $Vmx, $chk, "/tmp/qo-check.sh") | Out-Null
Vmrun @("runProgramInGuest", $Vmx, "/bin/bash", "/tmp/qo-check.sh") | Out-Null
$out = Join-Path $env:TEMP "qo-sizes.txt"
Vmrun @("copyFileFromGuestToHost", $Vmx, "/tmp/qo-sizes.txt", $out) | Out-Null
""
"--- in the guest ---"
if (Test-Path $out) { Get-Content $out; Remove-Item $out -Force }
