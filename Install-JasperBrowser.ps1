
$ErrorActionPreference = 'Stop'
$ProductName = 'Jasper Browser'
$JasperHome = Join-Path $env:LOCALAPPDATA 'JasperBrowserLite'
$ProfileDir = Join-Path $JasperHome 'Profile'
$SiteDir = Join-Path $JasperHome 'Site'
$BackupDir = Join-Path $JasperHome 'Backup'
$HorrorDir = Join-Path $JasperHome 'Horror'
$ProfileDefaultsDir = Join-Path $JasperHome 'ProfileDefaults'
$StartMenuDir = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'
$DesktopDir = [Environment]::GetFolderPath('Desktop')
$SourceRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

# Program Files is protected. Elevate only because the requested mode edits the existing Firefox installation in place.
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $argLine = '-NoLogo -NoProfile -ExecutionPolicy Bypass -File "{0}"' -f $PSCommandPath
    Start-Process -FilePath (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe') -Verb RunAs -ArgumentList $argLine
    exit 0
}

function Find-Firefox {
    $candidates = [System.Collections.Generic.List[string]]::new()
    $regPaths = @(
      'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\firefox.exe',
      'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\App Paths\firefox.exe',
      'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\firefox.exe'
    )
    foreach ($p in $regPaths) {
        try { $v = (Get-ItemProperty -LiteralPath $p -ErrorAction Stop).'(default)'; if ($v) { $candidates.Add([string]$v) } } catch {}
        try { $k = Get-Item -LiteralPath $p -ErrorAction Stop; $v = $k.GetValue(''); if ($v) { $candidates.Add([string]$v) } } catch {}
    }
    if ($env:ProgramFiles) { $candidates.Add((Join-Path $env:ProgramFiles 'Mozilla Firefox\firefox.exe')) }
    if (${env:ProgramFiles(x86)}) { $candidates.Add((Join-Path ${env:ProgramFiles(x86)} 'Mozilla Firefox\firefox.exe')) }
    if ($env:LOCALAPPDATA) { $candidates.Add((Join-Path $env:LOCALAPPDATA 'Mozilla Firefox\firefox.exe')) }
    $where = Get-Command firefox.exe -ErrorAction SilentlyContinue
    if ($where) { $candidates.Add($where.Source) }
    foreach ($item in $candidates | Select-Object -Unique) {
      if ($item) { $item = ([string]$item).Trim().Trim('"') }
      if ($item -and (Test-Path -LiteralPath $item -PathType Leaf)) { return (Resolve-Path -LiteralPath $item).Path }
    }
    return $null
}


function Get-FirefoxArchitecture([string]$Path) {
    try {
        $stream = [IO.File]::OpenRead($Path)
        try {
            $reader = New-Object IO.BinaryReader($stream)
            $stream.Position = 0x3C
            $peOffset = $reader.ReadInt32()
            if ($peOffset -lt 64 -or $peOffset -gt ($stream.Length - 8)) { return 'unknown' }
            $stream.Position = $peOffset
            if ($reader.ReadUInt32() -ne 0x00004550) { return 'unknown' }
            switch ($reader.ReadUInt16()) {
              0x014c { return 'x86' }
              0x8664 { return 'x64' }
              0xAA64 { return 'arm64' }
              default { return 'unknown' }
            }
        } finally { $stream.Dispose() }
    } catch { return 'unknown' }
}
function Get-DefaultFirefoxArchitecture {
    $arch = [string]$env:PROCESSOR_ARCHITECTURE
    if ($env:PROCESSOR_ARCHITEW6432) { $arch = [string]$env:PROCESSOR_ARCHITEW6432 }
    if ($arch -match 'ARM64') { return 'arm64' }
    if ([Environment]::Is64BitOperatingSystem) { return 'x64' }
    return 'x86'
}
function Install-FirefoxWithWinget([string]$Architecture) {
    $winget = Get-Command winget.exe -ErrorAction SilentlyContinue
    if (-not $winget) {
        $candidate = Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\winget.exe'
        if (Test-Path -LiteralPath $candidate) { $winget = [pscustomobject]@{ Source = $candidate } }
    }
    if (-not $winget) { throw 'Firefox was not found and winget.exe is unavailable. Install Microsoft App Installer (which supplies winget), then rerun this installer.' }
    Write-Host "Firefox was not detected. Installing Mozilla.Firefox through winget ($Architecture)..." -ForegroundColor Yellow
    $wingetArgs = @('install','--id','Mozilla.Firefox','--exact','--source','winget','--architecture',$Architecture,'--accept-source-agreements','--accept-package-agreements','--silent')
    & $winget.Source @wingetArgs | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "winget could not install Mozilla Firefox for architecture $Architecture (exit code $LASTEXITCODE). Install Firefox manually and rerun Jasper Browser setup." }
    Start-Sleep -Seconds 2
    $found = Find-Firefox
    if (-not $found) { throw 'winget reported success, but firefox.exe could not be detected afterwards. Finish Firefox setup and rerun the Jasper installer.' }
    return $found
}


