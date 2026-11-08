$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
try {
# Windows Job Object owns only our child processes. Closing the handle kills their descendants.
Add-Type @'
using System;
using System.Runtime.InteropServices;
public sealed class PlantJob : IDisposable {
 [DllImport("kernel32.dll", CharSet=CharSet.Unicode)] static extern IntPtr CreateJobObject(IntPtr a, string n);
 [DllImport("kernel32.dll")] static extern bool SetInformationJobObject(IntPtr h,int c,IntPtr p,uint l);
 [DllImport("kernel32.dll")] static extern bool AssignProcessToJobObject(IntPtr h,IntPtr p);
 [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr h);
 [StructLayout(LayoutKind.Sequential)] struct Basic { public long a,b; public uint flags; public UIntPtr min,max; public uint count; public UIntPtr affinity; public uint priority,scheduling; }
 [StructLayout(LayoutKind.Sequential)] struct IO { public ulong a,b,c,d,e,f; }
 [StructLayout(LayoutKind.Sequential)] struct Extended { public Basic basic; public IO io; public UIntPtr a,b,c,d; }
 IntPtr handle;
 public PlantJob() {
  handle=CreateJobObject(IntPtr.Zero,null);
  if(handle==IntPtr.Zero) throw new Exception("Could not create service job");
  Extended info=new Extended(); info.basic.flags=0x2000;
  int size=Marshal.SizeOf(info); IntPtr ptr=Marshal.AllocHGlobal(size);
  try { Marshal.StructureToPtr(info,ptr,false); if(!SetInformationJobObject(handle,9,ptr,(uint)size)) { CloseHandle(handle); handle=IntPtr.Zero; throw new Exception("Could not configure service cleanup"); } }
  finally { Marshal.FreeHGlobal(ptr); }
 }
 public void Add(IntPtr process) { if(!AssignProcessToJobObject(handle,process)) throw new Exception("Could not track child process safely"); }
 public void Dispose() { if(handle!=IntPtr.Zero) { CloseHandle(handle); handle=IntPtr.Zero; } }
}
'@
Add-Type -Path (Join-Path $PSScriptRoot 'ServiceProcess.cs')
} catch {
 $earlyLog=Join-Path $PSScriptRoot 'logs'
 New-Item -ItemType Directory -Force $earlyLog | Out-Null
 $_.Exception.ToString() | Add-Content -LiteralPath (Join-Path $earlyLog 'launcher-initialization.log') -Encoding UTF8
 [System.Windows.Forms.MessageBox]::Show('Launcher initialization failed. Apply Repair-Startup.cmd from the updated source. Details: '+$_.Exception.Message,'PlantResearch AI','OK','Error') | Out-Null
 exit 1
}
$script:job = $null
$script:children = @()
$script:ready = $false
$script:starting = $false
$script:mutex = New-Object System.Threading.Mutex($false,'Local\PlantResearchAI-SingleUser')
if (!$script:mutex.WaitOne(0)) { [System.Windows.Forms.MessageBox]::Show('PlantResearch AI is already running. Use the existing launcher window.','PlantResearch AI') | Out-Null; exit }
$root = [IO.Path]::GetFullPath($PSScriptRoot)
$appRoot = Join-Path $root 'app'
$logs = Join-Path $root 'logs'
$data = Join-Path $root 'data'
New-Item -ItemType Directory -Force $logs | Out-Null
$script:runLog = $null
function Write-Diagnostic($message) {
 if ($script:runLog) { Add-Content -LiteralPath $script:runLog -Value ((Get-Date -Format o)+' '+$message) -Encoding UTF8 }
}
function Fail-Startup($message) {
 Write-Diagnostic ('FAILED: '+$message)
 Stop-Services
 $status.Text=$message+' Open logs for details.'
 [System.Windows.Forms.MessageBox]::Show($form, $message+"`nDiagnostic log: "+$script:runLog, 'Startup failed','OK','Error') | Out-Null
}
$form = New-Object System.Windows.Forms.Form
$form.Text = 'PlantResearch AI'
$form.ClientSize = New-Object System.Drawing.Size(650,340)
$form.StartPosition = 'CenterScreen'
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox = $false
$status = New-Object System.Windows.Forms.Label
$status.SetBounds(20,20,610,70)
$status.Text = 'Starting local research workspace...'
$status.Font = New-Object System.Drawing.Font('Segoe UI',11)
$form.Controls.Add($status)
$note = New-Object System.Windows.Forms.Label
$note.SetBounds(20,92,610,45)
$note.Text = 'Basic PDF/data/chart tools work without a key. Optional AI key stays in memory for this session. Closing this window stops both services (closing a browser tab does not).'
$form.Controls.Add($note)
$provider = New-Object System.Windows.Forms.ComboBox
$provider.SetBounds(20,145,125,26)
$provider.DropDownStyle='DropDownList'
$provider.Items.AddRange(@('DeepSeek','Qwen')); $provider.SelectedIndex=0
$form.Controls.Add($provider)
$key = New-Object System.Windows.Forms.TextBox
$key.SetBounds(155,145,310,26); $key.UseSystemPasswordChar=$true
$form.Controls.Add($key)
$apply = New-Object System.Windows.Forms.Button
$apply.Text='Apply key / restart'; $apply.SetBounds(475,143,150,30)
$form.Controls.Add($apply)
$open = New-Object System.Windows.Forms.Button
$open.Text='Open website'; $open.SetBounds(20,195,140,36); $open.Enabled=$false
$form.Controls.Add($open)
$stop = New-Object System.Windows.Forms.Button
$stop.Text='Stop services'; $stop.SetBounds(175,195,140,36)
$form.Controls.Add($stop)
$start = New-Object System.Windows.Forms.Button
$start.Text='Start services'; $start.SetBounds(330,195,140,36); $start.Enabled=$false
$form.Controls.Add($start)
$logButton = New-Object System.Windows.Forms.Button
$logButton.Text='Open logs'; $logButton.SetBounds(485,195,140,36)
$form.Controls.Add($logButton)
$privacy = New-Object System.Windows.Forms.Label
$privacy.SetBounds(20,250,610,70)
$privacy.Text='Local single-user only. AI requests send the materials attached in the website to your selected provider. The provider selected in the website must match the key entered above. No public hosting or user authentication.'
$form.Controls.Add($privacy)
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval=1000
function Stop-Services {
 $timer.Stop()
 if ($script:job) { $script:job.Dispose(); $script:job=$null }
 foreach ($child in $script:children) {
  try { $child.Dispose(); Write-Diagnostic ('Stopped '+$child.Name) } catch { Write-Diagnostic ('Cleanup error: '+$_.Exception.Message) }
 }
 $script:children=@(); $script:ready=$false; $script:starting=$false
 $open.Enabled=$false; $start.Enabled=$true; $apply.Enabled=$true
 $status.Text='Services stopped. Research files remain saved locally.'
}
function Start-Child($exe,$arguments,$working,$name,$variables) {
 foreach ($path in @($exe,$working)) { if (!(Test-Path -LiteralPath $path)) { throw "Missing $name path: $path" } }
 $envMap=New-Object 'System.Collections.Generic.Dictionary[string,string]'
 # Ignore unrelated Python installations without modifying process/user/system settings.
 $envMap['PYTHONHOME']=$null; $envMap['PYTHONPATH']=$null
 foreach($k in $variables.Keys) { $envMap[$k]=[string]$variables[$k] }
 $outPath=Join-Path $script:sessionLogs ($name+'.out.log')
 $errPath=Join-Path $script:sessionLogs ($name+'.err.log')
 Write-Diagnostic ("Starting $name executable=$exe cwd=$working args=$arguments stdout=$outPath stderr=$errPath")
 $child=New-Object PlantService($name,$exe,$arguments,$working,$outPath,$errPath,$envMap)
 $script:children += $child
 $child.Start()
 Write-Diagnostic ("Started $name PID="+$child.Process.Id)
 $script:job.Add($child.Process.Handle)
}
function Start-Frontend {
 Start-Child (Join-Path $root 'runtime\node\node.exe') 'node_modules\next\dist\bin\next start --hostname 127.0.0.1 --port 3000' (Join-Path $appRoot 'frontend') 'frontend' @{NEXT_TELEMETRY_DISABLED='1'}
 $script:phase='frontend'; $script:deadline=[DateTime]::UtcNow.AddSeconds(120)
 $status.Text='Backend ready. Waiting for frontend on port 3000...'
 Write-Diagnostic 'Backend direct health check passed; frontend starting.'
}
function Start-Services {
 try {
  $script:sessionLogs=Join-Path $logs ((Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,8))
  New-Item -ItemType Directory $script:sessionLogs | Out-Null
  $script:runLog=Join-Path $script:sessionLogs 'launcher.log'
  Write-Diagnostic ('Launcher start; PowerShell='+$PSVersionTable.PSVersion+'; root='+$root)
  $start.Enabled=$false; $open.Enabled=$false; $apply.Enabled=$false
  foreach ($relative in @('runtime\python\python.exe','runtime\python\Lib\encodings\__init__.py','runtime\node\node.exe','app\backend\bootstrap.py','app\backend\app.py','app\frontend\.next\BUILD_ID')) {
   if (!(Test-Path -LiteralPath (Join-Path $root $relative))) { throw ('Installation is incomplete. Missing: '+$relative) }
  }
  foreach ($port in @(3000,8000)) {
   $listener = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Loopback,$port)
   try { $listener.Start() } catch { throw "Port $port is occupied. Close the other application, then click Start services. No unrelated processes were stopped." } finally { $listener.Stop() }
  }
  $script:job=New-Object PlantJob
  $vars=@{PLANT_DATA_DIR=$data;MPLCONFIGDIR=(Join-Path $root 'matplotlib-cache');PYTHONNOUSERSITE='1';PYTHONUTF8='1';PYTHONUNBUFFERED='1';PLANT_STARTUP_LOG=(Join-Path $script:sessionLogs 'python-startup.log');DEEPSEEK_API_KEY='';QWEN_API_KEY=''}
  if($key.Text) { if($provider.SelectedIndex -eq 0) {$vars.DEEPSEEK_API_KEY=$key.Text} else {$vars.QWEN_API_KEY=$key.Text} }
  $bootstrap=Join-Path $appRoot 'backend\bootstrap.py'
  Start-Child (Join-Path $root 'runtime\python\python.exe') ('-u -X faulthandler "'+$bootstrap+'"') $appRoot 'backend' $vars
  $script:phase='backend'
  $script:deadline=[DateTime]::UtcNow.AddSeconds(120); $script:starting=$true
  $status.Text='Waiting for Python backend on port 8000 (up to 120 seconds)...'
  $script:lastHealthError='No response yet'; $timer.Start()
 } catch { Fail-Startup $_.Exception.Message }
}
function Update-ServiceState {
 $timer.Stop() # Avoid reentrant GUI timer callbacks during HTTP requests.
 try {
  foreach ($child in $script:children) {
   if ($child.HasExited) {
    $child.FlushExited()
    throw ($child.Name+' exited before/stopped after readiness. Exit code: '+$child.ExitCodeText+'. See '+$child.Name+'.err.log and python-startup.log.')
   }
  }
  if ($script:starting) {
   $healthy=$false
   try {
    if ($script:phase -eq 'backend') {
     $backendHealth=Invoke-RestMethod 'http://127.0.0.1:8000/api/health' -TimeoutSec 1
     $healthy=($backendHealth.status -eq 'ok')
    } else {
     $proxyHealth=Invoke-RestMethod 'http://127.0.0.1:3000/api/health' -TimeoutSec 1
     $pageResponse=Invoke-WebRequest 'http://127.0.0.1:3000' -UseBasicParsing -TimeoutSec 2
     $healthy=($proxyHealth.status -eq 'ok' -and $pageResponse.StatusCode -eq 200)
    }
    if (!$healthy) { $script:lastHealthError='Health response was not status=ok' }
   } catch { $script:lastHealthError=$_.Exception.Message }
   if ($healthy) {
    if ($script:phase -eq 'backend') { Start-Frontend }
    else {
     $script:starting=$false; $script:ready=$true; $open.Enabled=$true; $apply.Enabled=$true
     $status.Text='Running - http://localhost:3000. Keep this launcher open.'
     Write-Diagnostic 'Frontend homepage and proxy health checks passed.'
     try { Start-Process 'http://localhost:3000' } catch { Write-Diagnostic 'Browser could not be opened automatically. Use Open website.' }
    }
   } elseif ([DateTime]::UtcNow -gt $script:deadline) {
    throw ($script:phase+' startup timed out. Last health error: '+$script:lastHealthError+'. See logs for import progress or native-runtime errors.')
   }
  }
 } catch { Fail-Startup $_.Exception.Message }
 finally { if ($script:starting -or $script:ready) { $timer.Start() } }
}
$timer.Add_Tick({Update-ServiceState})
$open.Add_Click({Start-Process 'http://localhost:3000'})
$stop.Add_Click({Stop-Services})
$start.Add_Click({Start-Services})
$apply.Add_Click({Stop-Services; Start-Services})
$logButton.Add_Click({Start-Process explorer.exe -ArgumentList ('"'+$logs+'"')})
$form.Add_Shown({Start-Services})
$form.Add_FormClosing({Stop-Services; $key.Clear()})
try { [System.Windows.Forms.Application]::Run($form) } finally { Stop-Services; $script:mutex.ReleaseMutex(); $script:mutex.Dispose() }
