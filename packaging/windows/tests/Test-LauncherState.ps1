$ErrorActionPreference='Stop'
$path=Join-Path $PSScriptRoot '..\Launcher.ps1'
$tokens=$null;$errors=$null
$ast=[System.Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$errors)
if($errors.Count){throw ($errors | Out-String)}
$function=$ast.Find({param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Update-ServiceState'},$true)
. ([scriptblock]::Create($function.Extent.Text))
$timer=New-Object PSObject
$timer | Add-Member ScriptMethod Stop {}
$timer | Add-Member ScriptMethod Start {}
$status=@{Text=''};$open=@{Enabled=$false};$apply=@{Enabled=$false}
$script:children=@();$script:ready=$false;$script:starting=$true;$script:phase='backend'
$script:deadline=[DateTime]::UtcNow.AddMinutes(1);$script:frontendStarts=0;$script:browserStarts=0;$script:failure=$null
function Write-Diagnostic($message) {}
function Start-Frontend {$script:frontendStarts++;$script:phase='frontend'}
function Start-Process {$script:browserStarts++}
function Fail-Startup($message) {$script:failure=$message;$script:starting=$false;$script:ready=$false}
function Invoke-RestMethod {return @{status='ok'}}
function Invoke-WebRequest {return @{StatusCode=200}}
Update-ServiceState
if($script:frontendStarts -ne 1 -or $open.Enabled){throw 'Frontend must start only after backend health, and website must remain disabled'}
Update-ServiceState
if(!$open.Enabled -or !$script:ready -or $script:starting -or $script:browserStarts -ne 1 -or $script:failure){throw 'Successful proxy/home checks did not reach ready (HOME regression)'}
# A dead backend must fail immediately with its exit code, without waiting for a timeout.
$dead=New-Object PSObject -Property @{HasExited=$true;Name='backend';ExitCodeText='23'}
$dead | Add-Member ScriptMethod FlushExited {}
$script:children=@($dead);$script:starting=$true;$script:ready=$false
Update-ServiceState
if($script:failure -notlike '*backend*23*'){throw 'Early backend exit was not identified'}
# Retain the actual health failure reason at a phase-specific timeout.
$script:children=@();$script:starting=$true;$script:phase='backend';$script:failure=$null
$script:deadline=[DateTime]::UtcNow.AddSeconds(-1)
function Invoke-RestMethod {throw 'test connection refused'}
Update-ServiceState
if($script:failure -notlike '*backend startup timed out*test connection refused*'){throw 'Timeout diagnostics swallowed the cause'}
Write-Host 'PASS: staged readiness, HOME regression, early backend exit, phase-specific timeout'
