<#
.SYNOPSIS
  Habilita TLS 1.1/1.2 en Windows Server 2008 R2 / Windows 7 SP1 para que el
  instalador de Tactical RMM (WinHTTP) pueda contactar el servidor.

.PARAMETER RutaKB
  Carpeta con los .msu ya descargados (KB3140245, KB3080079). Opcional.
  Se instalan en orden alfabetico con wusa, sin reiniciar.

.PARAMETER CertRaiz
  Ruta a un .cer/.crt de una CA raiz (p. ej. ISRG Root X1) para importar a
  "Entidades de certificacion raiz de confianza". Opcional.

.EXAMPLE
  .\habilitar-tls12-win2008r2.ps1 -RutaKB C:\kb -CertRaiz C:\kb\isrgrootx1.cer

Compatible con PowerShell 2.0. Ejecutar como Administrador.
#>
param(
    [string]$RutaKB,
    [string]$CertRaiz,
    [switch]$Reiniciar
)

$ErrorActionPreference = 'Stop'

# --- Verificaciones ---
$id = [Security.Principal.WindowsIdentity]::GetCurrent()
$admin = New-Object Security.Principal.WindowsPrincipal($id)
if (-not $admin.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Ejecuta este script como Administrador." -ForegroundColor Red
    exit 1
}

$os = Get-WmiObject Win32_OperatingSystem
Write-Host "SO: $($os.Caption) (SP$($os.ServicePackMajorVersion)) build $($os.BuildNumber)"
if ($os.Version -like '6.1*' -and $os.ServicePackMajorVersion -lt 1) {
    Write-Host "Falta el Service Pack 1. Instalalo antes de continuar." -ForegroundColor Red
    exit 1
}

# --- 1. Actualizaciones (.msu) ---
if ($RutaKB) {
    if (-not (Test-Path $RutaKB)) { throw "No existe la carpeta $RutaKB" }
    foreach ($msu in (Get-ChildItem -Path $RutaKB -Filter *.msu | Sort-Object Name)) {
        Write-Host "Instalando $($msu.Name) ..."
        $p = Start-Process -FilePath wusa.exe -ArgumentList "`"$($msu.FullName)`" /quiet /norestart" -Wait -PassThru
        # 0 = ok, 3010 = ok pendiente reinicio, 2359302 = ya instalado
        switch ($p.ExitCode) {
            0        { Write-Host "  OK" -ForegroundColor Green }
            3010     { Write-Host "  OK (requiere reinicio)" -ForegroundColor Yellow }
            2359302  { Write-Host "  Ya estaba instalado" }
            default  { Write-Host "  wusa devolvio $($p.ExitCode)" -ForegroundColor Yellow }
        }
    }
} else {
    Write-Host "Sin -RutaKB: no se instalan KB. Verificando si estan presentes..."
    foreach ($kb in 'KB3140245','KB3080079') {
        $h = Get-HotFix -Id $kb -ErrorAction SilentlyContinue
        if ($h) { Write-Host "  $kb instalado" -ForegroundColor Green }
        else    { Write-Host "  $kb NO instalado" -ForegroundColor Yellow }
    }
}

# --- 2. WinHTTP: DefaultSecureProtocols = TLS 1.1 + TLS 1.2 (0xA00) ---
$winhttp = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Internet Settings\WinHttp',
    'HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Internet Settings\WinHttp'
)
foreach ($k in $winhttp) {
    if (-not (Test-Path $k)) { New-Item -Path $k -Force | Out-Null }
    New-ItemProperty -Path $k -Name DefaultSecureProtocols -Value 0x00000A00 -PropertyType DWord -Force | Out-Null
    Write-Host "WinHTTP DefaultSecureProtocols=0xA00 en $k"
}

# --- 3. SCHANNEL: TLS 1.2 cliente habilitado ---
$sch = 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.2\Client'
if (-not (Test-Path $sch)) { New-Item -Path $sch -Force | Out-Null }
New-ItemProperty -Path $sch -Name Enabled           -Value 1 -PropertyType DWord -Force | Out-Null
New-ItemProperty -Path $sch -Name DisabledByDefault -Value 0 -PropertyType DWord -Force | Out-Null
Write-Host "SCHANNEL TLS 1.2 Client habilitado"

# --- 4. Certificado raiz opcional ---
if ($CertRaiz) {
    if (-not (Test-Path $CertRaiz)) { throw "No existe $CertRaiz" }
    $cert  = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($CertRaiz)
    $store = New-Object System.Security.Cryptography.X509Certificates.X509Store('Root','LocalMachine')
    $store.Open('ReadWrite')
    $store.Add($cert)
    $store.Close()
    Write-Host "Raiz importada: $($cert.Subject)"
}

Write-Host ""
Write-Host "Listo. Reinicia el servidor y vuelve a ejecutar el instalador de Tactical." -ForegroundColor Green
if ($Reiniciar) {
    Write-Host "Reiniciando en 10 segundos..."
    Start-Sleep -Seconds 10
    Restart-Computer -Force
}
