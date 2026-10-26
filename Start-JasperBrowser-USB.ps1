$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
$SourceRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$RuntimeRoot = Join-Path $SourceRoot 'USB-Runtime'
$JasperHome = Join-Path $env:LOCALAPPDATA 'JasperBrowserLiteUSB'
$SiteDir = Join-Path $JasperHome 'Site'
$AssetDir = Join-Path $SiteDir 'assets'
$HorrorDir = Join-Path $JasperHome 'Horror'
$ProfileDir = Join-Path $JasperHome 'Profile'
$Port = 18766
$HealthUrl = 'http://127.0.0.1:18766/health'
$StartUrl = 'http://127.0.0.1:18766/StartPage.html'
$ExpectedHealth = 'JASPER_OK|0.6.6-USB'
function Show-Notice([string]$Text,[string]$Title='Jasper Browser USB',[System.Windows.Forms.MessageBoxIcon]$Icon=[System.Windows.Forms.MessageBoxIcon]::Information) { [void][System.Windows.Forms.MessageBox]::Show($Text,$Title,[System.Windows.Forms.MessageBoxButtons]::OK,$Icon) }
function Find-Firefox {
  $c = New-Object System.Collections.Generic.List[string]
  foreach($key in @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\firefox.exe','HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\App Paths\firefox.exe','HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\firefox.exe')) {
    try { $k=Get-Item -LiteralPath $key -ErrorAction Stop; $v=$k.GetValue(''); if($v){$c.Add([string]$v)} } catch {}
  }
  if($env:ProgramFiles){$c.Add((Join-Path $env:ProgramFiles 'Mozilla Firefox\firefox.exe'))}
  if(${env:ProgramFiles(x86)}){$c.Add((Join-Path ${env:ProgramFiles(x86)} 'Mozilla Firefox\firefox.exe'))}
  if($env:LOCALAPPDATA){$c.Add((Join-Path $env:LOCALAPPDATA 'Mozilla Firefox\firefox.exe'))}
  $cmd=Get-Command firefox.exe -ErrorAction SilentlyContinue; if($cmd){$c.Add($cmd.Source)}
  foreach($x in $c | Select-Object -Unique){if($x -and (Test-Path -LiteralPath $x -PathType Leaf)){return (Resolve-Path -LiteralPath $x).Path}}
  return $null
}
function Get-Winget {
  $w=Get-Command winget.exe -ErrorAction SilentlyContinue
  if($w){return $w.Source}
  $candidate=Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\winget.exe'
  if(Test-Path -LiteralPath $candidate){return $candidate}
  return $null
}
try {
  if(-not (Test-Path -LiteralPath (Join-Path $RuntimeRoot 'Host-JasperPage.ps1'))){throw 'The USB runtime is incomplete. Re-flash from the full v0.6.6 package.'}
  $firefox=Find-Firefox
  if(-not $firefox){
    $winget=Get-Winget
    if(-not $winget){Show-Notice 'Firefox is missing and winget is unavailable. Install Microsoft App Installer (which provides winget), then run this USB launcher again.' 'Firefox required' ([System.Windows.Forms.MessageBoxIcon]::Warning); exit 3}
    Show-Notice 'Firefox was not found. Jasper will install Mozilla Firefox using winget, then continue setup. Windows may still show its normal security/UAC prompts.' 'Installing Firefox'
    $proc=Start-Process -FilePath $winget -ArgumentList @('install','--id','Mozilla.Firefox','--exact','--source','winget','--accept-source-agreements','--accept-package-agreements','--silent') -Wait -PassThru
    $firefox=Find-Firefox
    if(-not $firefox){Show-Notice ('Firefox was not detected after winget (exit code '+$proc.ExitCode+'). Finish any Windows installer prompts, then run this USB launcher again.') 'Firefox setup not finished' ([System.Windows.Forms.MessageBoxIcon]::Warning); exit 4}
  }
  New-Item -ItemType Directory -Force -Path $JasperHome,$SiteDir,$AssetDir,$HorrorDir,$ProfileDir,(Join-Path $ProfileDir 'chrome') | Out-Null
  Copy-Item -LiteralPath (Join-Path $RuntimeRoot 'StartPage.html') -Destination (Join-Path $SiteDir 'StartPage.html') -Force
  Get-ChildItem -LiteralPath (Join-Path $RuntimeRoot 'assets') -Force | Copy-Item -Destination $AssetDir -Recurse -Force
  foreach($name in @('Host-JasperPage.ps1','Jasper-Horror-Worker.ps1','Jasper-Desktop-Layout.ps1','Recover-JasperBrowser.ps1')){Copy-Item -LiteralPath (Join-Path $RuntimeRoot $name) -Destination (Join-Path $JasperHome $name) -Force}
  Copy-Item -LiteralPath (Join-Path $RuntimeRoot 'userChrome.css') -Destination (Join-Path $ProfileDir 'chrome\userChrome.css') -Force
  Copy-Item -LiteralPath (Join-Path $SourceRoot 'assets\jasper-32.png') -Destination (Join-Path $ProfileDir 'chrome\jasper-32.png') -Force
  [IO.File]::WriteAllText((Join-Path $JasperHome 'InstallDir.txt'),$firefox,(New-Object System.Text.UTF8Encoding($false)))
  if(-not (Test-Path -LiteralPath (Join-Path $JasperHome 'horror-token.txt')) -or [string]::IsNullOrWhiteSpace((Get-Content -LiteralPath (Join-Path $JasperHome 'horror-token.txt') -Raw -ErrorAction SilentlyContinue))){[IO.File]::WriteAllText((Join-Path $JasperHome 'horror-token.txt'),[Guid]::NewGuid().ToString('N'),(New-Object System.Text.UTF8Encoding($false)))}
  if(-not (Test-Path -LiteralPath (Join-Path $JasperHome 'horror-state.json'))){$s=[ordered]@{Stage=0;SearchTriggered=$false;ReloadCount=0;FinalSequenceStarted=$false;Completed=$false;DialogPending=$false;RedMode=$false;WallpaperBackup=$null;WallpaperApplied=$false};[IO.File]::WriteAllText((Join-Path $JasperHome 'horror-state.json'),($s|ConvertTo-Json -Depth 8),(New-Object System.Text.UTF8Encoding($false)))}
  Remove-Item -LiteralPath (Join-Path $HorrorDir 'adult-warning-stop.flag') -Force -ErrorAction SilentlyContinue
  foreach($asset in @('black-wallpaper.bmp','horror-sound.wav','final-scream.wav','bsod-buffer.wav')){if(Test-Path -LiteralPath (Join-Path $RuntimeRoot ('assets\'+$asset))){Copy-Item -LiteralPath (Join-Path $RuntimeRoot ('assets\'+$asset)) -Destination (Join-Path $HorrorDir $asset) -Force}}
  $userJs=@'
user_pref("browser.shell.checkDefaultBrowser", false);
user_pref("browser.startup.homepage", "http://127.0.0.1:18766/StartPage.html");
user_pref("browser.startup.page", 1);
'@
  [IO.File]::WriteAllText((Join-Path $ProfileDir 'user.js'),$userJs,(New-Object System.Text.UTF8Encoding($false)))
  $hostScript=Join-Path $JasperHome 'Host-JasperPage.ps1'
  $hostNeedle=[regex]::Escape($hostScript)
  $old=@(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue | Where-Object {$_.CommandLine -and $_.CommandLine -match $hostNeedle})
  foreach($p in $old){try{Stop-Process -Id ([int]$p.ProcessId) -Force -ErrorAction SilentlyContinue}catch{}}
  Start-Sleep -Milliseconds 250
  $ps=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
  Start-Process -FilePath $ps -WindowStyle Hidden -ArgumentList ('-NoLogo -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}"' -f $hostScript) | Out-Null
  $hostReady=$false
  for($i=0;$i -lt 40;$i++){Start-Sleep -Milliseconds 250;try{$r=Invoke-WebRequest -UseBasicParsing -Uri $HealthUrl -TimeoutSec 1;if([string]$r.Content -eq $ExpectedHealth){$hostReady=$true;break}}catch{}}
  if(-not $hostReady){$log=Join-Path $JasperHome 'host-startup-errors.log';$msg='Jasper USB helper failed to start on port 18766.';if(Test-Path $log){$lines = @(Get-Content -LiteralPath $log -Tail 8 -ErrorAction SilentlyContinue); $msg += "`r`n" + ($lines -join "`r`n")};Show-Notice $msg 'Jasper USB helper error' ([System.Windows.Forms.MessageBoxIcon]::Error);exit 5}
  $cfg=Invoke-RestMethod -Uri 'http://127.0.0.1:18766/api/config' -TimeoutSec 2
  if([string]::IsNullOrWhiteSpace([string]$cfg.token)){throw 'The USB helper is active but its security token is missing.'}
  $stateUrl='http://127.0.0.1:18766/api/state?token='+[Uri]::EscapeDataString([string]$cfg.token)
  $null=Invoke-RestMethod -Uri $stateUrl -TimeoutSec 2
  # Create a recovery launcher in AppData and shortcuts for recovery even after removing the USB.
  $recoverBat=Join-Path $JasperHome 'Recover-JasperBrowser-USB.bat'
  [IO.File]::WriteAllText($recoverBat,"@echo off`r`npowershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File `"$JasperHome\Recover-JasperBrowser.ps1`"`r`n",[Text.Encoding]::ASCII)
  $wsh=New-Object -ComObject WScript.Shell
  $startMenu=Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'
  foreach($linkPath in @((Join-Path $startMenu 'Jasper Browser USB.lnk'),(Join-Path ([Environment]::GetFolderPath('Desktop')) 'Jasper Browser USB.lnk'))){$lnk=$wsh.CreateShortcut($linkPath);$lnk.TargetPath=$firefox;$lnk.Arguments='-no-remote -profile "'+$ProfileDir+'" "'+$StartUrl+'"';$lnk.WorkingDirectory=$JasperHome;$lnk.IconLocation=(Join-Path $SourceRoot 'assets\jasper.ico')+',0';$lnk.Description='Jasper Browser USB user-local launch';$lnk.Save()}
  foreach($linkPath in @((Join-Path $startMenu 'Jasper Browser USB Recovery.lnk'),(Join-Path ([Environment]::GetFolderPath('Desktop')) 'Jasper Browser USB Recovery.lnk'))){$lnk=$wsh.CreateShortcut($linkPath);$lnk.TargetPath=$ps;$lnk.Arguments='-NoLogo -NoProfile -ExecutionPolicy Bypass -File "'+(Join-Path $JasperHome 'Recover-JasperBrowser.ps1')+'"';$lnk.WorkingDirectory=$JasperHome;$lnk.IconLocation=(Join-Path $SourceRoot 'assets\jasper.ico')+',0';$lnk.Description='Recover Jasper Browser USB effects';$lnk.Save()}
  Start-Process -FilePath $firefox -ArgumentList ('-no-remote -profile "{0}" "{1}"' -f $ProfileDir,'http://127.0.0.1:18766/StartPage.html') | Out-Null
} catch {
  try{[IO.File]::AppendAllText((Join-Path $JasperHome 'usb-launch-errors.log'),("{0:o} {1}`r`n" -f (Get-Date),$_.Exception.ToString()),(New-Object System.Text.UTF8Encoding($false)))}catch{}
  Show-Notice ("Jasper Browser USB could not start. Details: "+$_.Exception.Message+"`r`nLog: "+(Join-Path $JasperHome 'usb-launch-errors.log')) 'Jasper Browser USB' ([System.Windows.Forms.MessageBoxIcon]::Error)
}
