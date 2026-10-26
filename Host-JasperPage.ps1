$ErrorActionPreference = 'Stop'
$JasperHome = Join-Path $env:LOCALAPPDATA 'JasperBrowserLite'
$WebRoot = Join-Path $JasperHome 'Site'
$HorrorDir = Join-Path $JasperHome 'Horror'
$StatePath = Join-Path $JasperHome 'horror-state.json'
$TokenPath = Join-Path $JasperHome 'horror-token.txt'
$CancelPath = Join-Path $JasperHome 'horror-cancel.flag'
$AdultStopPath = Join-Path $JasperHome 'Horror\adult-warning-stop.flag'
$WorkerPath = Join-Path $JasperHome 'Jasper-Horror-Worker.ps1'
$DesktopLayoutScript = Join-Path $JasperHome 'Jasper-Desktop-Layout.ps1'
$Port = 18765
$MutexName = 'Local\JasperBrowserLiteHorrorState'

function New-DefaultState {
  [pscustomobject]@{ Stage=0; SearchTriggered=$false; ReloadCount=0; FinalSequenceStarted=$false; Completed=$false; DialogPending=$false; RedMode=$false; WallpaperBackup=$null; WallpaperApplied=$false }
}
function Read-StateCore {
  if (Test-Path -LiteralPath $StatePath) {
    try {
      $s = Get-Content -LiteralPath $StatePath -Raw -Encoding UTF8 | ConvertFrom-Json
      $defaults = New-DefaultState
      foreach ($p in $defaults.PSObject.Properties) {
        if ($null -eq $s.PSObject.Properties[$p.Name]) { $s | Add-Member -NotePropertyName $p.Name -NotePropertyValue $p.Value -Force }
      }
      return $s
    } catch {}
  }
  return (New-DefaultState)
}
function Write-StateCore($State) {
  $tmp = $StatePath + '.' + $PID + '.tmp'
  $json = $State | ConvertTo-Json -Depth 12
  [IO.File]::WriteAllText($tmp, $json, (New-Object System.Text.UTF8Encoding($false)))
  Move-Item -LiteralPath $tmp -Destination $StatePath -Force
}
function Set-StateValues([hashtable]$Changes) {
  $mutex = [System.Threading.Mutex]::new($false, $MutexName)
  try {
    [void]$mutex.WaitOne([TimeSpan]::FromSeconds(10))
    $s = Read-StateCore
    foreach ($key in $Changes.Keys) { $s | Add-Member -NotePropertyName $key -NotePropertyValue $Changes[$key] -Force }
    Write-StateCore $s
    return $s
  } finally { try { $mutex.ReleaseMutex() } catch {}; $mutex.Dispose() }
}
function Get-PublicState($State, [bool]$StartFinal = $false) {
  return [ordered]@{
    stage = [int]$State.Stage
    searchTriggered = [bool]$State.SearchTriggered
    reloadCount = [int]$State.ReloadCount
    finalSequenceStarted = [bool]$State.FinalSequenceStarted
    completed = [bool]$State.Completed
    dialogPending = [bool]$State.DialogPending
    redMode = [bool]$State.RedMode
    wallpaperApplied = [bool]$State.WallpaperApplied
    startFinalSequence = $StartFinal
  }
}
function Json-Response($Object, [string]$Status = '200 OK') {
  return @{ Status=$Status; Mime='application/json; charset=utf-8'; Body=($Object | ConvertTo-Json -Depth 12 -Compress) }
}
function Start-HorrorWorker([string]$Action) {
  if (-not (Test-Path -LiteralPath $WorkerPath)) { throw "Horror worker missing: $WorkerPath" }
  $powershellExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
  $arguments = '-NoLogo -NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}" -Action "{1}"' -f $WorkerPath, $Action
  Start-Process -FilePath $powershellExe -ArgumentList $arguments -WindowStyle Hidden | Out-Null
}
function Parse-Query([string]$QueryString) {
  $out = @{}
  foreach ($pair in ($QueryString -split '&')) {
    if ([string]::IsNullOrWhiteSpace($pair)) { continue }
    $kv = $pair.Split('=', 2)
    $k = [Uri]::UnescapeDataString($kv[0].Replace('+',' '))
    $v = if ($kv.Length -gt 1) { [Uri]::UnescapeDataString($kv[1].Replace('+',' ')) } else { '' }
    $out[$k] = $v
  }
  return $out
}
function Handle-Api([string]$PathOnly, [string]$QueryString) {
  if ($PathOnly -eq '/api/config') {
    $token = if (Test-Path -LiteralPath $TokenPath) { (Get-Content -LiteralPath $TokenPath -Raw).Trim() } else { '' }
    return (Json-Response ([ordered]@{ token=$token }))
  }
  if (-not $PathOnly.StartsWith('/api/')) { return $null }
  $q = Parse-Query $QueryString
  $tokenExpected = if (Test-Path -LiteralPath $TokenPath) { (Get-Content -LiteralPath $TokenPath -Raw).Trim() } else { '' }
  if ([string]::IsNullOrWhiteSpace($tokenExpected) -or -not $q.ContainsKey('token') -or $q['token'] -cne $tokenExpected) {
    return @{ Status='403 Forbidden'; Mime='application/json; charset=utf-8'; Body='{"error":"Forbidden"}' }
  }
  $state = Read-StateCore
  switch ($PathOnly) {
    '/api/state' {
      return (Json-Response (Get-PublicState $state $false))
    }
    '/api/adult-warning' {
      New-Item -ItemType Directory -Force -Path (Split-Path -Parent $AdultStopPath) | Out-Null
      Remove-Item -LiteralPath $AdultStopPath -Force -ErrorAction SilentlyContinue
      Start-HorrorWorker 'AdultWarning'
      return (Json-Response ([ordered]@{ started=$true; boundedSeconds=5 }))
    }
    '/api/adult-warning-stop' {
      New-Item -ItemType Directory -Force -Path (Split-Path -Parent $AdultStopPath) | Out-Null
      [IO.File]::WriteAllText($AdultStopPath, 'Adult-site scare dismissed '+(Get-Date).ToString('o'), (New-Object System.Text.UTF8Encoding($false)))
      return (Json-Response ([ordered]@{ stopped=$true }))
    }
    '/api/secret1' {
      if (-not $state.Completed -and [int]$state.Stage -eq 0) {
        Remove-Item -LiteralPath $CancelPath -Force -ErrorAction SilentlyContinue
        $state = Set-StateValues @{ Stage=1; DialogPending=$true }
        Start-HorrorWorker 'MessageOne'
      }
      return (Json-Response (Get-PublicState (Read-StateCore) $false))
    }
    '/api/secret2' {
      if (-not $state.Completed -and [int]$state.Stage -eq 1) {
        $state = Set-StateValues @{ Stage=2; DialogPending=$true }
        Start-HorrorWorker 'MessageQuestion'
      }
      return (Json-Response (Get-PublicState (Read-StateCore) $false))
    }
    '/api/secret3' {
      if (-not $state.Completed -and [int]$state.Stage -eq 2) {
        Remove-Item -LiteralPath $CancelPath -Force -ErrorAction SilentlyContinue
        $state = Set-StateValues @{ Stage=3; RedMode=$true; DialogPending=$true }
        Start-HorrorWorker 'FiftyDialogs'
      }
      return (Json-Response (Get-PublicState (Read-StateCore) $false))
    }
    '/api/trigger-search' {
      if (-not $state.Completed -and [int]$state.Stage -ge 3) {
        if (-not $state.SearchTriggered) {
          $state = Set-StateValues @{ SearchTriggered=$true; ReloadCount=0; FinalSequenceStarted=$false }
        }
        # Start the real wallpaper/audio effect immediately on the user's explicit action.
        # If a previous attempt failed, a later click/page open can retry while WallpaperApplied is false.
        $state = Read-StateCore
        if (-not [bool]$state.WallpaperApplied) {
          try { Start-HorrorWorker 'SearchStart' }
          catch { try { [IO.File]::AppendAllText((Join-Path $JasperHome 'host-startup-errors.log'), ("{0:o} click-triggered wallpaper/audio worker start failed: {1}`r`n" -f (Get-Date),$_.Exception.Message)) } catch {} }
        }
      }
      return (Json-Response (Get-PublicState (Read-StateCore) $false))
    }
    '/api/continue-horror' {
      $state = Read-StateCore
      if (-not $state.Completed -and [int]$state.Stage -ge 3 -and [bool]$state.SearchTriggered) {
        # Retry if the wallpaper worker has not confirmed success, then let the button advance the ending.
        if (-not [bool]$state.WallpaperApplied) {
          try { Start-HorrorWorker 'SearchStart' }
          catch { try { [IO.File]::AppendAllText((Join-Path $JasperHome 'host-startup-errors.log'), ("{0:o} continue-button wallpaper/audio retry failed: {1}`r`n" -f (Get-Date),$_.Exception.Message)) } catch {} }
        }
        if (-not [bool]$state.FinalSequenceStarted) {
          $state = Set-StateValues @{ FinalSequenceStarted=$true }
        }
      }
      return (Json-Response (Get-PublicState (Read-StateCore) $false))
    }
    '/api/page-load' {
      # Kept for compatibility with older cached homepage code; page loads never advance the horror now.
      return (Json-Response (Get-PublicState (Read-StateCore) $false))
    }
    '/api/final-shake' {
      if ($state.SearchTriggered -and $state.FinalSequenceStarted -and -not $state.Completed) {
        Start-HorrorWorker 'FinalShake'
        Start-HorrorWorker 'FinalAudio'
      }
      return (Json-Response (Get-PublicState (Read-StateCore) $false))
    }
    '/api/final-complete' {
      if ($state.SearchTriggered -and $state.FinalSequenceStarted -and -not $state.Completed) {
        $state = Set-StateValues @{ Completed=$true; DialogPending=$false }
        Start-HorrorWorker 'FinalPopup'
      }
      return (Json-Response (Get-PublicState (Read-StateCore) $false))
    }
    default { return @{ Status='404 Not Found'; Mime='application/json; charset=utf-8'; Body='{"error":"Not found"}' } }
  }
}
function Get-MimeType([string]$Path) {
  switch ([IO.Path]::GetExtension($Path).ToLowerInvariant()) {
    '.html' { 'text/html; charset=utf-8' }
    '.css' { 'text/css; charset=utf-8' }
    '.js' { 'application/javascript; charset=utf-8' }
    '.json' { 'application/json; charset=utf-8' }
    '.png' { 'image/png' }
    '.jpg' { 'image/jpeg' }
    '.jpeg' { 'image/jpeg' }
    '.svg' { 'image/svg+xml' }
    '.ico' { 'image/x-icon' }
    '.xml' { 'application/opensearchdescription+xml; charset=utf-8' }
    '.bmp' { 'image/bmp' }
    '.wav' { 'audio/wav' }
    default { 'application/octet-stream' }
  }
}

