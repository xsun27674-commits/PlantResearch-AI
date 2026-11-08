$ErrorActionPreference = 'Stop'
Set-Location (Join-Path $PSScriptRoot '..')
if (!(Test-Path '.venv\Scripts\python.exe')) { throw 'Run scripts\install-windows.ps1 first.' }
foreach ($port in @(3000,8000)) {
    if (Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue) {
        throw "Port $port is in use. Close the existing application or use the manual instructions in docs/WINDOWS.md."
    }
}
$python = (Resolve-Path '.venv\Scripts\python.exe').Path
$backend = Start-Process -FilePath $python -ArgumentList @('-m','uvicorn','backend.app:app','--host','127.0.0.1','--port','8000') -WorkingDirectory (Get-Location).Path -PassThru -NoNewWindow
try {
    $ready = $false
    for ($i=0; $i -lt 30; $i++) {
        if ($backend.HasExited) { throw 'Backend exited. Read the error above.' }
        try {
            $health=Invoke-RestMethod 'http://127.0.0.1:8000/api/health' -TimeoutSec 2
            if ($health.status -eq 'ok') { $ready=$true; break }
        } catch {}
        Start-Sleep -Seconds 1
    }
    if (!$ready) { throw 'Backend did not become ready within 30 seconds.' }
    Write-Host 'After Next.js shows Ready, open http://localhost:3000 on THIS Windows computer. Ctrl+C stops services.'
    npm.cmd run dev --prefix frontend
    if ($LASTEXITCODE -ne 0) { throw 'Frontend exited with an error.' }
} finally {
    if (!$backend.HasExited) { Stop-Process -Id $backend.Id -ErrorAction SilentlyContinue }
}