$script:JasperBuildStepCount = 8
function Set-JasperBuildStage {
    param([int]$Step, [string]$Title, [string]$Detail)
    $Step = [Math]::Max(1, [Math]::Min($script:JasperBuildStepCount, $Step))
    $percent = [int][Math]::Floor(($Step / [double]$script:JasperBuildStepCount) * 100)
    $filled = [int][Math]::Floor($percent / 5)
    $bar = ('#' * $filled) + ('-' * (20 - $filled))
    Write-Host ''
    Write-Host (('[{0:D2}/{1:D2}] {2}' -f $Step, $script:JasperBuildStepCount, $Title).ToUpperInvariant()) -ForegroundColor Cyan
    Write-Host ('  {0,3}% [{1}]' -f $percent, $bar) -ForegroundColor Green
    Write-Host ('  ' + $Detail) -ForegroundColor DarkGray
    try { Write-Progress -Id 1 -Activity 'Jasper Browser — assembling installation' -Status ($Title + ': ' + $Detail) -PercentComplete $percent } catch {}
}
function Complete-JasperBuildUI {
    try { Write-Progress -Id 1 -Activity 'Jasper Browser — assembling installation' -Completed } catch {}
    Write-Host ''
    Write-Host '============================================================' -ForegroundColor Green
    Write-Host ' BUILD COMPLETE: JASPER BROWSER IS INSTALLED' -ForegroundColor Green
    Write-Host '============================================================' -ForegroundColor Green
    Write-Host 'Note: this compile-style installer configures the existing Gecko/Firefox runtime; it does not compile Gecko source.' -ForegroundColor Yellow
}

function Invoke-JasperFinalTerminalGlitch {
    # A short, purely visual post-install effect. It changes only this console's colors
    # and output; it does not alter Windows settings, files, or processes.
    $payload = 'IUNFEWUIDSBFUICEWISAHFIUDEWHUHFDCIUEWHDSIHFCIDUSFCEDFICSDIJC'
    try {
        [Console]::BackgroundColor = [ConsoleColor]::Black
        [Console]::ForegroundColor = [ConsoleColor]::Red
        Clear-Host
        [Console]::ForegroundColor = [ConsoleColor]::Red
        $width = 80
        try { $width = [Math]::Max(20, [Console]::WindowWidth) } catch {}
        $copiesPerLine = [Math]::Max(1, [int][Math]::Ceiling($width / [double]($payload.Length + 1)))
        $line = (($payload + ' ') * $copiesPerLine)
        $timer = [Diagnostics.Stopwatch]::StartNew()
        $lineCount = 0
        while ($timer.ElapsedMilliseconds -lt 430 -and $lineCount -lt 160) {
            [Console]::WriteLine($line)
            $lineCount++
        }
        $timer.Stop()
        Start-Sleep -Milliseconds 120
    } catch {
        try { Write-Host $payload -ForegroundColor Red } catch {}
    }
}

