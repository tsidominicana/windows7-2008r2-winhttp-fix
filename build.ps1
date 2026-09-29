# Descarga los KB si faltan y compila el instalador. Deja el .exe en dist\
#
#   powershell -ExecutionPolicy Bypass -File build.ps1
#   powershell -ExecutionPolicy Bypass -File build.ps1 -Version 1.1.0

[CmdletBinding()]
param(
    [string]$Version,
    [string]$Iscc
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path

if (@(Get-ChildItem (Join-Path $root 'kb') -Filter *.msu -ErrorAction SilentlyContinue).Count -lt 4 -or
    -not (Test-Path (Join-Path $root 'kb\isrgrootx1.der'))) {
    & (Join-Path $root 'tools\download-kb.ps1')
}

if (-not $Iscc) {
    $candidates = @(
        "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
        "$env:ProgramFiles\Inno Setup 6\ISCC.exe"
    )
    $Iscc = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
}
if (-not $Iscc) {
    $cmd = Get-Command iscc -ErrorAction SilentlyContinue
    if ($cmd) { $Iscc = $cmd.Source }
}
if (-not $Iscc) { throw "No encuentro ISCC.exe. Instala Inno Setup 6 o pasa -Iscc <ruta>." }

$iscArgs = @((Join-Path $root 'winhttp-fix.iss'))
if ($Version) { $iscArgs += "/DAppVersion=$Version" }

Write-Host "ISCC: $Iscc"
& $Iscc @iscArgs
if ($LASTEXITCODE -ne 0) { throw "La compilacion fallo (codigo $LASTEXITCODE)." }

Get-ChildItem (Join-Path $root 'dist') -Filter *.exe | ForEach-Object {
    Write-Host ("OK -> {0} ({1:N0} KB)" -f $_.FullName, ($_.Length / 1KB))
}
