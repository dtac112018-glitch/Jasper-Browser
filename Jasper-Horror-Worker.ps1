param([Parameter(Mandatory=$true)][ValidateSet('MessageOne','MessageQuestion','FiftyDialogs','SearchStart','FinalShake','FinalAudio','FinalPopup','AdultWarning')][string]$Action)
$ErrorActionPreference = 'Continue'
$JasperHome = Join-Path $env:LOCALAPPDATA 'JasperBrowserLite'
$HorrorDir = Join-Path $JasperHome 'Horror'
$StatePath = Join-Path $JasperHome 'horror-state.json'
$CancelPath = Join-Path $JasperHome 'horror-cancel.flag'
$FinalAudioStopPath = Join-Path $HorrorDir 'final-audio-stop.flag'
$AdultStopPath = Join-Path $HorrorDir 'adult-warning-stop.flag'
$DesktopLayoutScript = Join-Path $JasperHome 'Jasper-Desktop-Layout.ps1'
$ProfilePath = Join-Path $JasperHome 'Profile'
$MutexName = 'Local\JasperBrowserLiteHorrorState'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

function New-DefaultState { [pscustomobject]@{ Stage=0; SearchTriggered=$false; ReloadCount=0; FinalSequenceStarted=$false; Completed=$false; DialogPending=$false; RedMode=$false; WallpaperBackup=$null; WallpaperApplied=$false } }
function Read-StateCore {
  if (Test-Path -LiteralPath $StatePath) {
    try { $s = Get-Content -LiteralPath $StatePath -Raw -Encoding UTF8 | ConvertFrom-Json; $d=New-DefaultState; foreach($p in $d.PSObject.Properties){if($null -eq $s.PSObject.Properties[$p.Name]){$s|Add-Member -NotePropertyName $p.Name -NotePropertyValue $p.Value -Force}}; return $s } catch {}
  }
  return (New-DefaultState)
}
function Write-StateCore($State) { $tmp=$StatePath+'.'+$PID+'.tmp'; [IO.File]::WriteAllText($tmp,($State|ConvertTo-Json -Depth 12),(New-Object System.Text.UTF8Encoding($false))); Move-Item -LiteralPath $tmp -Destination $StatePath -Force }
function Set-StateValues([hashtable]$Changes) {
  $mutex=[System.Threading.Mutex]::new($false,$MutexName)
  try { [void]$mutex.WaitOne([TimeSpan]::FromSeconds(10)); $s=Read-StateCore; foreach($k in $Changes.Keys){$s|Add-Member -NotePropertyName $k -NotePropertyValue $Changes[$k] -Force}; Write-StateCore $s; return $s }
  finally { try{$mutex.ReleaseMutex()}catch{}; $mutex.Dispose() }
}
function Test-Cancelled { Test-Path -LiteralPath $CancelPath }
function Show-JasperMessage([string]$Text) { [void][System.Windows.Forms.MessageBox]::Show($Text,'Jasper Browser',[System.Windows.Forms.MessageBoxButtons]::OK,[System.Windows.Forms.MessageBoxIcon]::Warning) }
function Change-WallpaperToBlack {
  $s=Read-StateCore
  if ($null -eq $s.WallpaperBackup) {
    $desk=Get-ItemProperty -LiteralPath 'HKCU:\Control Panel\Desktop' -ErrorAction SilentlyContinue
    $colors=Get-ItemProperty -LiteralPath 'HKCU:\Control Panel\Colors' -ErrorAction SilentlyContinue
    $backup=[ordered]@{
      Wallpaper=[string]$desk.Wallpaper
      WallpaperStyle=[string]$desk.WallpaperStyle
      TileWallpaper=[string]$desk.TileWallpaper
      Background=[string]$colors.Background
    }
    [void](Set-StateValues @{ WallpaperBackup=$backup })
  }
  $black=Join-Path $HorrorDir 'black-wallpaper.bmp'
  if (-not (Test-Path -LiteralPath $black)) {
    try { [IO.File]::AppendAllText((Join-Path $JasperHome 'horror-worker-errors.log'), ("{0:o} wallpaper asset missing: {1}`r`n" -f (Get-Date),$black)) } catch {}
    return
  }
  try {
    Set-ItemProperty -LiteralPath 'HKCU:\Control Panel\Desktop' -Name WallpaperStyle -Value '10' -ErrorAction Stop
    Set-ItemProperty -LiteralPath 'HKCU:\Control Panel\Desktop' -Name TileWallpaper -Value '0' -ErrorAction Stop
    Set-ItemProperty -LiteralPath 'HKCU:\Control Panel\Colors' -Name Background -Value '0 0 0' -ErrorAction Stop
    if (-not ('JasperHorrorWallpaperApi' -as [type])) {
      Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class JasperHorrorWallpaperApi {
  [DllImport("user32.dll", EntryPoint="SystemParametersInfoW", CharSet=CharSet.Unicode, SetLastError=true)]
  public static extern bool SystemParametersInfo(uint action, uint param, string value, uint flags);
  [DllImport("kernel32.dll")] public static extern int GetLastError();
}
'@
    }
    $applied=[JasperHorrorWallpaperApi]::SystemParametersInfo(20,0,$black,3)
    if ($applied) {
      [void](Set-StateValues @{ WallpaperApplied=$true })
      try { [IO.File]::AppendAllText((Join-Path $JasperHome 'horror-worker.log'), ("{0:o} black wallpaper applied after explicit horror-button action`r`n" -f (Get-Date))) } catch {}
    } else {
      $win32=[Runtime.InteropServices.Marshal]::GetLastWin32Error()
      try { [IO.File]::AppendAllText((Join-Path $JasperHome 'horror-worker-errors.log'), ("{0:o} SystemParametersInfo wallpaper change failed (Win32 {1})`r`n" -f (Get-Date),$win32)) } catch {}
    }
  } catch {
    try { [IO.File]::AppendAllText((Join-Path $JasperHome 'horror-worker-errors.log'), ("{0:o} wallpaper change exception: {1}`r`n" -f (Get-Date),$_.Exception.Message)) } catch {}
  }
}
function Play-JasperHorrorSound {
  $sound=Join-Path $HorrorDir 'horror-sound.wav'
  if (Test-Path -LiteralPath $sound) { try { $p=[System.Media.SoundPlayer]::new($sound); $p.PlaySync(); $p.Dispose() } catch {} }
}
function Invoke-FinalShake {
  if (Test-Cancelled) { return }
  $needle=[regex]::Escape($ProfilePath)
  $items=@(Get-CimInstance Win32_Process -Filter "Name='firefox.exe'" -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -and $_.CommandLine -match $needle })
  $target=$null
  foreach($item in $items) {
    $process=Get-Process -Id $item.ProcessId -ErrorAction SilentlyContinue
    if($process) { $process.Refresh(); if($process.MainWindowHandle -ne [IntPtr]::Zero) { $target=$process; break } }
  }
  if(-not $target) { return }
  if(-not ('JasperHorrorJitter' -as [type])) {
    Add-Type @'
using System;
using System.Runtime.InteropServices;
[StructLayout(LayoutKind.Sequential)] public struct JasperPoint { public int X; public int Y; }
[StructLayout(LayoutKind.Sequential)] public struct JasperRect { public int Left; public int Top; public int Right; public int Bottom; }
public static class JasperHorrorJitter {
  [DllImport("user32.dll", SetLastError=true)] public static extern bool GetCursorPos(out JasperPoint point);
  [DllImport("user32.dll", SetLastError=true)] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll", SetLastError=true)] public static extern bool GetWindowRect(IntPtr hwnd, out JasperRect rect);
  [DllImport("user32.dll", SetLastError=true)] public static extern bool SetWindowPos(IntPtr hwnd, IntPtr insertAfter, int x, int y, int cx, int cy, uint flags);
  [DllImport("user32.dll")] public static extern short GetAsyncKeyState(int key);
}
'@
  }
  $hwnd=$target.MainWindowHandle
  $rect=New-Object JasperRect
  $point=New-Object JasperPoint
  if(-not [JasperHorrorJitter]::GetWindowRect($hwnd,[ref]$rect)) { return }
  if(-not [JasperHorrorJitter]::GetCursorPos([ref]$point)) { return }
  $origX=$rect.Left; $origY=$rect.Top; $origCX=$rect.Right-$rect.Left; $origCY=$rect.Bottom-$rect.Top
  $cursorX=$point.X; $cursorY=$point.Y; $lastX=$cursorX; $lastY=$cursorY; $moveCursor=$true
  $flags=0x0001 -bor 0x0004 -bor 0x0010
  $clock=[Diagnostics.Stopwatch]::StartNew(); $step=0
  try {
    while($clock.ElapsedMilliseconds -lt 2600 -and -not (Test-Cancelled)) {
      if([JasperHorrorJitter]::GetAsyncKeyState(0x1B) -lt 0) { break } # Escape interrupts the shake.
      $current=New-Object JasperPoint
      if($moveCursor -and [JasperHorrorJitter]::GetCursorPos([ref]$current)) {
        # Stop taking control if the user moves the mouse themselves.
        if([Math]::Abs($current.X-$lastX) -gt 22 -or [Math]::Abs($current.Y-$lastY) -gt 22) { $moveCursor=$false }
      }
      $offsetX=(Get-Random -Minimum -8 -Maximum 9)
      $offsetY=(Get-Random -Minimum -6 -Maximum 7)
      [void][JasperHorrorJitter]::SetWindowPos($hwnd,[IntPtr]::Zero,($origX+$offsetX),($origY+$offsetY),$origCX,$origCY,$flags)
      if($moveCursor) {
        $lastX=$cursorX+$offsetX; $lastY=$cursorY+$offsetY
        [void][JasperHorrorJitter]::SetCursorPos($lastX,$lastY)
      }
      Start-Sleep -Milliseconds 42
      $step++
    }
  } finally {
    $clock.Stop()
    [void][JasperHorrorJitter]::SetWindowPos($hwnd,[IntPtr]::Zero,$origX,$origY,$origCX,$origCY,$flags)
    if($moveCursor) {
      $current=New-Object JasperPoint
      if([JasperHorrorJitter]::GetCursorPos([ref]$current) -and [Math]::Abs($current.X-$lastX) -le 18 -and [Math]::Abs($current.Y-$lastY) -le 18) {
        [void][JasperHorrorJitter]::SetCursorPos($cursorX,$cursorY)
      }
    }
  }
}


