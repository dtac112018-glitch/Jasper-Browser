
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
Add-Type -AssemblyName System.Windows.Forms
$homeDir = Join-Path $env:LOCALAPPDATA 'JasperBrowserLite'
$installExe = (Get-Content -LiteralPath (Join-Path $homeDir 'InstallDir.txt') -Raw -ErrorAction Stop).Trim()
$jasperProfile = Join-Path $homeDir 'Profile'
$firefox = $installExe
if (-not (Test-Path $firefox)) { Write-Host "Jasper runtime is missing: $firefox" -ForegroundColor Red; Read-Host 'Press Enter'; exit 1 }
$dialog = New-Object System.Windows.Forms.OpenFileDialog
$dialog.Title = 'Choose a Chrome extension package (.crx or .zip)'
$dialog.Filter = 'Chrome extension package (*.crx;*.zip)|*.crx;*.zip|All files (*.*)|*.*'
$dialog.Multiselect = $false
if ($dialog.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { exit 0 }
$inputFile = $dialog.FileName
$name = [IO.Path]::GetFileNameWithoutExtension($inputFile) -replace '[^A-Za-z0-9._-]','_'
$destination = Join-Path $homeDir ('Extensions\Imported\' + $name)
if (Test-Path $destination) { Remove-Item -LiteralPath $destination -Recurse -Force }
New-Item -ItemType Directory -Path $destination -Force | Out-Null
$tempZip = Join-Path $env:TEMP ('jasper-ext-' + [guid]::NewGuid().ToString('N') + '.zip')
try {
  if ([IO.Path]::GetExtension($inputFile).ToLowerInvariant() -eq '.crx') {
    $bytes = [IO.File]::ReadAllBytes($inputFile)
    if ($bytes.Length -lt 12 -or [Text.Encoding]::ASCII.GetString($bytes,0,4) -ne 'Cr24') { throw 'This does not appear to be a valid CRX package.' }
    $version = [BitConverter]::ToUInt32($bytes,4)
    if ($version -eq 2) { if ($bytes.Length -lt 16) { throw 'CRX v2 header is truncated.' }; $header = 16 + [BitConverter]::ToUInt32($bytes,8) + [BitConverter]::ToUInt32($bytes,12) }
    elseif ($version -eq 3) { $header = 12 + [BitConverter]::ToUInt32($bytes,8) }
    else { throw "Unsupported CRX version: $version" }
    if ($header -ge $bytes.Length) { throw 'CRX header length is invalid.' }
    $payload = New-Object byte[] ($bytes.Length - $header)
    [Array]::Copy($bytes, $header, $payload, 0, $payload.Length)
    [IO.File]::WriteAllBytes($tempZip, $payload)
  } else { Copy-Item -LiteralPath $inputFile -Destination $tempZip -Force }
  $rootPath = [IO.Path]::GetFullPath($destination).TrimEnd('\') + '\'
  $archive = [IO.Compression.ZipFile]::OpenRead($tempZip)
  try {
    foreach ($entry in $archive.Entries) {
      $target = [IO.Path]::GetFullPath((Join-Path $destination $entry.FullName))
      if (-not $target.StartsWith($rootPath, [StringComparison]::OrdinalIgnoreCase)) { throw "Unsafe archive path rejected: $($entry.FullName)" }
      if ($entry.FullName.EndsWith('/')) { New-Item -ItemType Directory -Force -Path $target | Out-Null; continue }
      New-Item -ItemType Directory -Force -Path (Split-Path -Parent $target) | Out-Null
      $src = $entry.Open(); try { $dst = [IO.File]::Create($target); try { $src.CopyTo($dst) } finally { $dst.Dispose() } } finally { $src.Dispose() }
    }
  } finally { $archive.Dispose() }
  $manifest = Join-Path $destination 'manifest.json'
  if (-not (Test-Path $manifest)) { throw 'No manifest.json at package root. The archive may be nested or invalid.' }
  $meta = Get-Content -LiteralPath $manifest -Raw | ConvertFrom-Json
  Write-Host "Extracted: $($meta.name)" -ForegroundColor Green
  Write-Host "Manifest version: $($meta.manifest_version)"
  Write-Host "Extension folder: $destination"
  Write-Host ''
  Write-Host 'Firefox supports many WebExtensions but not every Chrome API. Review permissions and only load extensions you trust.' -ForegroundColor Yellow
  Write-Host 'Chrome Web Store links do not make Chrome extensions automatically installable in Firefox; this helper only extracts and inspects a package.' -ForegroundColor Yellow
  Write-Host 'Temporary add-ons disappear when the browser restarts; Mozilla signature requirements are not bypassed.' -ForegroundColor Yellow
  if ((Read-Host 'Open Jasper Browser developer-tools page now? (Y/N)') -match '^(Y|YES)$') {
    Start-Process -FilePath $firefox -ArgumentList ('-no-remote -profile "{0}" "about:debugging#/runtime/this-firefox"' -f $jasperProfile)
    Write-Host "In the browser, click Load Temporary Add-on and choose: $manifest" -ForegroundColor Cyan
  }
} catch {
  Write-Host "Import failed: $($_.Exception.Message)" -ForegroundColor Red
  Read-Host 'Press Enter to exit'
  exit 1
} finally { if (Test-Path $tempZip) { Remove-Item -LiteralPath $tempZip -Force -ErrorAction SilentlyContinue } }
Read-Host 'Press Enter to finish'
