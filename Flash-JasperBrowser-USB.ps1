$ErrorActionPreference = 'Stop'
trap { $line = $_.InvocationInfo.ScriptLineNumber; Write-Host ("USB flash failed at line {0}: {1}" -f $line, $_.Exception.Message) -ForegroundColor Red; try { Read-Host 'Press Enter to close' } catch {}; exit 1 }
$SourceRoot = [IO.Path]::GetFullPath($PSScriptRoot)
$scriptPath = $PSCommandPath
function Test-Admin {
  $id = [Security.Principal.WindowsIdentity]::GetCurrent()
  $p = New-Object Security.Principal.WindowsPrincipal($id)
  return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}
if (-not (Test-Admin)) {
  Write-Host 'Formatting a USB drive needs administrator permission on Windows.' -ForegroundColor Yellow
  Write-Host 'This elevation is only for the explicitly requested format-and-copy operation.' -ForegroundColor Yellow
  if ((Read-Host 'Type ELEVATE to request the normal Windows UAC prompt') -cne 'ELEVATE') { Write-Host 'Cancelled; no drive was changed.' -ForegroundColor Yellow; exit 2 }
  $ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
  $args = '-NoLogo -NoProfile -ExecutionPolicy Bypass -File "{0}"' -f $scriptPath
  Start-Process -FilePath $ps -Verb RunAs -ArgumentList $args -Wait
  exit $LASTEXITCODE
}
Write-Host ''
Write-Host 'Available candidate USB/removable volumes:' -ForegroundColor Cyan
$candidates = @()
foreach ($v in @(Get-Volume | Where-Object { $_.DriveLetter -and $_.DriveType -ne 'CD-ROM' })) {
  $letter = [string]$v.DriveLetter
  try { $part = Get-Partition -DriveLetter $letter -ErrorAction Stop | Select-Object -First 1; $disk = Get-Disk -Number $part.DiskNumber -ErrorAction Stop } catch { continue }
  $logical = Get-CimInstance Win32_LogicalDisk -ErrorAction SilentlyContinue | Where-Object { $_.DeviceID -eq ($letter + ':') } | Select-Object -First 1
  $isRemovable = ($disk.BusType -eq 'USB') -or ($logical -and [int]$logical.DriveType -eq 2)
  if (-not $isRemovable) { continue }
  $sizeGB = [math]::Round(([double]$disk.Size / 1GB), 2)
  $candidates += [pscustomobject]@{Letter=$letter;Label=[string]$v.FileSystemLabel;FileSystem=[string]$v.FileSystem;DiskNumber=[int]$disk.Number;DiskName=[string]$disk.FriendlyName;BusType=[string]$disk.BusType;SizeGB=$sizeGB;IsBoot=[bool]$disk.IsBoot;IsSystem=[bool]$disk.IsSystem;IsReadOnly=[bool]$disk.IsReadOnly;SourceDrive=([IO.Path]::GetPathRoot($SourceRoot).TrimEnd('\').TrimEnd(':'))}
}
if (-not $candidates.Count) { throw 'No USB/removable volume found. Insert the USB drive and try again.' }
foreach ($c in $candidates) { Write-Host ("  {0}:  {1} | {2} GB | {3} | label='{4}' | disk #{5}" -f $c.Letter,$c.DiskName,$c.SizeGB,$c.BusType,$c.Label,$c.DiskNumber) }
$letter = (Read-Host 'Enter the USB drive letter to ERASE and flash (for example E)').Trim().TrimEnd(':').ToUpperInvariant()
$c = $candidates | Where-Object { $_.Letter.ToUpperInvariant() -eq $letter } | Select-Object -First 1
if (-not $c) { throw 'That drive was not in the verified USB/removable drive list.' }
if ($c.IsBoot -or $c.IsSystem) { throw 'Safety stop: Windows reports this as a boot/system disk.' }
$sourceDrive = [IO.Path]::GetPathRoot($SourceRoot).Substring(0,1).ToUpperInvariant()
if ($sourceDrive -eq $letter) { throw 'Safety stop: you cannot format the same drive that this flasher is running from. Extract the package onto your PC first.' }
if ($c.IsReadOnly) { throw 'The selected USB drive is read-only.' }
Write-Host ''
Write-Host '!!! THIS WILL ERASE ALL FILES ON THIS DRIVE !!!' -ForegroundColor Red
Write-Host ("Target: {0}: | {1} | {2} GB | current label='{3}'" -f $c.Letter,$c.DiskName,$c.SizeGB,$c.Label) -ForegroundColor Yellow
Write-Host 'Jasper will be copied as a user-launched portable setup. It will NOT auto-run on USB insertion and will NOT bypass UAC.' -ForegroundColor Cyan
$required = 'FORMAT ' + $letter + ':'
if ((Read-Host ("To confirm formatting, type exactly {0}" -f $required)) -cne $required) { Write-Host 'Cancelled; no drive was changed.' -ForegroundColor Yellow; exit 3 }
$driveRoot = $letter + ':\'
try {
  Format-Volume -DriveLetter $letter -FileSystem exFAT -NewFileSystemLabel 'JASPERUSB' -Force -Confirm:$false | Out-Null
} catch { throw ("Formatting failed. No package copy was attempted. Windows reported: {0}" -f $_.Exception.Message) }
Start-Sleep -Seconds 2
# Rebuild and validate the target path after formatting; use Robocopy for reliable
# Windows path handling across folders and individual files.
$driveRoot = [string]::Format('{0}:\', $letter)
if (-not (Test-Path -LiteralPath $driveRoot -PathType Container)) {
  throw ("The USB drive root is unavailable after formatting: [{0}]" -f $driveRoot)
}
Write-Host 'Copying Jasper Browser Lite and USB runtime...' -ForegroundColor Cyan
$robocopy = Join-Path $env:SystemRoot 'System32\robocopy.exe'
if (-not (Test-Path -LiteralPath $robocopy -PathType Leaf)) {
  throw 'Windows Robocopy was not found; no package copy was attempted.'
}
& $robocopy $SourceRoot $driveRoot /E /COPY:DAT /DCOPY:DAT /R:1 /W:1 /XJ
$copyCode = $LASTEXITCODE
if ($copyCode -ge 8) {
  throw ("Robocopy failed with exit code {0}; the USB copy may be incomplete." -f $copyCode)
}
if (-not (Test-Path -LiteralPath (Join-Path $driveRoot 'Start-JasperBrowser-USB.bat'))) { throw 'Copy verification failed: USB launcher is missing.' }
$info = @'
JASPER BROWSER LITE USB v0.6.6

To start, double-click Start-JasperBrowser-USB.bat.
This is a user-launched portable setup: it copies its runtime to the current user's LocalAppData and uses that user's installed Firefox.
If Firefox is missing, the launcher asks whether to run a normal winget installation. That installation may request UAC/admin approval.

For security, Windows will not auto-run this package merely because the USB is plugged in. This package does not bypass UAC.
The Flash tool formatted this drive as exFAT after a typed confirmation. Keep backups of anything important before flashing again.
'@
[IO.File]::WriteAllText((Join-Path $driveRoot 'USB-START-HERE.txt'),$info,(New-Object System.Text.UTF8Encoding($false)))
Write-Host ''
Write-Host ("SUCCESS: Jasper Browser USB package copied to {0}" -f $driveRoot) -ForegroundColor Green
Write-Host 'On another PC, manually run Start-JasperBrowser-USB.bat.' -ForegroundColor Green
Read-Host 'Press Enter to finish'