try {
    Write-Host '============================================================' -ForegroundColor Cyan
    Write-Host ' JASPER BROWSER v0.6.6 — ADULT-SITE BLOCK + HORROR INSTALLER' -ForegroundColor Cyan
    Write-Host '============================================================' -ForegroundColor Cyan
    Set-JasperBuildStage 1 'Detecting Gecko runtime' 'Scanning Windows install paths and App Paths registry...'
    $sourceExe = Find-Firefox
    if (-not $sourceExe) {
      $preferredArch = Get-DefaultFirefoxArchitecture
      $sourceExe = Install-FirefoxWithWinget $preferredArch
    }
    $runtimeArch = Get-FirefoxArchitecture $sourceExe
    if ($runtimeArch -eq 'unknown') { throw "Could not read Firefox executable architecture: $sourceExe" }
    $InstallDir = Split-Path -Parent $sourceExe
    Set-JasperBuildStage 2 'Validating installation' 'Checking that the browser is closed and install path is writable...'
    Write-Host "Detected runtime: $sourceExe ($runtimeArch)" -ForegroundColor Green
    if ($runtimeArch -eq 'x86') { Write-Host '32-bit Firefox detected; Jasper will use this 32-bit runtime. It will not replace it with x64.' -ForegroundColor Yellow }
    Write-Host "Jasper will use the existing Program Files installation: $InstallDir" -ForegroundColor Yellow
    Write-Host 'No second browser runtime copy will be created.' -ForegroundColor Green
    Write-Host 'Adult-site WebsiteFilter blocking applies to every profile using this Firefox installation.' -ForegroundColor Yellow
    Write-Host 'The Jasper profile remains separate, but browser policies are installation-wide.' -ForegroundColor Yellow

    $running = @(Get-CimInstance Win32_Process -Filter "Name='firefox.exe'" -ErrorAction SilentlyContinue)
    if ($running.Count -gt 0) { throw 'Close every Firefox/Jasper window before installing in-place, then run this installer again.' }

    Set-JasperBuildStage 3 'Preparing build workspace' 'Creating the Jasper profile, site directory, and recovery backup folder...'
    New-Item -ItemType Directory -Force -Path $JasperHome,$ProfileDir,$SiteDir,$BackupDir,$HorrorDir,$ProfileDefaultsDir,(Join-Path $ProfileDefaultsDir 'chrome'),(Join-Path $ProfileDir 'chrome'),(Join-Path $SiteDir 'assets') | Out-Null
    $exeText = $sourceExe
    [IO.File]::WriteAllText((Join-Path $JasperHome 'InstallDir.txt'), $exeText, (New-Object System.Text.UTF8Encoding($false)))

    # Keep recoverable copies of policy/shortcuts. Do not alter the installed Firefox executable itself.
    $policyPath = Join-Path $InstallDir 'distribution\policies.json'
    $policyDir = Split-Path -Parent $policyPath
    New-Item -ItemType Directory -Force -Path $policyDir | Out-Null
    $oldPolicyBackup = Join-Path $BackupDir 'policies.json.original'
    $policyAbsentMarker = Join-Path $BackupDir 'policies-was-absent.flag'
    if (-not (Test-Path $oldPolicyBackup) -and -not (Test-Path $policyAbsentMarker)) {
       if (Test-Path $policyPath) { Copy-Item -LiteralPath $policyPath -Destination $oldPolicyBackup -Force }
       else { [IO.File]::WriteAllText($policyAbsentMarker, 'No policies.json existed before Jasper Browser installation.') }
    }

    Set-JasperBuildStage 4 'Assembling Jasper resources' 'Linking the homepage, fox icon, site assets, style sheet, and helpers...'
    Copy-Item -Force (Join-Path $SourceRoot 'StartPage.html') (Join-Path $SiteDir 'StartPage.html')
    Copy-Item -Force (Join-Path $SourceRoot 'assets\*') $([IO.Path]::Combine($SiteDir,'assets')) -Recurse
    Copy-Item -Force (Join-Path $SourceRoot 'assets\jasper.ico') (Join-Path $JasperHome 'jasper.ico')
    Copy-Item -Force (Join-Path $SourceRoot 'assets\jasper-32.png') (Join-Path $ProfileDir 'chrome\jasper-32.png')
    Copy-Item -Force (Join-Path $SourceRoot 'userChrome.css') (Join-Path $ProfileDir 'chrome\userChrome.css')
    Copy-Item -Force (Join-Path $SourceRoot 'Host-JasperPage.ps1') (Join-Path $JasperHome 'Host-JasperPage.ps1')
    Copy-Item -Force (Join-Path $SourceRoot 'Start-JasperBrowser.ps1') (Join-Path $JasperHome 'Start-JasperBrowser.ps1')
    Copy-Item -Force (Join-Path $SourceRoot 'Start-JasperBrowser.vbs') (Join-Path $JasperHome 'Start-JasperBrowser.vbs')
    Copy-Item -Force (Join-Path $SourceRoot 'Jasper-Horror-Worker.ps1') (Join-Path $JasperHome 'Jasper-Horror-Worker.ps1')
    Copy-Item -Force (Join-Path $SourceRoot 'Jasper-Desktop-Layout.ps1') (Join-Path $JasperHome 'Jasper-Desktop-Layout.ps1')
    Copy-Item -Force (Join-Path $SourceRoot 'adult-site-blocklist.txt') (Join-Path $JasperHome 'adult-site-blocklist.txt')
    Copy-Item -Force (Join-Path $SourceRoot 'Recover-JasperBrowser.ps1') (Join-Path $JasperHome 'Recover-JasperBrowser.ps1')
    Copy-Item -Force (Join-Path $SourceRoot 'Recover-JasperBrowser.bat') (Join-Path $JasperHome 'Recover-JasperBrowser.bat')
    Copy-Item -Force (Join-Path $SourceRoot 'assets\black-wallpaper.bmp') (Join-Path $HorrorDir 'black-wallpaper.bmp')
    Copy-Item -Force (Join-Path $SourceRoot 'assets\horror-sound.wav') (Join-Path $HorrorDir 'horror-sound.wav')
    Copy-Item -Force (Join-Path $SourceRoot 'assets\final-scream.wav') (Join-Path $HorrorDir 'final-scream.wav')
    Copy-Item -Force (Join-Path $SourceRoot 'assets\bsod-buffer.wav') (Join-Path $HorrorDir 'bsod-buffer.wav')
    Copy-Item -Force (Join-Path $SourceRoot 'Import-Chrome-Extension.ps1') (Join-Path $JasperHome 'Import-Chrome-Extension.ps1')
    Copy-Item -Force (Join-Path $SourceRoot 'Uninstall-JasperBrowser.ps1') (Join-Path $JasperHome 'Uninstall-JasperBrowser.ps1')
    Copy-Item -Force (Join-Path $SourceRoot 'README.txt') (Join-Path $JasperHome 'README.txt')
    $tokenPath = Join-Path $JasperHome 'horror-token.txt'
    if (-not (Test-Path -LiteralPath $tokenPath)) { [IO.File]::WriteAllText($tokenPath, [Guid]::NewGuid().ToString('N'), (New-Object System.Text.UTF8Encoding($false))) }
    $statePath = Join-Path $JasperHome 'horror-state.json'
    if (-not (Test-Path -LiteralPath $statePath)) {
      $initialHorrorState = [ordered]@{ Stage=0; SearchTriggered=$false; ReloadCount=0; FinalSequenceStarted=$false; Completed=$false; DialogPending=$false; RedMode=$false; WallpaperBackup=$null }
      [IO.File]::WriteAllText($statePath, ($initialHorrorState | ConvertTo-Json -Depth 8), (New-Object System.Text.UTF8Encoding($false)))
    }

    Set-JasperBuildStage 5 'Configuring Jasper profile' 'Writing homepage preferences and managed search/extension settings...'
    $newTabUrl = 'http://127.0.0.1:18765/StartPage.html'
    $userJs = @"
// Jasper Browser profile preferences; this profile is isolated from your old Firefox profile.
user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);
user_pref("browser.startup.page", 1);
user_pref("browser.startup.homepage", "$newTabUrl");
user_pref("browser.shell.checkDefaultBrowser", false);
user_pref("browser.bookmarks.restore_default_bookmarks", false);
user_pref("browser.newtabpage.activity-stream.showSponsored", false);
user_pref("browser.newtabpage.activity-stream.showSponsoredTopSites", false);
user_pref("privacy.trackingprotection.enabled", true);
user_pref("browser.contentblocking.category", "standard");
user_pref("privacy.trackingprotection.socialtracking.enabled", true);
user_pref("browser.tabs.drawInTitlebar", false);
user_pref("browser.toolbars.bookmarks.visibility", "never");
user_pref("browser.urlbar.placeholderName", "Jasper Search");
"@
    [IO.File]::WriteAllText((Join-Path $ProfileDir 'user.js'), $userJs, (New-Object System.Text.UTF8Encoding($false)))
    Copy-Item -Force (Join-Path $ProfileDir 'user.js') (Join-Path $ProfileDefaultsDir 'user.js')
    Copy-Item -Force (Join-Path $SourceRoot 'userChrome.css') (Join-Path $ProfileDefaultsDir 'chrome\userChrome.css')
    Copy-Item -Force (Join-Path $SourceRoot 'assets\jasper-32.png') (Join-Path $ProfileDefaultsDir 'chrome\jasper-32.png')

    $smallPng = [IO.File]::ReadAllBytes((Join-Path $SiteDir 'assets\jasper-32.png'))
    $iconData = 'data:image/png;base64,' + [Convert]::ToBase64String($smallPng)
    $adultDomains = @(Get-Content -LiteralPath (Join-Path $SourceRoot 'adult-site-blocklist.txt') -Encoding UTF8 | ForEach-Object { $_.Trim().ToLowerInvariant() } | Where-Object { $_ -and -not $_.StartsWith('#') -and $_ -match '^[a-z0-9.-]+\.[a-z]{2,}$' } | Select-Object -Unique)
    $adultBlockPatterns = @()
    foreach ($domain in $adultDomains) {
      $adultBlockPatterns += ('*://' + $domain + '/*')
      $adultBlockPatterns += ('*://*.' + $domain + '/*')
    }
    Write-Host ("Adult-site blocklist will cover {0} known domains in this Firefox installation." -f $adultDomains.Count) -ForegroundColor Yellow
    Write-Host 'WebsiteFilter is installation-wide: other Firefox profiles using this same installation will also block these domains.' -ForegroundColor Yellow

    $policy = @{
      policies = @{
        WebsiteFilter = @{ Block = $adultBlockPatterns }
        ExtensionSettings = @{
          '*' = @{ installation_mode = 'allowed' }
          'newtaboverride@agenedia.com' = @{
            installation_mode = 'force_installed'
            install_url = 'https://addons.mozilla.org/firefox/downloads/latest/new-tab-override/latest.xpi'
          }
          'uBlock0@raymondhill.net' = @{
            installation_mode = 'force_installed'
            install_url = 'https://addons.mozilla.org/firefox/downloads/latest/ublock-origin/latest.xpi'
          }
        }
        '3rdparty' = @{
          Extensions = @{
            'newtaboverride@agenedia.com' = @{
              type = 'custom_url'
              url = $newTabUrl
              focus_website = $true
            }
            'uBlock0@raymondhill.net' = @{
              toAdd = @{
                trustedSiteDirectives = @('southparkstudios.com', 'southpark.cc.com')
              }
            }
          }
        }
        SearchEngines = @{
          Add = @(@{
            Name = 'Jasper Search'
            URLTemplate = 'https://www.google.com/search?q={searchTerms}'
            Method = 'GET'
            IconURL = $iconData
            Alias = 'jasper'
            Description = 'Jasper Search — results powered by Google'
            SuggestURLTemplate = 'https://suggestqueries.google.com/complete/search?client=firefox&q={searchTerms}'
          })
          Default = 'Jasper Search'
          PreventInstalls = $false
        }
      }
    }
    $policyJson = $policy | ConvertTo-Json -Depth 16
    [IO.File]::WriteAllText($policyPath, $policyJson, (New-Object System.Text.UTF8Encoding($false)))

    Set-JasperBuildStage 6 'Wiring native horror and recovery controls' 'Preparing actual Windows dialogs, reversible wallpaper effect, sound, and recovery launcher...'
    $brandWatcher = @'
