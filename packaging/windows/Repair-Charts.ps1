$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Windows.Forms
$mutex=New-Object System.Threading.Mutex($false,'Local\PlantResearchAI-SingleUser')
$locked=$false
$backup=$null
$replaced=@()
try {
 $locked=$mutex.WaitOne(0)
 if (!$locked) { throw 'Close the existing PlantResearch AI launcher before applying this repair.' }
 $root=Join-Path $env:LOCALAPPDATA 'PlantResearchAI'
 if (!(Test-Path (Join-Path $root 'runtime\python\python.exe'))) {throw 'Existing installation not found. No files changed.'}
 if (!(Test-Path (Join-Path $root 'app\backend\app.py'))) {throw 'Installed backend not found. No files changed.'}
 $sourceRoot=Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
 $files=@(@{Source=(Join-Path $sourceRoot 'backend\app.py');Target='app\backend\app.py'})
 foreach($file in $files) {if (!(Test-Path -LiteralPath $file.Source)) {throw ('Repair source missing: '+$file.Source)}}
 $choice=[System.Windows.Forms.MessageBox]::Show('Update only the chart logic? Existing code files will be backed up. Your data, Python runtime, dependencies and API settings will not be changed. No download, reinstall or administrator privileges.','PlantResearch AI chart repair','YesNo','Information')
 if($choice -ne 'Yes'){exit 0}
 $backup=Join-Path $root ('chart-backups\'+[guid]::NewGuid().ToString('N'))
 New-Item -ItemType Directory $backup | Out-Null
 foreach($file in $files) {
  $target=Join-Path $root $file.Target
  $saved=Join-Path $backup $file.Target
  $exists=Test-Path -LiteralPath $target
  if($exists) {New-Item -ItemType Directory -Force (Split-Path $saved) | Out-Null; Copy-Item -LiteralPath $target -Destination $saved}
  $replaced+=@{Target=$target;Saved=$saved;Existed=$exists}
  Copy-Item -LiteralPath $file.Source -Destination $target -Force
 }
 [System.Windows.Forms.MessageBox]::Show("Chart repair applied. Start your usual desktop shortcut and generate a grouped chart. Backup: $backup",'PlantResearch AI repair') | Out-Null
} catch {
 foreach($file in $replaced) {
  if($file.Existed) {Copy-Item -LiteralPath $file.Saved -Destination $file.Target -Force}
  elseif(Test-Path -LiteralPath $file.Target) {Remove-Item -LiteralPath $file.Target -Force}
 }
 [System.Windows.Forms.MessageBox]::Show($_.Exception.Message,'Repair failed','OK','Error') | Out-Null
 exit 1
} finally {if($locked){$mutex.ReleaseMutex()};$mutex.Dispose()}