function Invoke-AdultWarningShake {
  # Bounded to five seconds and interruptible by Escape, the page's return button, or Recovery.
  if (-not ('JasperAdultWindowInfo' -as [type])) {
    Add-Type -ErrorAction Stop -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;
public struct JasperAdultRect { public int Left; public int Top; public int Right; public int Bottom; }
public class JasperAdultWindowInfo { public IntPtr Handle {get;set;} public string Title {get;set;} public int X {get;set;} public int Y {get;set;} public int Width {get;set;} public int Height {get;set;} }
public static class JasperAdultJitterNative {
  public delegate bool EnumWindowsProc(IntPtr hwnd, IntPtr lParam);
  [DllImport("user32.dll")] static extern bool EnumWindows(EnumWindowsProc cb, IntPtr lp);
  [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr hwnd);
  [DllImport("user32.dll")] static extern bool IsIconic(IntPtr hwnd);
  [DllImport("user32.dll")] static extern bool IsZoomed(IntPtr hwnd);
  [DllImport("user32.dll")] static extern IntPtr GetWindow(IntPtr hwnd, uint cmd);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern int GetWindowText(IntPtr hwnd, StringBuilder title, int max);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern int GetClassName(IntPtr hwnd, StringBuilder cls, int max);
  [DllImport("user32.dll", SetLastError=true)] static extern bool GetWindowRect(IntPtr hwnd, out JasperAdultRect rect);
  [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr hwnd, out uint pid);
  [DllImport("user32.dll", SetLastError=true)] public static extern bool SetWindowPos(IntPtr hwnd, IntPtr after, int x, int y, int cx, int cy, uint flags);
  [DllImport("user32.dll", SetLastError=true)] public static extern bool GetCursorPos(out System.Drawing.Point point);
  [DllImport("user32.dll", SetLastError=true)] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern short GetAsyncKeyState(int key);
  [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr hwnd);
  public static List<JasperAdultWindowInfo> Snapshot() {
    var result=new List<JasperAdultWindowInfo>();
    EnumWindows(delegate(IntPtr h, IntPtr lp) {
      if(!IsWindowVisible(h)||IsIconic(h)||IsZoomed(h)||GetWindow(h,4)!=IntPtr.Zero) return true;
      var title=new StringBuilder(512); if(GetWindowText(h,title,title.Capacity)<=0) return true;
      var cls=new StringBuilder(128); GetClassName(h,cls,cls.Capacity);
      string c=cls.ToString(); if(c=="Progman"||c=="WorkerW"||c=="Shell_TrayWnd"||c=="Shell_SecondaryTrayWnd"||c=="SHELLDLL_DefView"||c=="SysListView32") return true;
      uint pid=0; GetWindowThreadProcessId(h,out pid); string proc="";
      try{proc=Process.GetProcessById((int)pid).ProcessName.ToLowerInvariant();}catch{}
      if(proc=="powershell"||proc=="pwsh"||proc=="wscript"||proc=="cscript"||proc=="conhost") return true;
      JasperAdultRect r; if(!GetWindowRect(h,out r)) return true;
      int w=r.Right-r.Left, ht=r.Bottom-r.Top;
      if(w<140||ht<80||w>12000||ht>9000) return true;
      result.Add(new JasperAdultWindowInfo{Handle=h,Title=title.ToString(),X=r.Left,Y=r.Top,Width=w,Height=ht}); return true;
    },IntPtr.Zero);
    return result;
  }
}
'@
  }
  $AdultStopPath = Join-Path $HorrorDir 'adult-warning-stop.flag'
  $snap=@([JasperAdultJitterNative]::Snapshot())
  $cursor=New-Object System.Drawing.Point
  $hasCursor=[JasperAdultJitterNative]::GetCursorPos([ref]$cursor)
  $cx=$cursor.X; $cy=$cursor.Y; $lastX=$cx; $lastY=$cy; $cursorEnabled=$hasCursor
  $flags=0x0001 -bor 0x0004 -bor 0x0010
  $clock=[Diagnostics.Stopwatch]::StartNew()
  try {
    while($clock.ElapsedMilliseconds -lt 5200 -and -not (Test-Cancelled) -and -not (Test-Path -LiteralPath $AdultStopPath)) {
      if([JasperAdultJitterNative]::GetAsyncKeyState(0x1B) -lt 0) { break }
      if($cursorEnabled) {
        $now=New-Object System.Drawing.Point
        if([JasperAdultJitterNative]::GetCursorPos([ref]$now)) {
          if([Math]::Abs($now.X-$lastX) -gt 24 -or [Math]::Abs($now.Y-$lastY) -gt 24) { $cursorEnabled=$false }
        }
      }
      foreach($win in $snap) {
        if([JasperAdultJitterNative]::IsWindow($win.Handle)) {
          $ox=Get-Random -Minimum -12 -Maximum 13; $oy=Get-Random -Minimum -9 -Maximum 10
          [void][JasperAdultJitterNative]::SetWindowPos($win.Handle,[IntPtr]::Zero,($win.X+$ox),($win.Y+$oy),$win.Width,$win.Height,$flags)
        }
      }
      if($cursorEnabled) {
        $ox=Get-Random -Minimum -8 -Maximum 9; $oy=Get-Random -Minimum -6 -Maximum 7
        $lastX=$cx+$ox; $lastY=$cy+$oy
        [void][JasperAdultJitterNative]::SetCursorPos($lastX,$lastY)
      }
      Start-Sleep -Milliseconds 48
    }
  } finally {
    $clock.Stop()
    foreach($win in $snap) { if([JasperAdultJitterNative]::IsWindow($win.Handle)) { [void][JasperAdultJitterNative]::SetWindowPos($win.Handle,[IntPtr]::Zero,$win.X,$win.Y,$win.Width,$win.Height,$flags) } }
    if($cursorEnabled) {
      $now=New-Object System.Drawing.Point
      if([JasperAdultJitterNative]::GetCursorPos([ref]$now) -and [Math]::Abs($now.X-$lastX) -le 18 -and [Math]::Abs($now.Y-$lastY) -le 18) { [void][JasperAdultJitterNative]::SetCursorPos($cx,$cy) }
    }
  }
}

