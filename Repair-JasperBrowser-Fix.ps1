$ErrorActionPreference = 'Stop'
$SourceRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$JasperHome = Join-Path $env:LOCALAPPDATA 'JasperBrowserLite'
$SiteDir = Join-Path $JasperHome 'Site'
$AssetDir = Join-Path $SiteDir 'assets'
$HorrorDir = Join-Path $JasperHome 'Horror'
$HostScript = Join-Path $JasperHome 'Host-JasperPage.ps1'
$HealthUrl = 'http://127.0.0.1:18765/health'
$ExpectedHealth = 'JASPER_OK|0.6.6'

Write-Host '============================================================' -ForegroundColor Cyan
Write-Host ' JASPER BROWSER — HELPER & HIDDEN-LAUNCHER REPAIR v0.6.6' -ForegroundColor Cyan
Write-Host '============================================================' -ForegroundColor Cyan
if (-not (Test-Path -LiteralPath (Join-Path $JasperHome 'InstallDir.txt'))) {
  Write-Host 'Jasper Browser Lite is not installed for this Windows user. Run Install-JasperBrowser.bat instead.' -ForegroundColor Red
  Read-Host 'Press Enter to close'; exit 2
}
New-Item -ItemType Directory -Force -Path $JasperHome,$SiteDir,$AssetDir,$HorrorDir | Out-Null
Copy-Item -Force (Join-Path $SourceRoot 'StartPage.html') (Join-Path $SiteDir 'StartPage.html')
Copy-Item -Force (Join-Path $SourceRoot 'assets\*') $AssetDir -Recurse
Copy-Item -Force (Join-Path $SourceRoot 'assets\black-wallpaper.bmp') (Join-Path $HorrorDir 'black-wallpaper.bmp')
Copy-Item -Force (Join-Path $SourceRoot 'assets\horror-sound.wav') (Join-Path $HorrorDir 'horror-sound.wav')
Copy-Item -Force (Join-Path $SourceRoot 'assets\final-scream.wav') (Join-Path $HorrorDir 'final-scream.wav')
Copy-Item -Force (Join-Path $SourceRoot 'assets\bsod-buffer.wav') (Join-Path $HorrorDir 'bsod-buffer.wav')
Copy-Item -Force (Join-Path $SourceRoot 'Host-JasperPage.ps1') (Join-Path $JasperHome 'Host-JasperPage.ps1')
Copy-Item -Force (Join-Path $SourceRoot 'Jasper-Horror-Worker.ps1') (Join-Path $JasperHome 'Jasper-Horror-Worker.ps1')
Copy-Item -Force (Join-Path $SourceRoot 'Jasper-Desktop-Layout.ps1') (Join-Path $JasperHome 'Jasper-Desktop-Layout.ps1')
Copy-Item -Force (Join-Path $SourceRoot 'Recover-JasperBrowser.ps1') (Join-Path $JasperHome 'Recover-JasperBrowser.ps1')
Copy-Item -Force (Join-Path $SourceRoot 'Recover-JasperBrowser.bat') (Join-Path $JasperHome 'Recover-JasperBrowser.bat')
Copy-Item -Force (Join-Path $SourceRoot 'Start-JasperBrowser.ps1') (Join-Path $JasperHome 'Start-JasperBrowser.ps1')
Copy-Item -Force (Join-Path $SourceRoot 'Start-JasperBrowser.vbs') (Join-Path $JasperHome 'Start-JasperBrowser.vbs')
Remove-Item -LiteralPath (Join-Path $JasperHome 'Jasper-Startup-Terminal.bat') -Force -ErrorAction SilentlyContinue

$tokenPath = Join-Path $JasperHome 'horror-token.txt'
$token = if (Test-Path -LiteralPath $tokenPath) { (Get-Content -LiteralPath $tokenPath -Raw -ErrorAction SilentlyContinue).Trim() } else { '' }
if ([string]::IsNullOrWhiteSpace($token)) {
  [IO.File]::WriteAllText($tokenPath,[Guid]::NewGuid().ToString('N'),(New-Object System.Text.UTF8Encoding($false)))
  Write-Host 'Repaired missing/empty local helper token.' -ForegroundColor Yellow
}
if (-not (Test-Path -LiteralPath (Join-Path $JasperHome 'horror-state.json'))) {
  $state=[ordered]@{Stage=0;SearchTriggered=$false;ReloadCount=0;FinalSequenceStarted=$false;Completed=$false;DialogPending=$false;RedMode=$false;WallpaperBackup=$null}
  [IO.File]::WriteAllText((Join-Path $JasperHome 'horror-state.json'),($state|ConvertTo-Json -Depth 8),(New-Object System.Text.UTF8Encoding($false)))
}

