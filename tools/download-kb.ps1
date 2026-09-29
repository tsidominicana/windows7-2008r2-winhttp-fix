<#
  Descarga los KB necesarios desde el Catalogo de Microsoft Update a kb\.
  Uso:  powershell -File tools\download-kb.ps1
#>
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$root = Split-Path -Parent $PSScriptRoot
$dest = Join-Path $root 'kb'
New-Item -ItemType Directory -Force -Path $dest | Out-Null

# KB -> patron para elegir la fila correcta del catalogo (Win7 / 2008 R2)
$targets = @(
  @{ Kb = 'KB3140245'; Arch = 'x64'; Match = 'Windows 7|Windows Server 2008 R2' },
  @{ Kb = 'KB3140245'; Arch = 'x86'; Match = 'Windows 7' },
  @{ Kb = 'KB3080079'; Arch = 'x64'; Match = 'Windows 7|Windows Server 2008 R2' },
  @{ Kb = 'KB3080079'; Arch = 'x86'; Match = 'Windows 7' }
)

function Get-CatalogLinks($kb) {
  $r = Invoke-WebRequest -UseBasicParsing "https://www.catalog.update.microsoft.com/Search.aspx?q=$kb"
  $rows = [regex]::Matches($r.Content, '<tr id="([0-9a-f\-]{36})_R\d+"[\s\S]*?</tr>')
  foreach ($row in $rows) {
    $guid  = $row.Groups[1].Value
    $title = ([regex]::Match($row.Value, "id='[0-9a-f\-]{36}_link'[^>]*>\s*([^<]+?)\s*<")).Groups[1].Value
    $body  = @{ updateIDs = "[{`"size`":0,`"languages`":`"`",`"uidInfo`":`"$guid`",`"updateID`":`"$guid`"}]" }
    $d = Invoke-WebRequest -UseBasicParsing -Method Post -Uri 'https://www.catalog.update.microsoft.com/DownloadDialog.aspx' -Body $body
    $urls = [regex]::Matches($d.Content, "downloadInformation\[0\]\.files\[\d+\]\.url = '([^']+)'") | ForEach-Object { $_.Groups[1].Value }
    [pscustomobject]@{ Title = $title; Urls = @($urls) }
  }
}

foreach ($kb in ($targets | ForEach-Object { $_.Kb } | Select-Object -Unique)) {
  Write-Host "Consultando catalogo: $kb"
  foreach ($e in (Get-CatalogLinks $kb)) {
    foreach ($u in $e.Urls) {
      $name = Split-Path $u -Leaf
      if ($name -notmatch 'windows6\.1') { continue }   # solo Win7 / 2008 R2 (x86, x64; ignora ia64)
      if ($name -match 'ia64') { continue }
      $arch = if ($name -match '-x64_') { 'x64' } elseif ($name -match '-x86_') { 'x86' } else { continue }
      $out = Join-Path $dest ("{0}-{1}.msu" -f $kb.ToLower(), $arch)   # nombre estable para el .iss
      if (Test-Path $out) { continue }
      Write-Host "  bajando $name"
      Invoke-WebRequest -UseBasicParsing -Uri $u -OutFile $out
    }
  }
}
Get-ChildItem $dest -Filter *.msu | Get-FileHash -Algorithm SHA256 | ForEach-Object { "{0}  {1}" -f $_.Hash, (Split-Path $_.Path -Leaf) } | Tee-Object (Join-Path $dest 'SHA256SUMS.txt')