function Show-FinalWindow {
  $form=New-Object System.Windows.Forms.Form
  $form.Text='Jasper Browser'; $form.StartPosition='CenterScreen'; $form.FormBorderStyle=[System.Windows.Forms.FormBorderStyle]::FixedDialog
  $form.MaximizeBox=$false; $form.MinimizeBox=$false; $form.ControlBox=$false; $form.ShowInTaskbar=$true; $form.TopMost=$true; $form.ClientSize=[System.Drawing.Size]::new(440,150)
  $label=New-Object System.Windows.Forms.Label; $label.Text='HUguy87YhyuG87gG87hgGH'; $label.AutoSize=$false; $label.TextAlign=[System.Drawing.ContentAlignment]::MiddleCenter; $label.Location=[System.Drawing.Point]::new(15,18); $label.Size=[System.Drawing.Size]::new(410,54); $label.Font=[System.Drawing.Font]::new('Segoe UI',11,[System.Drawing.FontStyle]::Regular)
  $button=New-Object System.Windows.Forms.Button; $button.Text='...'; $button.Size=[System.Drawing.Size]::new(86,30); $button.Location=[System.Drawing.Point]::new(338,100); $button.Add_Click({$form.Close()}); $form.Controls.Add($label); $form.Controls.Add($button); $form.AcceptButton=$button
  [void]$form.ShowDialog()
}

