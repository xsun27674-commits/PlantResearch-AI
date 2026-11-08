@echo off
setlocal
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0packaging\windows\Repair-Startup.ps1"
if errorlevel 1 pause
