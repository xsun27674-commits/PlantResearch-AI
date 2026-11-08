@echo off
setlocal
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0packaging\windows\Install-Online.ps1"
if errorlevel 1 pause
