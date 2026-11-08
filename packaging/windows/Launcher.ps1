$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
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
$script:job = $null
$script:children = @()
$script:ready = $false
$script:starting = $false
$script:mutex = New-Object System.Threading.Mutex($false,'Local\PlantResearchAI-SingleUser')
if (!$script:mutex.WaitOne(0)) { [System.Windows.Forms.MessageBox]::Show('PlantResearch AI is already running. Use the existing launcher window.','PlantResearch AI') | Out-Null; exit }
$root = $PSScriptRoot
$appRoot = Join-Path $root 'app'
$logs = Join-Path $root 'logs'
$data = Join-Path $root 'data'
New-Item -ItemType Directory -Force $logs,$data | Out-Null
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
 foreach ($p in $script:children) { try { $p.WaitForExit(3000) | Out-Null; if (!$p.HasExited) { $p.Kill() } } catch {} }
 $script:children=@(); $script:ready=$false; $script:starting=$false
 $open.Enabled=$false; $start.Enabled=$true; $apply.Enabled=$true; $status.Text='Services stopped. Research files remain saved locally.'
}
function Start-Child($exe,$arguments,$working,$name,$variables) {
 # Child-specific process environment is inherited then immediately restored.
 $old=@{}
 foreach($k in $variables.Keys) { $old[$k]=[Environment]::GetEnvironmentVariable($k,'Process'); [Environment]::SetEnvironmentVariable($k,[string]$variables[$k],'Process') }
 try {
  $p=Start-Process -FilePath $exe -ArgumentList $arguments -WorkingDirectory $working -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $logs ($name+'.out.log')) -RedirectStandardError (Join-Path $logs ($name+'.err.log'))
 } finally { foreach($k in $variables.Keys) { [Environment]::SetEnvironmentVariable($k,$old[$k],'Process') } }
 $script:children += $p
 try { $script:job.Add($p.Handle) } catch { if (!$p.HasExited) { $p.Kill() }; throw }
}
function Start-Services {
 try {
  $start.Enabled=$false; $open.Enabled=$false; $apply.Enabled=$false
  foreach ($port in @(3000,8000)) {
   $listener = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Loopback,$port)
   try { $listener.Start() } catch { throw "Port $port is occupied. Close the other application, then click Start services. No unrelated processes were stopped." } finally { $listener.Stop() }
  }
  $script:job=New-Object PlantJob
  $vars=@{PLANT_DATA_DIR=$data;MPLCONFIGDIR=(Join-Path $root 'matplotlib-cache');PYTHONNOUSERSITE='1';PYTHONUTF8='1';DEEPSEEK_API_KEY='';QWEN_API_KEY=''}
  if($key.Text) { if($provider.SelectedIndex -eq 0) {$vars.DEEPSEEK_API_KEY=$key.Text} else {$vars.QWEN_API_KEY=$key.Text} }
  Start-Child (Join-Path $root 'runtime\python\python.exe') '-m uvicorn backend.app:app --host 127.0.0.1 --port 8000' $appRoot 'backend' $vars
  Start-Child (Join-Path $root 'runtime\node\node.exe') 'node_modules\next\dist\bin\next start --hostname 127.0.0.1 --port 3000' (Join-Path $appRoot 'frontend') 'frontend' @{NEXT_TELEMETRY_DISABLED='1'}
  $script:deadline=[DateTime]::UtcNow.AddSeconds(120); $script:starting=$true
  $status.Text='Starting services. The browser will open when both services are ready...'; $timer.Start()
 } catch { $errorText=$_.Exception.Message; Stop-Services; $status.Text=$errorText+' See Open logs.' }
}
$timer.Add_Tick({
 try {
  foreach ($p in $script:children) { if ($p.HasExited) { throw 'A service exited unexpectedly. See Open logs for details.' } }
  if ($script:starting) {
   $healthy=$false
   try {
    $health=Invoke-RestMethod 'http://127.0.0.1:3000/api/health' -TimeoutSec 1
    $home=Invoke-WebRequest 'http://127.0.0.1:3000' -UseBasicParsing -TimeoutSec 2
    $healthy=($health.status -eq 'ok' -and $home.StatusCode -eq 200)
   } catch {}
   if($healthy) {
    $script:starting=$false; $script:ready=$true; $open.Enabled=$true; $apply.Enabled=$true
    $status.Text='Running - http://localhost:3000. Keep this launcher open.'
    Start-Process 'http://localhost:3000'
   } elseif ([DateTime]::UtcNow -gt $script:deadline) { throw 'Startup timed out. See Open logs; services have been stopped.' }
  }
 } catch { $errorText=$_.Exception.Message; Stop-Services; $status.Text=$errorText }
})
$open.Add_Click({Start-Process 'http://localhost:3000'})
$stop.Add_Click({Stop-Services})
$start.Add_Click({Start-Services})
$apply.Add_Click({Stop-Services; Start-Services})
$logButton.Add_Click({Start-Process explorer.exe -ArgumentList ('"'+$logs+'"')})
$form.Add_Shown({Start-Services})
$form.Add_FormClosing({Stop-Services; $key.Clear()})
try { [System.Windows.Forms.Application]::Run($form) } finally { Stop-Services; $script:mutex.ReleaseMutex(); $script:mutex.Dispose() }
