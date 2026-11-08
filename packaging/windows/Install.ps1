$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
try {
    if (![Environment]::Is64BitOperatingSystem -or $env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { throw 'This package requires Windows 10/11 x64 (Intel/AMD), not ARM64.' }
    $root = Join-Path $env:LOCALAPPDATA 'PlantResearchAI'
    if (Test-Path $root) { throw "An installation already exists at $root. No files were changed. Use its desktop shortcut. For a clean reinstall, close the launcher and rename this folder first; preserve its data folder." }
    $answer = [System.Windows.Forms.MessageBox]::Show("Install PlantResearch AI in your user folder?`n`nIncludes private Python/Node runtimes and dependencies. No administrator privileges, system PATH changes, registry changes or network downloads. A desktop shortcut will be created. Requires about 2 GB free space.`n`nWindows package has NOT been tested on a real Windows PC. Continue?",'PlantResearch AI installation','YesNo','Information')
    if ($answer -ne 'Yes') { exit 0 }
    $desktopLink = Join-Path ([Environment]::GetFolderPath('Desktop')) 'PlantResearch AI.lnk'
    if (Test-Path $desktopLink) { throw 'A desktop shortcut with this name already exists. It was not overwritten.' }
    Write-Host 'Verifying package integrity...'
    $payload = Join-Path $PSScriptRoot 'payload.zip'
    $expected = (Get-Content (Join-Path $PSScriptRoot 'payload.sha256') -Raw).Trim()
    if ((Get-FileHash $payload -Algorithm SHA256).Hash.ToLowerInvariant() -ne $expected) { throw 'Payload checksum mismatch. Installation stopped.' }
    $stage = Join-Path $env:LOCALAPPDATA ('PlantResearchAI-setup-' + [guid]::NewGuid().ToString('N'))
    Write-Host 'Extracting application and bundled runtimes. This may take several minutes...'
    Expand-Archive -LiteralPath $payload -DestinationPath $stage
    Move-Item -LiteralPath $stage -Destination $root
    $stage = $null
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut((Join-Path ([Environment]::GetFolderPath('Desktop')) 'PlantResearch AI.lnk'))
    $shortcut.TargetPath = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $shortcut.Arguments = '-NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File "' + (Join-Path $root 'Launcher.ps1') + '"'
    $shortcut.WorkingDirectory = $root
    $shortcut.Description = 'PlantResearch AI - local single-user research workspace'
    $shortcut.Save()
    $choice = [System.Windows.Forms.MessageBox]::Show('Installation complete. A desktop shortcut has been created. Start PlantResearch AI now?','PlantResearch AI','YesNo','Information')
    if ($choice -eq 'Yes') { Start-Process $shortcut.TargetPath -ArgumentList $shortcut.Arguments }
} catch {
    Write-Host $_.Exception.Message -ForegroundColor Red
    [System.Windows.Forms.MessageBox]::Show($_.Exception.Message,'Installation failed','OK','Error') | Out-Null
    if ($stage -and (Test-Path $stage)) { Remove-Item -LiteralPath $stage -Recurse -Force }
    exit 1
}
