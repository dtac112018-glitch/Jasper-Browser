param([Parameter(Mandatory=$true)][ValidateSet('Chaos','Restore')][string]$Action,[string]$JasperHomeOverride='')
$ErrorActionPreference = 'Continue'
if ([string]::IsNullOrWhiteSpace($JasperHomeOverride)) { $JasperHome = Join-Path $env:LOCALAPPDATA 'JasperBrowserLite' } else { $JasperHome = [IO.Path]::GetFullPath($JasperHomeOverride) }
$SnapshotPath = Join-Path $JasperHome 'desktop-layout-backup.json'
$LogPath = Join-Path $JasperHome 'desktop-layout.log'
$BrowserProfile = Join-Path $JasperHome 'Profile'
$StopPath = Join-Path $JasperHome 'desktop-layout-stop.flag'
$ActivePath = Join-Path $JasperHome 'desktop-layout-active.flag'
$UsedPath = Join-Path $JasperHome 'desktop-chaos-consumed.flag'
Add-Type -AssemblyName System.Windows.Forms

$nativeSource = @'
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;

[StructLayout(LayoutKind.Sequential)] public struct JasperPoint { public int X; public int Y; }
[StructLayout(LayoutKind.Sequential)] public struct JasperRect { public int Left; public int Top; public int Right; public int Bottom; }
public class JasperIconPosition { public int Index { get; set; } public int X { get; set; } public int Y { get; set; } }
public class JasperWindowPosition { public long Handle { get; set; } public string Title { get; set; } public string ProcessName { get; set; } public int X { get; set; } public int Y { get; set; } public int Width { get; set; } public int Height { get; set; } }
public delegate bool JasperEnumWindowsProc(IntPtr hWnd, IntPtr lParam);
public static class JasperDesktopNative {
  const uint PROCESS_VM_OPERATION=0x0008, PROCESS_VM_READ=0x0010, PROCESS_VM_WRITE=0x0020, PROCESS_QUERY_INFORMATION=0x0400;
  const uint MEM_COMMIT=0x1000, MEM_RESERVE=0x2000, MEM_RELEASE=0x8000, PAGE_READWRITE=0x04;
  const uint SWP_NOSIZE=0x0001, SWP_NOZORDER=0x0004, SWP_NOACTIVATE=0x0010, SWP_NOMOVE=0x0002, SWP_FRAMECHANGED=0x0020;
  const int GWL_STYLE=-16; const int LVS_AUTOARRANGE=0x0100;
  const uint LVM_GETITEMCOUNT=0x1004, LVM_GETITEMPOSITION=0x1010, LVM_SETITEMPOSITION32=0x1031;
  [StructLayout(LayoutKind.Sequential)] struct FLASHWINFO { public uint cbSize; public IntPtr hwnd; public uint dwFlags; public uint uCount; public uint dwTimeout; }
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern IntPtr FindWindow(string cls, string title);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern IntPtr FindWindowEx(IntPtr parent, IntPtr after, string cls, string title);
  [DllImport("user32.dll")] static extern bool EnumWindows(JasperEnumWindowsProc callback, IntPtr lParam);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern int GetClassName(IntPtr hwnd, StringBuilder text, int maxCount);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern int GetWindowText(IntPtr hwnd, StringBuilder text, int maxCount);
  [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr hwnd);
  [DllImport("user32.dll")] static extern bool IsIconic(IntPtr hwnd);
  [DllImport("user32.dll")] static extern bool IsZoomed(IntPtr hwnd);
  [DllImport("user32.dll")] static extern IntPtr GetWindow(IntPtr hwnd, uint cmd);
  [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr hwnd, out JasperRect rect);
  [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr hwnd, out uint pid);
  [DllImport("user32.dll", SetLastError=true)] static extern bool SetWindowPos(IntPtr hwnd, IntPtr after, int x, int y, int cx, int cy, uint flags);
  [DllImport("user32.dll", EntryPoint="GetWindowLongW", SetLastError=true)] static extern int GetWindowLong(IntPtr hwnd, int index);
  [DllImport("user32.dll", EntryPoint="SetWindowLongW", SetLastError=true)] static extern int SetWindowLong(IntPtr hwnd, int index, int value);
  [DllImport("user32.dll")] static extern IntPtr SendMessage(IntPtr hwnd, uint msg, IntPtr wParam, IntPtr lParam);
  [DllImport("kernel32.dll", SetLastError=true)] static extern IntPtr OpenProcess(uint access, bool inherit, uint pid);
  [DllImport("kernel32.dll", SetLastError=true)] static extern IntPtr VirtualAllocEx(IntPtr process, IntPtr address, UIntPtr size, uint allocType, uint protect);
  [DllImport("kernel32.dll", SetLastError=true)] static extern bool VirtualFreeEx(IntPtr process, IntPtr address, UIntPtr size, uint freeType);
  [DllImport("kernel32.dll", SetLastError=true)] static extern bool ReadProcessMemory(IntPtr process, IntPtr address, out JasperPoint buffer, int size, out IntPtr read);
  [DllImport("kernel32.dll", SetLastError=true)] static extern bool WriteProcessMemory(IntPtr process, IntPtr address, ref JasperPoint buffer, int size, out IntPtr written);
  [DllImport("kernel32.dll", SetLastError=true)] static extern bool CloseHandle(IntPtr handle);
  [DllImport("user32.dll", SetLastError=true)] static extern bool FlashWindowEx(ref FLASHWINFO info);
  [DllImport("user32.dll")] static extern short GetAsyncKeyState(int vKey);
  public static bool EscapePressed() { return (GetAsyncKeyState(0x1B) & 0x8000) != 0; }