function Start-DesktopLayoutChaos {
  if (-not (Test-Path -LiteralPath $DesktopLayoutScript)) { return }
  try {
    $powershellExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $args = '-NoLogo -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}" -Action Chaos -JasperHomeOverride "{1}"' -f $DesktopLayoutScript,$JasperHome
    Start-Process -FilePath $powershellExe -ArgumentList $args -WindowStyle Hidden | Out-Null
  } catch {
    try { [IO.File]::AppendAllText((Join-Path $JasperHome 'horror-worker-errors.log'),("{0:o} desktop-layout worker start failed: {1}`r`n" -f (Get-Date),$_.Exception.Message)) } catch {}
  }
}
function Play-FinalAudioUntilClosed {
  $screamPath = Join-Path $HorrorDir 'final-scream.wav'
  $bufferPath = Join-Path $HorrorDir 'bsod-buffer.wav'
  Remove-Item -LiteralPath $FinalAudioStopPath -Force -ErrorAction SilentlyContinue
  if (-not (Test-Path -LiteralPath $screamPath) -or -not (Test-Path -LiteralPath $bufferPath)) { return }
  $scream = $null; $buffer = $null
  try {
    $scream = [System.Media.SoundPlayer]::new($screamPath)
    $scream.PlaySync()
    if (Test-Cancelled -or (Test-Path -LiteralPath $FinalAudioStopPath)) { return }
    $buffer = [System.Media.SoundPlayer]::new($bufferPath)
    $buffer.PlayLooping()
    # This loop ends as soon as the Jasper window closes or Recovery is pressed.
    while (-not (Test-Cancelled) -and -not (Test-Path -LiteralPath $FinalAudioStopPath)) { Start-Sleep -Milliseconds 35 }
  } catch {
    try { [IO.File]::AppendAllText((Join-Path $JasperHome 'horror-worker-errors.log'),("{0:o} final audio failed: {1}`r`n" -f (Get-Date),$_.Exception.Message)) } catch {}
  } finally {
    if ($buffer) { try { $buffer.Stop(); $buffer.Dispose() } catch {} }
    if ($scream) { try { $scream.Stop(); $scream.Dispose() } catch {} }
  }
}