# Self-heal the small per-user API credentials/state before listening. An empty token
# makes /api/state return 403 and used to trigger the browser's helper-failure alert.
try {
  New-Item -ItemType Directory -Force -Path $JasperHome, $WebRoot, $HorrorDir | Out-Null
  $currentToken = if (Test-Path -LiteralPath $TokenPath) { (Get-Content -LiteralPath $TokenPath -Raw -ErrorAction SilentlyContinue).Trim() } else { '' }
  if ([string]::IsNullOrWhiteSpace($currentToken)) {
    [IO.File]::WriteAllText($TokenPath, [Guid]::NewGuid().ToString('N'), (New-Object System.Text.UTF8Encoding($false)))
  }
  if (-not (Test-Path -LiteralPath $StatePath)) { Write-StateCore (New-DefaultState) }
} catch {
  try { [IO.File]::AppendAllText((Join-Path $JasperHome 'host-startup-errors.log'), ("{0:o} {1}`r`n" -f (Get-Date), $_.Exception.Message)) } catch {}
}

$listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, $Port)
try { $listener.Start() } catch {
  # Keep startup failure diagnosable instead of silently exiting when port 18765 is busy.
  try { [IO.File]::AppendAllText((Join-Path $JasperHome 'host-startup-errors.log'), ("{0:o} listener failed on 127.0.0.1:{1}: {2}`r`n" -f (Get-Date), $Port, $_.Exception.Message), (New-Object System.Text.UTF8Encoding($false))) } catch {}
  exit 1
}
try {
  while ($true) {
    $client = $listener.AcceptTcpClient()
    $stream = $null; $reader = $null
    try {
      $client.ReceiveTimeout = 5000; $client.SendTimeout = 5000
      $stream = $client.GetStream(); $stream.ReadTimeout = 5000
      $reader = New-Object System.IO.StreamReader($stream, [System.Text.Encoding]::ASCII, $false, 1024, $true)
      $requestLine = $reader.ReadLine()
      if (-not $requestLine) { continue }
      $headerLines = @{}
      while ($true) {
        $headerLine = $reader.ReadLine()
        if ($null -eq $headerLine -or $headerLine -eq '') { break }
        $idx = $headerLine.IndexOf(':')
        if ($idx -gt 0) { $headerLines[$headerLine.Substring(0,$idx).Trim().ToLowerInvariant()] = $headerLine.Substring($idx+1).Trim() }
      }
      $parts = $requestLine.Split(' ')
      $method = if ($parts.Length -ge 1) { $parts[0] } else { 'GET' }
      $requestTarget = if ($parts.Length -ge 2) { $parts[1] } else { '/' }
      $targetParts = $requestTarget.Split('?',2)
      $pathOnly = [Uri]::UnescapeDataString($targetParts[0])
      $queryString = if ($targetParts.Length -gt 1) { $targetParts[1] } else { '' }
      $response = $null
      if ($method -ne 'GET' -and $method -ne 'HEAD') {
        $response = @{ Status='405 Method Not Allowed'; Mime='text/plain; charset=utf-8'; Body='Method not allowed' }
      } elseif ($pathOnly -eq '/health') {
        $response = @{ Status='200 OK'; Mime='text/plain; charset=utf-8'; Body='JASPER_OK|0.6.6' }
      } elseif ($pathOnly.StartsWith('/api/')) {
        try { $response = Handle-Api $pathOnly $queryString } catch { $response = @{ Status='500 Internal Server Error'; Mime='application/json; charset=utf-8'; Body=('{"error":"' + ($_.Exception.Message -replace '"','\"') + '"}') } }
      } else {
        try {
          $relative = $pathOnly.TrimStart('/').Replace('/','\')
          if ([string]::IsNullOrWhiteSpace($relative)) { $relative = 'StartPage.html' }
          $rootFull = [IO.Path]::GetFullPath($WebRoot).TrimEnd('\') + '\'
          $fileFull = [IO.Path]::GetFullPath((Join-Path $WebRoot $relative))
          if (-not $fileFull.StartsWith($rootFull, [StringComparison]::OrdinalIgnoreCase)) { throw 'Invalid path' }
          if (-not (Test-Path -LiteralPath $fileFull -PathType Leaf)) {
            $response = @{ Status='404 Not Found'; Mime='text/plain; charset=utf-8'; Body='Not found' }
          } else {
            $bytes = [IO.File]::ReadAllBytes($fileFull)
            $bodyText = $null
            $response = @{ Status='200 OK'; Mime=(Get-MimeType $fileFull); BodyBytes=$bytes; Body=$null }
          }
        } catch { $response = @{ Status='403 Forbidden'; Mime='text/plain; charset=utf-8'; Body='Forbidden' } }
      }
      if (-not $response) { $response = @{ Status='500 Internal Server Error'; Mime='text/plain; charset=utf-8'; Body='Internal Server Error' } }
      if ($response.ContainsKey('BodyBytes')) { $bodyBytes = $response.BodyBytes } else { $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes([string]$response.Body) }
      $head = "HTTP/1.1 $($response.Status)`r`nContent-Type: $($response.Mime)`r`nContent-Length: $($bodyBytes.Length)`r`nCache-Control: no-store`r`nX-Content-Type-Options: nosniff`r`nConnection: close`r`n`r`n"
      $headBytes = [System.Text.Encoding]::ASCII.GetBytes($head)
      $stream.Write($headBytes,0,$headBytes.Length)
      if ($method -ne 'HEAD' -and $bodyBytes.Length -gt 0) { $stream.Write($bodyBytes,0,$bodyBytes.Length) }
      $stream.Flush()
    } catch {
      # Drop malformed requests and keep the loopback host alive.
    } finally {
      if ($reader) { $reader.Dispose() }
      if ($stream) { $stream.Dispose() }
      $client.Close()
    }
  }
} finally { $listener.Stop() }
