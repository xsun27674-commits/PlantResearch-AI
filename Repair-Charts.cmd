@echo off
setlocal
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0packaging\windows\Repair-Charts.ps1"
if errorlevel 1 pause
