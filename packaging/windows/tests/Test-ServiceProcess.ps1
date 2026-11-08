param([Parameter(Mandatory=$true)][string]$Python)
$ErrorActionPreference='Stop'
Add-Type -Path (Join-Path $PSScriptRoot '..\ServiceProcess.cs')
$testRoot=Join-Path ([IO.Path]::GetTempPath()) ('plant service test '+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory $testRoot | Out-Null
$child=$null
try {
 $probe=Join-Path $testRoot 'probe.py'
 @'
import os,sys
print('stdout-captured', flush=True)
print('stderr-captured', file=sys.stderr, flush=True)
print('cwd=' + os.getcwd(), flush=True)
print('env=' + os.environ.get('PLANT_TEST_VARIABLE', ''), flush=True)
sys.exit(42)
'@ | Set-Content -LiteralPath $probe -Encoding UTF8
 $map=New-Object 'System.Collections.Generic.Dictionary[string,string]'
 $map['PLANT_TEST_VARIABLE']='child-only'
 $out=Join-Path $testRoot 'out.log';$err=Join-Path $testRoot 'err.log'
 $child=New-Object PlantService('probe',$Python,('-u "'+$probe+'"'),$testRoot,$out,$err,$map)
 $child.Start()
 if(!$child.Process.WaitForExit(10000)){throw 'Probe timeout'}
 $child.FlushExited()
 if($child.Process.ExitCode -ne 42){throw 'Lost exit code'}
 $stdout=Get-Content $out -Raw; $stderr=Get-Content $err -Raw
 if(!$stdout.Contains('stdout-captured') -or !$stdout.Contains($testRoot) -or !$stdout.Contains('env=child-only') -or !$stderr.Contains('stderr-captured')){throw 'Pipe/environment/working-directory capture failed'}
 if([Environment]::GetEnvironmentVariable('PLANT_TEST_VARIABLE','Process') -eq 'child-only'){throw 'Parent environment modified'}
 $child.Dispose();$child=$null
 # Simulate failure before Python bootstrap runs (missing stdlib/site configuration).
 $map['PYTHONHOME']=Join-Path $testRoot 'missing-python-home'
 $child=New-Object PlantService('broken',$Python,'-u -c "pass"',$testRoot,$out,$err,$map)
 $child.Start()
 if(!$child.Process.WaitForExit(10000)){throw 'Broken interpreter timeout'}
 $child.FlushExited()
 if($child.Process.ExitCode -eq 0 -or !(Get-Content $err -Raw)){throw 'Early interpreter failure was not captured'}
 Write-Host 'PASS: real child output, stderr, exit code, spaced cwd, scoped environment and pre-bootstrap interpreter failure'
} finally {
 if($child){$child.Dispose()}
 Remove-Item -LiteralPath $testRoot -Recurse -Force
}