  static IntPtr GetDesktopListView() {
    IntPtr progman=FindWindow("Progman", null);
    IntPtr view=FindWindowEx(progman, IntPtr.Zero, "SHELLDLL_DefView", null);
    if(view==IntPtr.Zero) {
      JasperEnumWindowsProc cb = delegate(IntPtr w, IntPtr unused) {
        StringBuilder cls = new StringBuilder(128); GetClassName(w,cls,cls.Capacity);
        if(cls.ToString()=="WorkerW") { view=FindWindowEx(w,IntPtr.Zero,"SHELLDLL_DefView",null); if(view!=IntPtr.Zero) return false; }
        return true;
      };
      EnumWindows(cb,IntPtr.Zero);
    }
    if(view==IntPtr.Zero) return IntPtr.Zero;
    return FindWindowEx(view,IntPtr.Zero,"SysListView32","FolderView");
  }
  public static List<JasperIconPosition> GetDesktopIconPositions() {
    List<JasperIconPosition> result=new List<JasperIconPosition>();
    IntPtr list=GetDesktopListView();
    if(list==IntPtr.Zero) throw new InvalidOperationException("The Windows desktop icon list was not found; Explorer may still be starting.");
    uint pid=0; GetWindowThreadProcessId(list,out pid);
    if(pid==0) throw new InvalidOperationException("Could not identify the Windows desktop shell process.");
    IntPtr process=OpenProcess(PROCESS_VM_OPERATION|PROCESS_VM_READ|PROCESS_VM_WRITE|PROCESS_QUERY_INFORMATION,false,pid);
    if(process==IntPtr.Zero) throw new InvalidOperationException("Could not access the Windows desktop icon list.");
    IntPtr remote=IntPtr.Zero;
    try {
      int size=Marshal.SizeOf(typeof(JasperPoint));
      remote=VirtualAllocEx(process,IntPtr.Zero,new UIntPtr((uint)size),MEM_COMMIT|MEM_RESERVE,PAGE_READWRITE);
      if(remote==IntPtr.Zero) throw new InvalidOperationException("Could not allocate temporary memory for desktop layout capture.");
      int count=SendMessage(list,LVM_GETITEMCOUNT,IntPtr.Zero,IntPtr.Zero).ToInt32();
      for(int i=0;i<count;i++) {
        SendMessage(list,LVM_GETITEMPOSITION,new IntPtr(i),remote);
        JasperPoint point; IntPtr read;
        if(ReadProcessMemory(process,remote,out point,size,out read)) result.Add(new JasperIconPosition{Index=i,X=point.X,Y=point.Y});
      }
      return result;
    } finally { if(remote!=IntPtr.Zero) VirtualFreeEx(process,remote,UIntPtr.Zero,MEM_RELEASE); CloseHandle(process); }
  }
  public static int GetDesktopIconStyle() {
    IntPtr list=GetDesktopListView(); if(list==IntPtr.Zero) throw new InvalidOperationException("The desktop icon list was not found while reading its style.");
    return GetWindowLong(list,GWL_STYLE);
  }
  public static bool SetDesktopIconStyle(int style) {
    IntPtr list=GetDesktopListView(); if(list==IntPtr.Zero) return false;
    SetWindowLong(list,GWL_STYLE,style);
    SetWindowPos(list,IntPtr.Zero,0,0,0,0,SWP_NOMOVE|SWP_NOSIZE|SWP_NOZORDER|SWP_NOACTIVATE|SWP_FRAMECHANGED);
    return GetWindowLong(list,GWL_STYLE)==style;
  }
  public static bool SetDesktopAutoArrange(bool enabled) {
    int style=GetDesktopIconStyle();
    int next=enabled ? (style|LVS_AUTOARRANGE) : (style & ~LVS_AUTOARRANGE);
    return SetDesktopIconStyle(next);
  }
  public static bool SetDesktopIconPosition(int index,int x,int y) {
    IntPtr list=GetDesktopListView(); if(list==IntPtr.Zero || x<0 || y<0 || x>32767 || y>32767) return false;
    uint pid=0; GetWindowThreadProcessId(list,out pid); if(pid==0) return false;
    IntPtr process=OpenProcess(PROCESS_VM_OPERATION|PROCESS_VM_WRITE|PROCESS_VM_READ|PROCESS_QUERY_INFORMATION,false,pid);
    if(process==IntPtr.Zero) return false;
    IntPtr remote=IntPtr.Zero;
    try {
      int size=Marshal.SizeOf(typeof(JasperPoint));
      remote=VirtualAllocEx(process,IntPtr.Zero,new UIntPtr((uint)size),MEM_COMMIT|MEM_RESERVE,PAGE_READWRITE);
      if(remote==IntPtr.Zero) return false;
      JasperPoint point=new JasperPoint{X=x,Y=y}; IntPtr written;
      if(!WriteProcessMemory(process,remote,ref point,size,out written) || written.ToInt64()<size) return false;
      SendMessage(list,LVM_SETITEMPOSITION32,new IntPtr(index),remote);
      return true;
    } finally { if(remote!=IntPtr.Zero) VirtualFreeEx(process,remote,UIntPtr.Zero,MEM_RELEASE); CloseHandle(process); }
  }
  public static List<JasperWindowPosition> GetNormalWindows(string excludedTitle) {
    List<JasperWindowPosition> result=new List<JasperWindowPosition>();
    JasperEnumWindowsProc cb = delegate(IntPtr hwnd, IntPtr unused) {
      if(!IsWindowVisible(hwnd) || IsIconic(hwnd) || IsZoomed(hwnd) || GetWindow(hwnd,4)!=IntPtr.Zero) return true; // skip owned/hidden/minimized/maximized windows
      StringBuilder title=new StringBuilder(512); GetWindowText(hwnd,title,title.Capacity);
      if(title.Length==0 || title.ToString().IndexOf(excludedTitle,StringComparison.OrdinalIgnoreCase)>=0) return true;
      StringBuilder cls=new StringBuilder(128); GetClassName(hwnd,cls,cls.Capacity);
      string c=cls.ToString();
      if(c=="Progman"||c=="WorkerW"||c=="Shell_TrayWnd"||c=="Shell_SecondaryTrayWnd"||c=="SHELLDLL_DefView"||c=="SysListView32") return true;
      JasperRect r; if(!GetWindowRect(hwnd,out r)) return true;
      int w=r.Right-r.Left, h=r.Bottom-r.Top; if(w<150||h<90||w>12000||h>9000) return true;
      uint pid=0; GetWindowThreadProcessId(hwnd,out pid); string proc="";
      try { proc=Process.GetProcessById((int)pid).ProcessName; } catch {}
      if(proc=="powershell"||proc=="pwsh"||proc=="wscript"||proc=="cscript"||proc=="conhost") return true;
      result.Add(new JasperWindowPosition{Handle=hwnd.ToInt64(),Title=title.ToString(),ProcessName=proc,X=r.Left,Y=r.Top,Width=w,Height=h});
      return true;
    };
    EnumWindows(cb,IntPtr.Zero); return result;
  }
  public static bool MoveWindow(long handle,int x,int y) { return SetWindowPos(new IntPtr(handle),IntPtr.Zero,x,y,0,0,SWP_NOSIZE|SWP_NOZORDER|SWP_NOACTIVATE); }
  public static void FlashTaskbarButton(long handle,uint count) {
    FLASHWINFO info=new FLASHWINFO(); info.cbSize=(uint)Marshal.SizeOf(typeof(FLASHWINFO)); info.hwnd=new IntPtr(handle); info.dwFlags=3; info.uCount=count; info.dwTimeout=120;
    FlashWindowEx(ref info);
  }
}
'@