# Stop only Jasper's own previously launched helper, which may still be running an older script in memory.
$needle=[regex]::Escape($HostScript)
$oldHosts=@(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -and $_.CommandLine -match $needle })
foreach($p in $oldHosts){try{Stop-Process -Id ([int]$p.ProcessId) -Force -ErrorAction SilentlyContinue}catch{}}
Start-Sleep -Milliseconds 350
$ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
Start-Process -FilePath $ps -WindowStyle Hidden -ArgumentList ('-NoLogo -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}"' -f $HostScript) | Out-Null
$ready=$false
for($i=0;$i -lt 40;$i++){
  Start-Sleep -Milliseconds 250
  try{$r=Invoke-WebRequest -UseBasicParsing -Uri $HealthUrl -TimeoutSec 1;if([string]$r.Content -eq $ExpectedHealth){$ready=$true;break}}catch{}
}
if(-not $ready){
  Write-Host 'The helper still did not start. Port 18765 may be used by another program. No unrelated process was stopped.' -ForegroundColor Red
  $logPath=Join-Path $JasperHome 'host-startup-errors.log'
  if(Test-Path -LiteralPath $logPath){Write-Host 'Recent helper diagnostics:' -ForegroundColor Yellow;Get-Content -LiteralPath $logPath -Tail 8 | ForEach-Object {Write-Host $_ -ForegroundColor DarkYellow}}
  Read-Host 'Press Enter to close';exit 3
}
try{
  $cfg=Invoke-RestMethod -Uri 'http://127.0.0.1:18765/api/config' -TimeoutSec 2
  $stateUrl='http://127.0.0.1:18765/api/state?token='+[Uri]::EscapeDataString([string]$cfg.token)
  $null=Invoke-RestMethod -Uri $stateUrl -TimeoutSec 2
}catch{Write-Host ('Static host is running but API test failed: '+$_.Exception.Message) -ForegroundColor Red;Read-Host 'Press Enter to close';exit 4}

$wscriptExe=Join-Path $env:SystemRoot 'System32\wscript.exe'
$wsh=New-Object -ComObject WScript.Shell
$startMenu=Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'
$desktop=[Environment]::GetFolderPath('Desktop')
foreach($path in @((Join-Path $startMenu 'Jasper Browser.lnk'),(Join-Path $desktop 'Jasper Browser.lnk'))){
  $lnk=$wsh.CreateShortcut($path)
  $lnk.TargetPath=$wscriptExe
  $lnk.Arguments='//B //NoLogo "'+(Join-Path $JasperHome 'Start-JasperBrowser.vbs')+'"'
  $lnk.WorkingDirectory=$JasperHome
  $lnk.WindowStyle=7
  $icon=Join-Path $JasperHome 'jasper.ico';if(Test-Path -LiteralPath $icon){$lnk.IconLocation=$icon+',0'}
  $lnk.Description='Jasper Browser — launches without a visible PowerShell console'
  $lnk.Save()
}
$startupDir=Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Startup'
New-Item -ItemType Directory -Force -Path $startupDir | Out-Null
$hostLink=$wsh.CreateShortcut((Join-Path $startupDir 'Jasper Local Page Host.lnk'))
$hostLink.TargetPath=$ps
$hostLink.Arguments='-NoLogo -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "'+$HostScript+'"'
$hostLink.WorkingDirectory=$JasperHome
$hostLink.WindowStyle=7
$hostLink.Description='Jasper Browser local start-page host (loopback only)'
$hostLink.Save()

Write-Host 'Repair complete: local horror API is responding, stale Jasper helper code was replaced, and the Browser shortcut now launches invisibly.' -ForegroundColor Green
Write-Host 'The current horror stage was preserved. Use Jasper Browser Recovery to restore wallpaper, desktop icons, and window positions.' -ForegroundColor Cyan
Read-Host 'Press Enter to close'
