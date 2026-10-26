
$ErrorActionPreference = 'Stop'
$homeDir = Join-Path $env:LOCALAPPDATA 'JasperBrowserLite'
$backupDir = Join-Path $homeDir 'Backup'
$installExePath = Join-Path $homeDir 'InstallDir.txt'
if (-not (Test-Path $installExePath)) { Write-Host 'Jasper Browser install record not found.' -ForegroundColor Yellow }
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
  $argLine = '-NoLogo -NoProfile -ExecutionPolicy Bypass -File "{0}"' -f $PSCommandPath
  Start-Process -FilePath (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe') -Verb RunAs -ArgumentList $argLine
  exit 0
}
$startMenuShortcut = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Jasper Browser.lnk'
$desktopShortcut = Join-Path ([Environment]::GetFolderPath('Desktop')) 'Jasper Browser.lnk'
$startupShortcut = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Startup\Jasper Local Page Host.lnk'
foreach ($s in @($startMenuShortcut,$desktopShortcut,$startupShortcut)) { if (Test-Path $s) { Remove-Item -LiteralPath $s -Force -ErrorAction SilentlyContinue } }

if (Test-Path $installExePath) {
  $installExe = (Get-Content -LiteralPath $installExePath -Raw).Trim()
  $installDir = Split-Path -Parent $installExe
  $policyPath = Join-Path $installDir 'distribution\policies.json'
  $oldBackup = Join-Path $backupDir 'policies.json.original'
  $absentFlag = Join-Path $backupDir 'policies-was-absent.flag'
  if (Test-Path $oldBackup) {
    Copy-Item -LiteralPath $oldBackup -Destination $policyPath -Force
    Write-Host 'Restored the pre-Jasper policies.json.' -ForegroundColor Green
  } elseif (Test-Path $absentFlag) {
    if (Test-Path $policyPath) { Remove-Item -LiteralPath $policyPath -Force }
    Write-Host 'Removed the Jasper policies.json; no policy existed before installation.' -ForegroundColor Green
  }
}
# Stop only the Jasper-owned local-page host process.
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
  Where-Object { $_.CommandLine -and $_.CommandLine -like "*JasperBrowserLite*Host-JasperPage.ps1*" } |
  ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }

Write-Host 'Removed Jasper shortcuts and attempted to restore original browser policies.'
Write-Host 'Firefox program files and normal profiles were not deleted.'
if ((Read-Host 'Delete Jasper profile, local page files, icons and backups? Type DELETE to confirm') -ceq 'DELETE') {
  $running = @(Get-CimInstance Win32_Process -Filter "Name='firefox.exe'" -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -and $_.CommandLine -like "*JasperBrowserLite*Profile*" })
  if ($running.Count -gt 0) { throw 'Jasper Browser is still running. Close it and run uninstall again.' }
  if (Test-Path $homeDir) { Remove-Item -LiteralPath $homeDir -Recurse -Force }
  Write-Host 'Jasper profile and local files removed.' -ForegroundColor Green
} else { Write-Host 'Jasper profile and local files kept.' }
Read-Host 'Press Enter to finish'
