$ErrorActionPreference = 'Stop'
$JasperHome = Join-Path $env:LOCALAPPDATA 'JasperBrowserLite'
$BrowserExeFile = Join-Path $JasperHome 'InstallDir.txt'
$BrowserExe = if (Test-Path -LiteralPath $BrowserExeFile) { (Get-Content -LiteralPath $BrowserExeFile -Raw).Trim() } else { '' }
$StatePath = Join-Path $JasperHome 'horror-state.json'
$Profile = Join-Path $JasperHome 'Profile'
$HostScript = Join-Path $JasperHome 'Host-JasperPage.ps1'
$HealthUrl = 'http://127.0.0.1:18765/health'
$StartUrl = 'http://127.0.0.1:18765/StartPage.html'
$ExpectedHealth = 'JASPER_OK|0.6.6'

function Test-JasperHost {
  try {
    $r = Invoke-WebRequest -UseBasicParsing -Uri $HealthUrl -TimeoutSec 1
    return ([string]$r.Content -eq $ExpectedHealth)
  } catch { return $false }
}
function Stop-OldJasperHost {
  # Stop only PowerShell processes launched with this user's Jasper host script.
  $needle = [regex]::Escape($HostScript)
  $items = @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -and $_.CommandLine -match $needle })
  foreach ($item in $items) { try { Stop-Process -Id ([int]$item.ProcessId) -Force -ErrorAction SilentlyContinue } catch {} }
}
function Start-JasperHost {
  if (-not (Test-Path -LiteralPath $HostScript)) { throw "Jasper local helper is missing: $HostScript" }
  $ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
  Start-Process -FilePath $ps -WindowStyle Hidden -ArgumentList ('-NoLogo -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}"' -f $HostScript) | Out-Null
  for ($i=0; $i -lt 40; $i++) {
    Start-Sleep -Milliseconds 250
    if (Test-JasperHost) { return $true }
  }
  return $false
}

if (-not $BrowserExe -or -not (Test-Path -LiteralPath $BrowserExe)) {
  Add-Type -AssemblyName System.Windows.Forms
  [void][System.Windows.Forms.MessageBox]::Show('Jasper Browser could not find its Firefox runtime. Run the Jasper Browser installer or Recovery tool.','Jasper Browser',[System.Windows.Forms.MessageBoxButtons]::OK,[System.Windows.Forms.MessageBoxIcon]::Error)
  exit 2
}
if (Test-Path -LiteralPath $StatePath) {
  try {
    $endingState = Get-Content -LiteralPath $StatePath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($endingState.Completed -eq $true) {
      Add-Type -AssemblyName System.Windows.Forms
      [void][System.Windows.Forms.MessageBox]::Show('Jasper Browser has reached its ending and is locked. Run Jasper Browser Recovery to restore the desktop and unlock it.','Jasper Browser',[System.Windows.Forms.MessageBoxButtons]::OK,[System.Windows.Forms.MessageBoxIcon]::Warning)
      exit 23
    }
  } catch { }
}
$hostReady = Test-JasperHost
if (-not $hostReady) {
  Stop-OldJasperHost
  Start-Sleep -Milliseconds 300
  $hostReady = Start-JasperHost
}
if (-not $hostReady) {
  Add-Type -AssemblyName System.Windows.Forms
  [void][System.Windows.Forms.MessageBox]::Show('Jasper Browser could not start its local page helper on 127.0.0.1:18765. Close Jasper Browser, run Repair-JasperBrowser-Fix from the v0.6.6 package, and check %LOCALAPPDATA%\JasperBrowserLite\host-startup-errors.log if it still fails.','Jasper Browser',[System.Windows.Forms.MessageBoxButtons]::OK,[System.Windows.Forms.MessageBoxIcon]::Error)
  exit 24
}
# Verify the API—not just the static page—before opening the browser.
try {
  $cfg = Invoke-RestMethod -Uri 'http://127.0.0.1:18765/api/config' -TimeoutSec 2
  if ([string]::IsNullOrWhiteSpace([string]$cfg.token)) { throw 'The helper token is empty.' }
  $stateUrl = 'http://127.0.0.1:18765/api/state?token=' + [Uri]::EscapeDataString([string]$cfg.token)
  $null = Invoke-RestMethod -Uri $stateUrl -TimeoutSec 2
} catch {
  Stop-OldJasperHost
  Start-Sleep -Milliseconds 300
  $hostReady = Start-JasperHost
  if (-not $hostReady) {
    Add-Type -AssemblyName System.Windows.Forms
    [void][System.Windows.Forms.MessageBox]::Show('Jasper Browser local helper did not pass its API check. Run Repair-JasperBrowser-Fix from the v0.6.6 package. Check %LOCALAPPDATA%\JasperBrowserLite\host-startup-errors.log if the failure repeats.','Jasper Browser',[System.Windows.Forms.MessageBoxButtons]::OK,[System.Windows.Forms.MessageBoxIcon]::Error)
    exit 25
  }
}
$args = '-no-remote -profile "{0}" "{1}"' -f $Profile, $StartUrl
Start-Process -FilePath $BrowserExe -ArgumentList $args | Out-Null
Start-Sleep -Milliseconds 450
$brand = Join-Path $JasperHome 'Brand-Window.ps1'
if (Test-Path -LiteralPath $brand) {
  $ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
  Start-Process -FilePath $ps -WindowStyle Hidden -ArgumentList ('-NoLogo -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}"' -f $brand) | Out-Null
}
