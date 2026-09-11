@echo off
rem 01_scan_G.bat - double-click to run the read-only scan of G:\
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp001_scan_G.ps1"
echo.
pause