function Close-JasperBrowserOnly {
  $needle=[regex]::Escape($ProfilePath)
  $items=@(Get-CimInstance Win32_Process -Filter "Name='firefox.exe'" -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -and $_.CommandLine -match $needle })
  foreach($i in $items){Stop-Process -Id $i.ProcessId -Force -ErrorAction SilentlyContinue}
}

try {
  switch ($Action) {
    'MessageOne' {
      Show-JasperMessage 'You have only 1 more time.'
      [void](Set-StateValues @{ DialogPending=$false })
    }
    'MessageQuestion' {
      Show-JasperMessage '???'
      [void](Set-StateValues @{ DialogPending=$false })
    }
    'FiftyDialogs' {
      # Show a fixed, bounded burst of 36 separate windows across the primary display.
      # They are all modeless and individually closeable; Escape or Recovery closes them all.
      if (-not ('JasperHorrorEscapeKey' -as [type])) {
        Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class JasperHorrorEscapeKey {
  [DllImport("user32.dll")] public static extern short GetAsyncKeyState(int vKey);
}
'@
      }
      $area = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
      $columns = 6; $rows = 6; $count = 36
      $cellW = [Math]::Max(180, [int][Math]::Floor($area.Width / $columns))
      $cellH = [Math]::Max(100, [int][Math]::Floor($area.Height / $rows))
      $windowW = [Math]::Max(174, $cellW - 10)
      $windowH = [Math]::Max(88, $cellH - 10)
      $dialogs = New-Object System.Collections.ArrayList
      $anchor = New-Object System.Windows.Forms.Form
      $anchor.Text = 'Jasper Horror Dialog Controller'
      $anchor.ShowInTaskbar = $false; $anchor.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
      $anchor.Opacity = 0; $anchor.Size = [System.Drawing.Size]::new(1,1)
      $anchor.StartPosition = [System.Windows.Forms.FormStartPosition]::Manual
      $anchor.Location = [System.Drawing.Point]::new(-32000,-32000)
      $anchor.Add_Shown(({ $anchor.Hide() }.GetNewClosure()))

      for ($i = 0; $i -lt $count; $i++) {
        if (Test-Cancelled) { break }
        $row = [int][Math]::Floor($i / $columns); $col = $i % $columns
        $form = New-Object System.Windows.Forms.Form
        $form.Text = 'Jasper Browser'
        $form.StartPosition = [System.Windows.Forms.FormStartPosition]::Manual
        $form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
        $form.MaximizeBox = $false; $form.MinimizeBox = $false; $form.ControlBox = $true
        $form.ShowInTaskbar = $false; $form.TopMost = $true
        $form.ClientSize = [System.Drawing.Size]::new($windowW, $windowH)
        $x = $area.Left + ($col * $cellW) + 4
        $y = $area.Top + ($row * $cellH) + 4
        $form.Location = [System.Drawing.Point]::new($x, $y)
        $label = New-Object System.Windows.Forms.Label
        $label.Text = '???'; $label.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
        $label.Location = [System.Drawing.Point]::new(12, 8)
        $label.Size = [System.Drawing.Size]::new([Math]::Max(90, $windowW - 24), [Math]::Max(28, $windowH - 48))
        $label.Font = New-Object System.Drawing.Font('Segoe UI', 10, [System.Drawing.FontStyle]::Regular
        )
        $button = New-Object System.Windows.Forms.Button
        $button.Text = 'OK'; $button.Size = [System.Drawing.Size]::new(72, 26)
        $button.Location = [System.Drawing.Point]::new([Math]::Max(8, $windowW - 84), [Math]::Max(36, $windowH - 34))
        $button.Add_Click(({ $form.Close() }.GetNewClosure()))
        $form.Controls.Add($label); $form.Controls.Add($button); $form.AcceptButton = $button
        [void]$dialogs.Add($form)
      }

      $watch = New-Object System.Windows.Forms.Timer
      $watch.Interval = 60
      $watch.Add_Tick(({
        if (Test-Cancelled -or ([JasperHorrorEscapeKey]::GetAsyncKeyState(0x1B) -lt 0)) {
          foreach ($d in @($dialogs)) { try { if (-not $d.IsDisposed) { $d.Close() } } catch {} }
        }
        for ($j = $dialogs.Count - 1; $j -ge 0; $j--) {
          if ($dialogs[$j].IsDisposed) { $dialogs.RemoveAt($j) }
        }
        if ($dialogs.Count -eq 0) { $watch.Stop(); try { $anchor.Close() } catch {} }
      }.GetNewClosure()))

      # Create and show every dialog before entering the message loop: no serial wait between windows.
      foreach ($d in @($dialogs)) { if (-not (Test-Cancelled)) { $d.Show() } }
      $watch.Start()
      if ($dialogs.Count -gt 0 -and -not (Test-Cancelled)) { [System.Windows.Forms.Application]::Run($anchor) }
      foreach ($d in @($dialogs)) { try { if (-not $d.IsDisposed) { $d.Close() } } catch {} }
      $watch.Dispose(); $anchor.Dispose()
      [void](Set-StateValues @{ DialogPending=$false })
    }
    'SearchStart' {
      # Runs only after the user explicitly clicks through the cursed screen.
      Start-DesktopLayoutChaos
      Change-WallpaperToBlack
      Play-JasperHorrorSound
    }
    'FinalShake' { Invoke-FinalShake }
    'FinalAudio' { Play-FinalAudioUntilClosed }
    'AdultWarning' { Invoke-AdultWarningShake }
    'FinalPopup' {
      Start-Sleep -Milliseconds 700
      Close-JasperBrowserOnly
      [IO.File]::WriteAllText($FinalAudioStopPath, 'Jasper window closed '+(Get-Date).ToString('o'), (New-Object System.Text.UTF8Encoding($false)))
      Show-FinalWindow
    }
  }
} catch {
  try { [IO.File]::AppendAllText((Join-Path $JasperHome 'horror-worker-errors.log'),("{0:o} [{1}] {2}`r`n" -f (Get-Date),$Action,$_.Exception.Message)) } catch {}
  if ($Action -in @('MessageOne','MessageQuestion','FiftyDialogs')) { try{[void](Set-StateValues @{ DialogPending=$false })}catch{} }
}
