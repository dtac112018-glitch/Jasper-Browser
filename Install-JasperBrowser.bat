@echo off
setlocal
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install-JasperBrowser.ps1"
if errorlevel 1 (
  echo.
  echo Jasper Browser setup reported an error. Read the PowerShell message above.
  pause
)
endlocal
