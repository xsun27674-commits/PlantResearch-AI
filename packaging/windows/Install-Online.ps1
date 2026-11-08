$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Windows.Forms
$stage=$null
$originalPath=$env:PATH
try {
 if (![Environment]::Is64BitOperatingSystem -or $env:PROCESSOR_ARCHITECTURE -eq 'ARM64') {throw 'Windows 10/11 Intel/AMD x64 is required.'}
 $root=Join-Path $env:LOCALAPPDATA 'PlantResearchAI'
 $link=Join-Path ([Environment]::GetFolderPath('Desktop')) 'PlantResearch AI.lnk'
 if ((Test-Path $root) -or (Test-Path $link)) {throw 'An installation or shortcut already exists. No existing files were overwritten.'}
 $choice=[System.Windows.Forms.MessageBox]::Show('Install PlantResearch AI for this user? This downloads portable Python and Node from official sources, installs application dependencies, builds the website and creates a desktop shortcut. Internet and up to 3 GB free disk space are needed. No administrator privileges, system PATH or registry changes. This Windows installer is not yet tested on a real Windows PC.','PlantResearch AI online setup','YesNo','Information')
 if($choice -ne 'Yes'){exit 0}
 $stage=Join-Path $env:LOCALAPPDATA ('PlantResearchAI-setup-'+[guid]::NewGuid().ToString('N'))
 New-Item -ItemType Directory $stage | Out-Null
 function Download-Verified($url,$file,$hash) {
  Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $file
  if((Get-FileHash $file -Algorithm SHA256).Hash.ToLowerInvariant() -ne $hash){throw 'Official runtime checksum mismatch. Stopping installation.'}
 }
 Write-Host 'Downloading official portable runtimes...'
 $pythonZip=Join-Path $stage 'python.zip'
 Download-Verified 'https://www.nuget.org/api/v2/package/python/3.12.10' $pythonZip '0eb85c2dfccccf1b17352de4c397f69194035b7d37149eacc16f1147d93de3b8'
 $nodeZip=Join-Path $stage 'node.zip'
 Download-Verified 'https://nodejs.org/dist/v24.14.0/node-v24.14.0-win-x64.zip' $nodeZip '313fa40c0d7b18575821de8cb17483031fe07d95de5994f6f435f3b345f85c66'
 New-Item -ItemType Directory (Join-Path $stage 'runtime') | Out-Null
 Expand-Archive -LiteralPath $pythonZip -DestinationPath (Join-Path $stage 'python-extract')
 Expand-Archive -LiteralPath $nodeZip -DestinationPath (Join-Path $stage 'node-extract')
 Move-Item (Join-Path $stage 'python-extract\tools') (Join-Path $stage 'runtime\python')
 Move-Item (Join-Path $stage 'node-extract\node-v24.14.0-win-x64') (Join-Path $stage 'runtime\node')
 $source=Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
 $app=Join-Path $stage 'app'
 New-Item -ItemType Directory $app | Out-Null
 # Only project source folders; never copy local environments or research data.
 foreach($name in @('backend','frontend','scripts','docs','packaging')) {
  $dest=Join-Path $app $name
  New-Item -ItemType Directory $dest | Out-Null
  Get-ChildItem (Join-Path $source $name) -Force | Where-Object {$_.Name -notin @('node_modules','.next','private_data','__pycache__','.pytest_cache')} | Copy-Item -Destination $dest -Recurse
 }
 Copy-Item (Join-Path $source 'README.md') $app
 Copy-Item (Join-Path $PSScriptRoot 'Launcher.ps1') (Join-Path $stage 'Launcher.ps1')
 $python=Join-Path $stage 'runtime\python\python.exe'
 $node=Join-Path $stage 'runtime\node'
 $env:PATH=$node+';'+$originalPath
 Write-Host 'Installing Python application dependencies...'
 & $python -m pip install --disable-pip-version-check -r (Join-Path $app 'packaging\windows\requirements.txt')
 if($LASTEXITCODE -ne 0){throw 'Python dependency installation failed. See output above.'}
 Write-Host 'Installing and building the website (may take several minutes)...'
 & (Join-Path $node 'npm.cmd') ci --prefix (Join-Path $app 'frontend') --no-audit --no-fund
 if($LASTEXITCODE -ne 0){throw 'Frontend dependencies failed. See output above.'}
 $env:NEXT_TELEMETRY_DISABLED='1'
 & (Join-Path $node 'npm.cmd') run build --prefix (Join-Path $app 'frontend')
 if($LASTEXITCODE -ne 0){throw 'Frontend build failed. See output above.'}
 Remove-Item $pythonZip,$nodeZip -Force
 Remove-Item (Join-Path $stage 'python-extract'),(Join-Path $stage 'node-extract') -Recurse -Force
 Move-Item $stage $root
 $stage=$null
 $shell=New-Object -ComObject WScript.Shell
 $shortcut=$shell.CreateShortcut($link)
 $shortcut.TargetPath=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
 $shortcut.Arguments='-NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File "'+(Join-Path $root 'Launcher.ps1')+'"'
 $shortcut.WorkingDirectory=$root
 $shortcut.Save()
 [System.Windows.Forms.MessageBox]::Show('Installation complete. The desktop shortcut is ready. Starting PlantResearch AI.','PlantResearch AI') | Out-Null
 Start-Process $shortcut.TargetPath -ArgumentList $shortcut.Arguments
} catch {
 Write-Host $_.Exception.Message -ForegroundColor Red
 [System.Windows.Forms.MessageBox]::Show($_.Exception.Message,'Installation failed','OK','Error') | Out-Null
 if($stage -and (Test-Path $stage)){Remove-Item $stage -Recurse -Force}
 exit 1
} finally {$env:PATH=$originalPath}
