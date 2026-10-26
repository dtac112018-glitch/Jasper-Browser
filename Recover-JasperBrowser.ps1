param([ValidateSet('Menu','RestoreOnly')][string]$Mode='Menu',[switch]$NoPause)
$ErrorActionPreference='Continue'
$JasperHome=Join-Path $env:LOCALAPPDATA 'JasperBrowserLite'
$ProfilePath=Join-Path $JasperHome 'Profile'
$DefaultsPath=Join-Path $JasperHome 'ProfileDefaults'
$StatePath=Join-Path $JasperHome 'horror-state.json'
$CancelPath=Join-Path $JasperHome 'horror-cancel.flag'
$FinalAudioStopPath=Join-Path $JasperHome 'Horror\final-audio-stop.flag'
$DesktopLayoutScript=Join-Path $JasperHome 'Jasper-Desktop-Layout.ps1'
$MutexName='Local\JasperBrowserLiteHorrorState'
function Write-ResetState {
  $state=[ordered]@{Stage=0;SearchTriggered=$false;ReloadCount=0;FinalSequenceStarted=$false;Completed=$false;DialogPending=$false;RedMode=$false;WallpaperBackup=$null}
  $tmp=$StatePath+'.'+$PID+'.tmp'
  [IO.File]::WriteAllText($tmp,($state|ConvertTo-Json -Depth 10),(New-Object System.Text.UTF8Encoding($false)))
  Move-Item -LiteralPath $tmp -Destination $StatePath -Force
}
function Stop-HorrorWorkers {
  [IO.File]::WriteAllText($CancelPath,'Recovery requested '+(Get-Date).ToString('o'),(New-Object System.Text.UTF8Encoding($false)))
  [IO.File]::WriteAllText($FinalAudioStopPath,'Recovery requested '+(Get-Date).ToString('o'),(New-Object System.Text.UTF8Encoding($false)))
  $workers=@(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -and $_.CommandLine -like '*Jasper-Horror-Worker.ps1*' })
  foreach($p in $workers){Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue}
}
function Stop-DesktopLayoutWorkers {
  $workers=@(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -and $_.CommandLine -like '*Jasper-Desktop-Layout.ps1*' })
  foreach($p in $workers){try{Stop-Process -Id ([int]$p.ProcessId) -Force -ErrorAction SilentlyContinue}catch{}}
}
function Restore-DesktopLayout {
  if (-not (Test-Path -LiteralPath $DesktopLayoutScript)) { Write-Host 'Desktop-layout recovery script is missing; wallpaper recovery will continue.' -ForegroundColor Yellow; return }
  try {
    $ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $args = '-NoLogo -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}" -Action Restore -JasperHomeOverride "{1}"' -f $DesktopLayoutScript,$JasperHome
    $proc = Start-Process -FilePath $ps -ArgumentList $args -WindowStyle Hidden -Wait -PassThru
    if ($proc.ExitCode -ne 0) { Write-Host 'Some desktop positions might need manual adjustment.' -ForegroundColor Yellow }
  } catch { Write-Host "Desktop-layout restore reported: $($_.Exception.Message)" -ForegroundColor Yellow }
}
function Stop-JasperBrowserOnly {
  $needle=[regex]::Escape($ProfilePath)
  $items=@(Get-CimInstance Win32_Process -Filter "Name='firefox.exe'" -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -and $_.CommandLine -match $needle })
  foreach($i in $items){Stop-Process -Id $i.ProcessId -Force -ErrorAction SilentlyContinue}
}
function Restore-OriginalWallpaper {
  if (-not (Test-Path -LiteralPath $StatePath)) { Write-Host 'No Jasper horror state file found; no wallpaper backup is available.' -ForegroundColor Yellow; return }
  $s=$null; try{$s=Get-Content -LiteralPath $StatePath -Raw -Encoding UTF8|ConvertFrom-Json}catch{}
  $b=$s.WallpaperBackup
  if ($null -eq $b) { Write-Host 'No saved wallpaper backup was recorded; nothing to restore.' -ForegroundColor Yellow; return }
  try {
    if (Test-Path -LiteralPath 'HKCU:\Control Panel\Desktop') {
      Set-ItemProperty -LiteralPath 'HKCU:\Control Panel\Desktop' -Name WallpaperStyle -Value ([string]$b.WallpaperStyle) -ErrorAction SilentlyContinue
      Set-ItemProperty -LiteralPath 'HKCU:\Control Panel\Desktop' -Name TileWallpaper -Value ([string]$b.TileWallpaper) -ErrorAction SilentlyContinue
    }
    if ($b.Background) { Set-ItemProperty -LiteralPath 'HKCU:\Control Panel\Colors' -Name Background -Value ([string]$b.Background) -ErrorAction SilentlyContinue }
    if (-not ('JasperRecoveryWallpaperApi' -as [type])) {
      Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class JasperRecoveryWallpaperApi {
 [DllImport("user32.dll", EntryPoint="SystemParametersInfoW", CharSet=CharSet.Unicode, SetLastError=true)]
 public static extern bool SystemParametersInfo(uint action,uint param,string value,uint flags);
}
'@
    }
    $original=[string]$b.Wallpaper
    if ($original -and -not (Test-Path -LiteralPath $original)) { Write-Host "Original wallpaper file was not found: $original" -ForegroundColor Yellow; return }
    [void][JasperRecoveryWallpaperApi]::SystemParametersInfo(20,0,$original,3)
    Write-Host 'Original desktop wallpaper restored.' -ForegroundColor Green
  } catch { Write-Host "Wallpaper restore failed: $($_.Exception.Message)" -ForegroundColor Red }
}
function Restore-Effects {
  Stop-HorrorWorkers
  Stop-DesktopLayoutWorkers
  Stop-JasperBrowserOnly
  Start-Sleep -Milliseconds 300
  Restore-DesktopLayout
  Remove-Item -LiteralPath (Join-Path $JasperHome 'desktop-chaos-consumed.flag'),(Join-Path $JasperHome 'desktop-layout-stop.flag'),(Join-Path $JasperHome 'desktop-layout-active.flag') -Force -ErrorAction SilentlyContinue
  Restore-OriginalWallpaper
  Write-ResetState
  Remove-Item -LiteralPath $CancelPath -Force -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath $FinalAudioStopPath -Force -ErrorAction SilentlyContinue
  Write-Host 'Horror sequence and any adult-site shake stopped; Jasper trigger state reset. Browser was closed so its timers could not continue.' -ForegroundColor Green
  Write-Host 'Reopen Jasper Browser when ready.' -ForegroundColor Cyan
}
function Full-ResetProfile {
  Stop-HorrorWorkers
  Stop-DesktopLayoutWorkers
  Stop-JasperBrowserOnly
  Start-Sleep -Milliseconds 500
  Restore-DesktopLayout
  Remove-Item -LiteralPath (Join-Path $JasperHome 'desktop-chaos-consumed.flag'),(Join-Path $JasperHome 'desktop-layout-stop.flag'),(Join-Path $JasperHome 'desktop-layout-active.flag') -Force -ErrorAction SilentlyContinue
  Restore-OriginalWallpaper
  if (Test-Path -LiteralPath $ProfilePath) {
    $backup=Join-Path $JasperHome ('Profile.RecoveryBackup-'+(Get-Date -Format 'yyyyMMdd-HHmmss'))
    Move-Item -LiteralPath $ProfilePath -Destination $backup
    Write-Host "Previous Jasper profile was preserved at: $backup" -ForegroundColor Yellow
  }
  New-Item -ItemType Directory -Force -Path $ProfilePath,(Join-Path $ProfilePath 'chrome') | Out-Null
  if (Test-Path -LiteralPath (Join-Path $DefaultsPath 'user.js')) { Copy-Item -LiteralPath (Join-Path $DefaultsPath 'user.js') -Destination (Join-Path $ProfilePath 'user.js') -Force }
  if (Test-Path -LiteralPath (Join-Path $DefaultsPath 'chrome\userChrome.css')) { Copy-Item -LiteralPath (Join-Path $DefaultsPath 'chrome\userChrome.css') -Destination (Join-Path $ProfilePath 'chrome\userChrome.css') -Force }
  if (Test-Path -LiteralPath (Join-Path $DefaultsPath 'chrome\jasper-32.png')) { Copy-Item -LiteralPath (Join-Path $DefaultsPath 'chrome\jasper-32.png') -Destination (Join-Path $ProfilePath 'chrome\jasper-32.png') -Force }
  Write-ResetState
  Remove-Item -LiteralPath $CancelPath -Force -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath $FinalAudioStopPath -Force -ErrorAction SilentlyContinue
  Write-Host 'Jasper Browser profile reset to clean defaults. The old profile was backed up, not deleted.' -ForegroundColor Green
  Write-Host 'Your regular Firefox profile was not touched.' -ForegroundColor Cyan
}
if ($Mode -eq 'RestoreOnly') { Restore-Effects; if (-not $NoPause) { Read-Host 'Press Enter to finish' }; exit 0 }
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host ' JASPER BROWSER — RECOVERY' -ForegroundColor Cyan
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host '1. Stop horror effects, restore wallpaper, reset Easter egg state (keep profile data)' -ForegroundColor White
Write-Host '2. FULL RESET Jasper Browser profile (old profile is backed up first)' -ForegroundColor Yellow
Write-Host '3. Exit' -ForegroundColor Gray
$choice=Read-Host 'Choose 1, 2, or 3'
switch($choice) {
  '1' { if ((Read-Host 'Recover now? Type YES') -ceq 'YES') { Restore-Effects } else { Write-Host 'Cancelled.' -ForegroundColor Yellow } }
  '2' { Write-Host 'This resets Jasper bookmarks, cookies, history, extensions, and profile settings. The prior profile will be backed up.' -ForegroundColor Yellow; if ((Read-Host 'Type RESET to continue') -ceq 'RESET') { Full-ResetProfile } else { Write-Host 'Cancelled.' -ForegroundColor Yellow } }
  default { Write-Host 'No changes made.' -ForegroundColor Gray }
}
if (-not $NoPause) { Read-Host 'Press Enter to finish' }
