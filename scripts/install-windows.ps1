$ErrorActionPreference = 'Stop'
Set-Location (Join-Path $PSScriptRoot '..')
function Check-Exit($step) { if ($LASTEXITCODE -ne 0) { throw "$step failed (exit $LASTEXITCODE)" } }
py -3.12 -m venv .venv
Check-Exit 'Create Python virtual environment'
& .\.venv\Scripts\python.exe -m pip install -r backend\requirements.txt
Check-Exit 'Install Python dependencies'
npm.cmd ci --prefix frontend
Check-Exit 'Install frontend dependencies'
Write-Host 'Installation complete. Run scripts\start-windows.ps1 next.'
