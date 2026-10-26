@echo off
setlocal
 title Jasper Browser - USB Flasher
 echo ================================================
 echo  JASPER BROWSER LITE - USB FLASHER v0.6.6
 echo ================================================
 echo This will ERASE the selected USB drive and copy Jasper Browser files.
 echo It will NOT auto-run when plugged into another PC.
 echo.
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Flash-JasperBrowser-USB.ps1"
if errorlevel 1 (
 echo.
 echo USB flash did not complete. See the error above.
 pause
)
endlocal
