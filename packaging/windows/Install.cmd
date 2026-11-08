@echo off
setlocal
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0Install.ps1"
if errorlevel 1 (
 echo Installation did not complete. Please read the message above.
 pause
)
