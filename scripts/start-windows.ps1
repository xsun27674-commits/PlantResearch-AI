$ErrorActionPreference = 'Stop'
Set-Location (Join-Path $PSScriptRoot '..')
$projectRoot=(Get-Location).Path
if (!(Test-Path '.venv\Scripts\python.exe')) { throw 'Run scripts\install-windows.ps1 first.' }
foreach ($port in @(3000,8000)) {
    if (Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue) {
        throw "Port $port is in use. Close the existing application; unrelated processes will not be stopped."
    }
}
Add-Type -Path (Join-Path $projectRoot 'packaging\windows\ServiceProcess.cs')
$python = (Resolve-Path '.venv\Scripts\python.exe').Path
$logs=Join-Path $projectRoot ('logs\'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force $logs | Out-Null
$variables=New-Object 'System.Collections.Generic.Dictionary[string,string]'
$variables['PYTHONHOME']=$null; $variables['PYTHONPATH']=$null
$variables['PYTHONUNBUFFERED']='1'; $variables['PYTHONUTF8']='1'
$variables['PLANT_STARTUP_LOG']=Join-Path $logs 'python-startup.log'
$bootstrap=Join-Path $projectRoot 'backend\bootstrap.py'
$backend=New-Object PlantService('backend',$python,('-u -X faulthandler "'+$bootstrap+'"'),$projectRoot,(Join-Path $logs 'backend.out.log'),(Join-Path $logs 'backend.err.log'),$variables)
try {
    $backend.Start()
    Write-Host ('Backend PID='+$backend.Process.Id+'; logs: '+$logs)
    $ready = $false
    for ($i=0; $i -lt 120; $i++) {
        if ($backend.HasExited) {
            $backend.FlushExited()
            throw ('Backend exited with code '+$backend.ExitCodeText+'. See '+$logs)
        }
        try {
            $backendHealth=Invoke-RestMethod 'http://127.0.0.1:8000/api/health' -TimeoutSec 1
            if ($backendHealth.status -eq 'ok') { $ready=$true; break }
        } catch {}
        Start-Sleep -Seconds 1
    }
    if (!$ready) { throw ('Backend readiness timed out. See import progress in '+$logs+'\python-startup.log') }
    Write-Host 'Backend ready. After Next.js shows Ready, open http://localhost:3000 on this Windows computer.'
    npm.cmd run dev --prefix frontend
    if ($LASTEXITCODE -ne 0) { throw 'Frontend exited with an error.' }
} finally { $backend.Dispose() }