function Write-DesktopLog([string]$Message) {
  try { [IO.File]::AppendAllText($LogPath,("{0:o} {1}`r`n" -f (Get-Date),$Message)) } catch {}
}
function Test-JasperBrowserAlive {
  try {
    $needle=[regex]::Escape($BrowserProfile)
    $items=@(Get-CimInstance Win32_Process -Filter "Name='firefox.exe'" -ErrorAction Stop | Where-Object { $_.CommandLine -and $_.CommandLine -match $needle })
    return ($items.Count -gt 0)
  } catch {
    Write-DesktopLog ("browser process check failed: {0}" -f $_.Exception.Message)
    # Fail safe: stop the desktop effect if process status cannot be verified.
    return $false
  }
}
function Get-ShuffledIconTargets($items) {
  $targets=@($items | ForEach-Object { [pscustomobject]@{X=[int]$_.X;Y=[int]$_.Y} })
  if($targets.Count -gt 1) {
    $offset=Get-Random -Minimum 1 -Maximum $targets.Count
    $rotated=@(); for($i=0;$i -lt $targets.Count;$i++) { $rotated += $targets[($i+$offset) % $targets.Count] }
    # Further shuffle the rotated positions for variety while ensuring a nonzero permutation.
    $shuffled=@($rotated | Sort-Object { Get-Random })
    if($shuffled.Count -eq $targets.Count) {
      $same=$true
      for($i=0;$i -lt $targets.Count;$i++) { if([int]$shuffled[$i].X -ne [int]$targets[$i].X -or [int]$shuffled[$i].Y -ne [int]$targets[$i].Y) { $same=$false; break } }
      if($same) {
        $fallbackOffset=Get-Random -Minimum 1 -Maximum $targets.Count
        $shuffled=@(); for($i=0;$i -lt $targets.Count;$i++) { $shuffled += $targets[($i+$fallbackOffset) % $targets.Count] }
      }
      return ,$shuffled
    }
  }
  return ,$targets
}
function Invoke-DesktopShuffleCycle($savedWindows) {
  $iconCount=0; $iconMoves=0
  try {
    $now=@([JasperDesktopNative]::GetDesktopIconPositions())
    $iconCount=$now.Count
    if($now.Count -gt 1) {
      $targets=Get-ShuffledIconTargets $now
      for($i=0;$i -lt $now.Count;$i++) {
        if([JasperDesktopNative]::SetDesktopIconPosition([int]$now[$i].Index,[int]$targets[$i].X,[int]$targets[$i].Y)) { $iconMoves++ }
      }
    }
  } catch { Write-DesktopLog ("repeat icon shuffle failed: {0}" -f $_.Exception.Message) }
  $area=[System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
  $windowMoves=0
  foreach($w in @($savedWindows)) {
    try {
      $maxX=[Math]::Max($area.Left,$area.Right-[int]$w.Width)
      $maxY=[Math]::Max($area.Top,$area.Bottom-[int]$w.Height)
      $x=Get-Random -Minimum $area.Left -Maximum ($maxX+1)
      $y=Get-Random -Minimum $area.Top -Maximum ($maxY+1)
      if([JasperDesktopNative]::MoveWindow([long]$w.Handle,[int]$x,[int]$y)) { $windowMoves++ }
      [JasperDesktopNative]::FlashTaskbarButton([long]$w.Handle,1)
    } catch {}
  }
  Write-DesktopLog ("continuous shuffle cycle: {0} icon slots, {1} icon requests, {2} saved app windows moved." -f $iconCount,$iconMoves,$windowMoves)
}
function Restore-SnapshotData($snapshot, [bool]$RemoveSnapshot) {
  if ($null -eq $snapshot) { return }
  try { [void][JasperDesktopNative]::SetDesktopAutoArrange($false) } catch {}
  $iconOk=0; $windowOk=0
  foreach($icon in @($snapshot.Icons)) {
    try { if([JasperDesktopNative]::SetDesktopIconPosition([int]$icon.Index,[int]$icon.X,[int]$icon.Y)){$iconOk++} } catch {}
  }
  foreach($w in @($snapshot.Windows)) {
    try { if([JasperDesktopNative]::MoveWindow([long]$w.Handle,[int]$w.X,[int]$w.Y)){$windowOk++} } catch {}
  }
  Start-Sleep -Milliseconds 180
  if ($snapshot.PSObject.Properties.Name -contains 'IconViewStyle') {
    try { [void][JasperDesktopNative]::SetDesktopIconStyle([int]$snapshot.IconViewStyle) } catch { Write-DesktopLog ("original desktop icon style restore failed: {0}" -f $_.Exception.Message) }
  }
  Write-DesktopLog ("restore attempted: {0}/{1} icon positions dispatched; {2}/{3} window positions dispatched." -f $iconOk,@($snapshot.Icons).Count,$windowOk,@($snapshot.Windows).Count)
  # Keep the saved recovery copy if a desktop icon request failed so Recovery can retry.
  $allIconsDispatched = ($iconOk -ge @($snapshot.Icons).Count)
  if($RemoveSnapshot -and $allIconsDispatched) { Remove-Item -LiteralPath $SnapshotPath -Force -ErrorAction SilentlyContinue }
  elseif($RemoveSnapshot) { Write-DesktopLog 'recovery snapshot retained because some icon positions could not be sent.' }
}

try {
  if (-not ('JasperDesktopNative' -as [type])) { Add-Type -TypeDefinition $nativeSource -Language CSharp -ErrorAction Stop }
  if ($Action -eq 'Chaos') {
    # One run per recovery cycle. The marker remains after Jasper closes; Recovery clears it.
    if (Test-Path -LiteralPath $UsedPath) {
      Write-DesktopLog 'continuous chaos skipped: this horror event already ran once; use Recovery before replaying it.'
      exit 0
    }
    if (-not (Test-JasperBrowserAlive)) {
      Write-DesktopLog 'continuous chaos skipped because the Jasper Browser profile is not running.'
      exit 0
    }
    # Ensure only one loop is active at a time.
    $mutex = New-Object System.Threading.Mutex($false,'Local\JasperBrowserLiteDesktopChaos')
    $gotMutex=$false
    try { $gotMutex=$mutex.WaitOne(0) } catch { $gotMutex=$false }
    if (-not $gotMutex) { Write-DesktopLog 'continuous chaos skipped: another desktop-layout worker is already active.'; exit 0 }
    try {
      Remove-Item -LiteralPath $StopPath -Force -ErrorAction SilentlyContinue
      [IO.File]::WriteAllText($UsedPath,('Desktop chaos consumed '+(Get-Date).ToString('o')),(New-Object System.Text.UTF8Encoding($false)))
      [IO.File]::WriteAllText($ActivePath,([string]$PID),(New-Object System.Text.UTF8Encoding($false)))

      # Restore a stale saved layout first, but never overwrite the only recovery copy if it is malformed.
      if (Test-Path -LiteralPath $SnapshotPath) {
        try {
          $existing=Get-Content -LiteralPath $SnapshotPath -Raw -Encoding UTF8 | ConvertFrom-Json
          if ($existing -and $null -ne $existing.Icons -and $null -ne $existing.Windows) {
            Restore-SnapshotData $existing $true
            Write-DesktopLog ("restored stale snapshot version {0} before applying a fresh chaos layout" -f $existing.Version)
          } else {
            Write-DesktopLog 'stale snapshot was not structurally valid; refusing to overwrite the only recovery copy.'
            Remove-Item -LiteralPath $ActivePath -Force -ErrorAction SilentlyContinue
            exit 1
          }
        } catch {
          Write-DesktopLog ("could not recover an existing snapshot; refusing to overwrite it: {0}" -f $_.Exception.Message)
          Remove-Item -LiteralPath $ActivePath -Force -ErrorAction SilentlyContinue
          exit 1
        }
      }

      $icons=@(); $windows=@(); $iconStyle=0
      try {
        $iconStyle=[JasperDesktopNative]::GetDesktopIconStyle()
        $icons=@([JasperDesktopNative]::GetDesktopIconPositions() | ForEach-Object { [pscustomobject]@{Index=[int]$_.Index;X=[int]$_.X;Y=[int]$_.Y} })
      } catch { Write-DesktopLog ("icon capture skipped: {0}" -f $_.Exception.Message) }
      try {
        $area=[System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
        $windows=@([JasperDesktopNative]::GetNormalWindows('Jasper Browser') | Where-Object { $_.X -lt $area.Right -and ($_.X+$_.Width) -gt $area.Left -and $_.Y -lt $area.Bottom -and ($_.Y+$_.Height) -gt $area.Top } | ForEach-Object { [pscustomobject]@{Handle=[long]$_.Handle;Title=[string]$_.Title;ProcessName=[string]$_.ProcessName;X=[int]$_.X;Y=[int]$_.Y;Width=[int]$_.Width;Height=[int]$_.Height} })
      } catch { Write-DesktopLog ("window capture skipped: {0}" -f $_.Exception.Message) }

      $snapshot=[ordered]@{Version='0.6.6';Created=(Get-Date).ToString('o');IconViewStyle=[int]$iconStyle;Icons=@($icons);Windows=@($windows)}
      [IO.File]::WriteAllText($SnapshotPath,($snapshot|ConvertTo-Json -Depth 10),(New-Object System.Text.UTF8Encoding($false)))

      # Disable Explorer auto-arrange for the duration of the effect; Recovery restores the original style.
      if($icons.Count -gt 1) {
        try { $styleNow=[JasperDesktopNative]::GetDesktopIconStyle(); [void][JasperDesktopNative]::SetDesktopIconStyle([int]($styleNow -band (-bnot 0x0100))) } catch { Write-DesktopLog ("could not disable desktop auto-arrange: {0}" -f $_.Exception.Message) }
      }
      Write-DesktopLog ("continuous chaos started once: {0} original icon slots; {1} original app windows. Re-randomizing until Jasper closes, Escape is pressed, or Recovery stops it." -f $icons.Count,$windows.Count)

      $firstCycle=$true
      while (-not (Test-Path -LiteralPath $StopPath) -and -not [JasperDesktopNative]::EscapePressed()) {
        if (-not (Test-JasperBrowserAlive)) { Write-DesktopLog 'Jasper Browser is closed; continuous desktop randomization stopped.'; break }
        if($firstCycle -and $icons.Count -gt 1) {
          # Guarantee the first visible shuffle is a non-zero rotation of the saved slots.
          try {
            $offset=Get-Random -Minimum 1 -Maximum $icons.Count
            for($i=0;$i -lt $icons.Count;$i++) {
              $target=$icons[($i+$offset) % $icons.Count]
              [void][JasperDesktopNative]::SetDesktopIconPosition([int]$icons[$i].Index,[int]$target.X,[int]$target.Y)
            }
          } catch { Write-DesktopLog ("first icon shuffle failed: {0}" -f $_.Exception.Message) }
        } else {
          Invoke-DesktopShuffleCycle $windows
        }
        $firstCycle=$false
        if ($windows.Count -gt 0) { foreach($w in @($windows | Sort-Object {Get-Random})){try{[JasperDesktopNative]::FlashTaskbarButton([long]$w.Handle,2)}catch{}} }
        Start-Sleep -Milliseconds 900
      }
      Write-DesktopLog 'continuous chaos loop ended; leaving the last randomized layout in place for Recovery.'
    } finally {
      Remove-Item -LiteralPath $ActivePath -Force -ErrorAction SilentlyContinue
      if($gotMutex) { try { $mutex.ReleaseMutex() } catch {} }
      if($mutex){$mutex.Dispose()}
    }
  } else {
    [IO.File]::WriteAllText($StopPath,('Recovery requested '+(Get-Date).ToString('o')),(New-Object System.Text.UTF8Encoding($false)))
    Start-Sleep -Milliseconds 250
    if (-not (Test-Path -LiteralPath $SnapshotPath)) {
      Remove-Item -LiteralPath $UsedPath,$StopPath,$ActivePath -Force -ErrorAction SilentlyContinue
      Write-Output 'No saved desktop layout was found.'; exit 0
    }
    $snapshot=Get-Content -LiteralPath $SnapshotPath -Raw -Encoding UTF8 | ConvertFrom-Json
    Restore-SnapshotData $snapshot $true
    Write-Output "Requested restoration of $(@($snapshot.Icons).Count) desktop icon slots and $(@($snapshot.Windows).Count) app window positions. See desktop-layout.log for results."
    Remove-Item -LiteralPath $UsedPath,$StopPath,$ActivePath -Force -ErrorAction SilentlyContinue
  }
} catch {
  Write-DesktopLog ("[{0}] {1}" -f $Action,$_.Exception.Message)
  exit 1
}