$ErrorActionPreference = 'SilentlyContinue'
$JasperHome = Join-Path $env:LOCALAPPDATA 'JasperBrowserLite'
$JasperProfile = Join-Path $JasperHome 'Profile'
$IconPath = Join-Path $JasperHome 'jasper.ico'
$AppId = 'Jasper.Browser.Lite'
Add-Type @"
using System;
using System.Runtime.InteropServices;
[StructLayout(LayoutKind.Sequential)]
public struct JasperPropertyKey { public Guid fmtid; public uint pid; public JasperPropertyKey(Guid f, uint p) { fmtid=f; pid=p; } }
[StructLayout(LayoutKind.Explicit, Size=24)]
public struct JasperPropVariant { [FieldOffset(0)] public ushort vt; [FieldOffset(8)] public IntPtr pwszVal; }
[ComImport, Guid("886D8EEB-8CF2-4446-8D02-CDBA1DBDCF99"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface JasperIPropertyStore {
  [PreserveSig] int GetCount(out uint cProps);
  [PreserveSig] int GetAt(uint iProp, out JasperPropertyKey pkey);
  [PreserveSig] int GetValue(ref JasperPropertyKey key, out JasperPropVariant pv);
  [PreserveSig] int SetValue(ref JasperPropertyKey key, ref JasperPropVariant pv);
  [PreserveSig] int Commit();
}
public static class JasperWinBrand {
  static readonly Guid StoreIid = new Guid("886D8EEB-8CF2-4446-8D02-CDBA1DBDCF99");
  static readonly Guid AppModelFmtid = new Guid("9F4C2855-9F79-4B39-A8D0-E1D42DE1D5F3");
  static readonly JasperPropertyKey AppIdKey = new JasperPropertyKey(AppModelFmtid, 5);
  [DllImport("user32.dll", CharSet=CharSet.Unicode, SetLastError=true)] public static extern bool SetWindowText(IntPtr hWnd, string text);
  [DllImport("user32.dll", EntryPoint="SendMessageW", SetLastError=true)] public static extern IntPtr SendMessage(IntPtr hWnd, uint msg, IntPtr wParam, IntPtr lParam);
  [DllImport("user32.dll", CharSet=CharSet.Unicode, SetLastError=true)] public static extern IntPtr LoadImage(IntPtr hinst, string name, uint type, int cx, int cy, uint flags);
  [DllImport("shell32.dll", CharSet=CharSet.Unicode, PreserveSig=true)] static extern int SHGetPropertyStoreForWindow(IntPtr hwnd, ref Guid riid, out JasperIPropertyStore store);
  [DllImport("ole32.dll", PreserveSig=true)] static extern int PropVariantClear(ref JasperPropVariant pv);
  static bool SetAppId(JasperIPropertyStore store, string appId) {
    if (store == null) return false;
    var pv = new JasperPropVariant(); pv.vt = 31; pv.pwszVal = Marshal.StringToCoTaskMemUni(appId);
    var key = AppIdKey; try { return store.SetValue(ref key, ref pv) >= 0 && store.Commit() >= 0; }
    finally { PropVariantClear(ref pv); if (Marshal.IsComObject(store)) Marshal.ReleaseComObject(store); }
  }
  public static bool SetAppUserModelIdForWindow(IntPtr hwnd, string appId) {
    var iid = StoreIid; JasperIPropertyStore store;
    if (SHGetPropertyStoreForWindow(hwnd, ref iid, out store) < 0) return false;
    return SetAppId(store, appId);
  }
}
"@
$smallIcon = [JasperWinBrand]::LoadImage([IntPtr]::Zero, $IconPath, 1, 16, 16, 0x10)
$largeIcon = [JasperWinBrand]::LoadImage([IntPtr]::Zero, $IconPath, 1, 32, 32, 0x10)
$profileNeedle = [regex]::Escape($JasperProfile)
$hadWindow = $false
$emptyLoops = 0
$startupDeadline = (Get-Date).AddSeconds(90)
while ($true) {
  $jasperProcesses = @(Get-CimInstance Win32_Process -Filter "Name='firefox.exe'" -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -and $_.CommandLine -match $profileNeedle })
  if ($jasperProcesses.Count -eq 0) {
    if ($hadWindow) { $emptyLoops++; if ($emptyLoops -ge 8) { break } }
    elseif ((Get-Date) -gt $startupDeadline) { break }
    Start-Sleep -Milliseconds 400
    continue
  }
  foreach ($m in $jasperProcesses) {
    $p = Get-Process -Id $m.ProcessId -ErrorAction SilentlyContinue
    if (-not $p) { continue }
    $p.Refresh(); $h = $p.MainWindowHandle
    if ($h -eq [IntPtr]::Zero) { continue }
    $hadWindow = $true; $emptyLoops = 0
    [void][JasperWinBrand]::SetWindowText($h, 'Jasper Browser')
    if ($smallIcon -ne [IntPtr]::Zero) { [void][JasperWinBrand]::SendMessage($h, 0x80, [IntPtr]::Zero, $smallIcon) }
    if ($largeIcon -ne [IntPtr]::Zero) { [void][JasperWinBrand]::SendMessage($h, 0x80, [IntPtr]1, $largeIcon) }
    [void][JasperWinBrand]::SetAppUserModelIdForWindow($h, $AppId)
  }
  Start-Sleep -Milliseconds 600
}
'@
    [IO.File]::WriteAllText((Join-Path $JasperHome 'Brand-Window.ps1'), $brandWatcher, (New-Object System.Text.UTF8Encoding($false)))

    # v0.6.0: never show a console beside Jasper. The VBS shortcut wrapper starts PowerShell hidden.
    Remove-Item -LiteralPath (Join-Path $JasperHome 'Jasper-Startup-Terminal.bat') -Force -ErrorAction SilentlyContinue
    Copy-Item -Force (Join-Path $SourceRoot 'Start-JasperBrowser.ps1') (Join-Path $JasperHome 'Start-JasperBrowser.ps1')
    Copy-Item -Force (Join-Path $SourceRoot 'Start-JasperBrowser.vbs') (Join-Path $JasperHome 'Start-JasperBrowser.vbs')

    Set-JasperBuildStage 7 'Registering Jasper shortcuts' 'Creating Start menu/desktop entries and the local-page host launcher...'
    # Install an invisible-on-screen host at user logon so the local new-tab URL exists whenever the browser runs.
    $startupDir = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Startup'
    New-Item -ItemType Directory -Force -Path $startupDir | Out-Null
    $hostShortcutPath = Join-Path $startupDir 'Jasper Local Page Host.lnk'
    $powershellExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $wscriptExe = Join-Path $env:SystemRoot 'System32\wscript.exe'
    Add-Type @"
using System;
using System.Runtime.InteropServices;
[StructLayout(LayoutKind.Sequential)] public struct JasperLinkPropertyKey { public Guid fmtid; public uint pid; public JasperLinkPropertyKey(Guid f, uint p) { fmtid=f; pid=p; } }
[StructLayout(LayoutKind.Explicit, Size=24)] public struct JasperLinkPropVariant { [FieldOffset(0)] public ushort vt; [FieldOffset(8)] public IntPtr pwszVal; }
[ComImport, Guid("886D8EEB-8CF2-4446-8D02-CDBA1DBDCF99"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)] public interface JasperLinkIPropertyStore {
  [PreserveSig] int GetCount(out uint cProps); [PreserveSig] int GetAt(uint iProp, out JasperLinkPropertyKey pkey); [PreserveSig] int GetValue(ref JasperLinkPropertyKey key, out JasperLinkPropVariant pv); [PreserveSig] int SetValue(ref JasperLinkPropertyKey key, ref JasperLinkPropVariant pv); [PreserveSig] int Commit();
}
public static class JasperLinkIdentity {
  static readonly Guid StoreIid = new Guid("886D8EEB-8CF2-4446-8D02-CDBA1DBDCF99");
  static readonly JasperLinkPropertyKey AppIdKey = new JasperLinkPropertyKey(new Guid("9F4C2855-9F79-4B39-A8D0-E1D42DE1D5F3"), 5);
  [DllImport("shell32.dll", CharSet=CharSet.Unicode, PreserveSig=true)] static extern int SHGetPropertyStoreFromParsingName(string path, IntPtr bindCtx, uint flags, ref Guid riid, out JasperLinkIPropertyStore store);
  [DllImport("ole32.dll", PreserveSig=true)] static extern int PropVariantClear(ref JasperLinkPropVariant pv);
  public static bool SetAppUserModelIdForShortcut(string path, string appId) {
    var iid = StoreIid; JasperLinkIPropertyStore store;
    if (SHGetPropertyStoreFromParsingName(path, IntPtr.Zero, 2, ref iid, out store) < 0) return false;
    var pv = new JasperLinkPropVariant(); pv.vt=31; pv.pwszVal=Marshal.StringToCoTaskMemUni(appId);
    var key = AppIdKey; try { return store.SetValue(ref key, ref pv) >= 0 && store.Commit() >= 0; }
    finally { PropVariantClear(ref pv); if (Marshal.IsComObject(store)) Marshal.ReleaseComObject(store); }
  }
}
"@ -ErrorAction Stop
    $wsh = New-Object -ComObject WScript.Shell
    $hostShortcut = $wsh.CreateShortcut($hostShortcutPath)
    $hostShortcut.TargetPath = $powershellExe
    $hostShortcut.Arguments = '-NoLogo -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + (Join-Path $JasperHome 'Host-JasperPage.ps1') + '"'
    $hostShortcut.WorkingDirectory = $JasperHome
    $hostShortcut.WindowStyle = 7
    $hostShortcut.Description = 'Jasper Browser local start-page host (loopback only)'
    $hostShortcut.Save()

    # Replace/add only Jasper shortcuts that point to the existing Program Files firefox.exe.
    $startMenuShortcut = Join-Path $StartMenuDir 'Jasper Browser.lnk'
    $desktopShortcut = Join-Path $DesktopDir 'Jasper Browser.lnk'
    foreach ($shortcutPath in @($startMenuShortcut,$desktopShortcut)) {
      $shortcut = $wsh.CreateShortcut($shortcutPath)
      $shortcut.TargetPath = $wscriptExe
      $shortcut.Arguments = '//B //NoLogo "' + (Join-Path $JasperHome 'Start-JasperBrowser.vbs') + '"'
      $shortcut.WorkingDirectory = $JasperHome
      $shortcut.WindowStyle = 7
      $shortcut.IconLocation = (Join-Path $JasperHome 'jasper.ico') + ',0'
      $shortcut.Description = 'Jasper Browser — existing Program Files runtime, Jasper profile and Google-powered Jasper Search'
      $shortcut.Save()
      try { [void][JasperLinkIdentity]::SetAppUserModelIdForShortcut($shortcutPath, 'Jasper.Browser.Lite') } catch {}
    }
    $recoveryShortcutPaths = @(
      (Join-Path $StartMenuDir 'Jasper Browser Recovery.lnk'),
      (Join-Path $DesktopDir 'Jasper Browser Recovery.lnk')
    )
    foreach ($recoveryPath in $recoveryShortcutPaths) {
      $recoveryLink = $wsh.CreateShortcut($recoveryPath)
      $recoveryLink.TargetPath = $powershellExe
      $recoveryLink.Arguments = '-NoLogo -NoProfile -ExecutionPolicy Bypass -File "' + (Join-Path $JasperHome 'Recover-JasperBrowser.ps1') + '"'
      $recoveryLink.WorkingDirectory = $JasperHome
      $recoveryLink.IconLocation = (Join-Path $JasperHome 'jasper.ico') + ',0'
      $recoveryLink.Description = 'Restore Jasper Browser horror effects, wallpaper, or reset the Jasper profile'
      $recoveryLink.Save()
      try { [void][JasperLinkIdentity]::SetAppUserModelIdForShortcut($recoveryPath, 'Jasper.Browser.Recovery') } catch {}
    }

    Set-JasperBuildStage 8 'Finalizing installation' 'Starting the loopback page host and verifying Jasper page availability...'
    # Restart any stale in-memory host before checking the updated endpoint.
    $HostScriptPath = Join-Path $JasperHome 'Host-JasperPage.ps1'
    $hostReady = $false
    try { $r = Invoke-WebRequest -UseBasicParsing -Uri 'http://127.0.0.1:18765/health' -TimeoutSec 1; $hostReady = ([string]$r.Content -eq 'JASPER_OK|0.6.6') } catch {}
    if (-not $hostReady) {
      $oldHostNeedle = [regex]::Escape($HostScriptPath)
      $oldHosts = @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -and $_.CommandLine -match $oldHostNeedle })
      foreach ($oldHost in $oldHosts) { try { Stop-Process -Id ([int]$oldHost.ProcessId) -Force -ErrorAction SilentlyContinue } catch {} }
      Start-Sleep -Milliseconds 300
      Start-Process -FilePath $powershellExe -WindowStyle Hidden -ArgumentList ('-NoLogo -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}"' -f $HostScriptPath) | Out-Null
      for ($i = 0; $i -lt 40; $i++) {
        Start-Sleep -Milliseconds 250
        try { $r = Invoke-WebRequest -UseBasicParsing -Uri 'http://127.0.0.1:18765/health' -TimeoutSec 1; if ([string]$r.Content -eq 'JASPER_OK|0.6.6') { $hostReady = $true; break } } catch {}
      }
    }
    if (-not $hostReady) { throw 'Jasper local page helper did not start after updating it. Port 18765 may be occupied by another program.' }

    Complete-JasperBuildUI
    Write-Host 'JASPER BROWSER v0.6.6 INSTALLED IN PLACE' -ForegroundColor Green
    Write-Host "Runtime: $sourceExe"
    Write-Host "Program Files folder modified: $InstallDir"
    Write-Host "Jasper-only profile: $ProfileDir"
    Write-Host 'uBlock Origin is force-installed; filtering is disabled only on South Park domains to help its video player.' -ForegroundColor Green
    Write-Host 'New tabs use the version-checked Jasper local host; browser launch uses a hidden wrapper (no PowerShell terminal).' -ForegroundColor Green
    Write-Host 'Horror Easter egg: reversible wallpaper, native dialogs, recoverable desktop/window shuffle, rising scream and a simulated BSOD-like buffer sound; Windows itself is not crashed.' -ForegroundColor Yellow
    Write-Host 'Note: Windows does not provide a stable supported API to reorder pinned taskbar icons; running-window taskbar buttons can flash during the effect.' -ForegroundColor Yellow
    Write-Host 'Recovery shortcut created on the desktop and in the Start menu.' -ForegroundColor Green
    Write-Host 'This is still Firefox/Gecko under the hood; product binaries are not source-rebuilt.' -ForegroundColor Yellow
    Write-Host 'Because this is an in-place install, SearchEngines and forced extensions are managed installation-wide.' -ForegroundColor Yellow
    Read-Host 'Press Enter to finish'
    Invoke-JasperFinalTerminalGlitch
} catch {
    try { Write-Progress -Id 1 -Activity 'Jasper Browser — assembling installation' -Completed } catch {}
    Write-Host ''
    Write-Host '[BUILD FAILED] Jasper setup stopped at the first required error.' -ForegroundColor Red
    Write-Host "Installation failed: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host 'Review the message above. firefox.exe and profile data are not overwritten; if policies were already written, use the included uninstaller to restore the saved policy backup.' -ForegroundColor Yellow
    Read-Host 'Press Enter to exit'
    exit 1
}
