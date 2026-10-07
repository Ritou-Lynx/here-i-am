param([Parameter(Mandatory=$true)][string]$PrepareScript,[Parameter(Mandatory=$true)][string]$ConfigPath,[Parameter(Mandatory=$true)][string]$ExpectedConfigSha256,[Parameter(Mandatory=$true)][string]$ExpectedSourceSha256,[Parameter(Mandatory=$true)][string]$FixtureRoot)
$ErrorActionPreference='Stop';Set-StrictMode -Version 2
$env:PSModulePath=Join-Path $PSHOME 'Modules'
$root=[IO.Path]::GetFullPath($FixtureRoot)
if($root-cne $FixtureRoot -or [IO.Path]::GetFileName($root)-cnotmatch '^schema6-identity-[A-Za-z0-9]+$'){throw 'observer_synthetic_root_required'}
$source=[IO.Path]::GetFullPath($PrepareScript)
if(!$source.StartsWith($root+'\',[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($source)-cne 'prepare-production-login.ps1'){throw 'observer_source_scope_rejected'}
function SourceHash{(Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash.ToLowerInvariant()}
if((SourceHash)-cne $ExpectedSourceSha256){throw 'observer_source_hash_rejected'}
$diagnostic=Join-Path $root 'prepare-node-observations.json'
if(Test-Path -LiteralPath $diagnostic){throw 'observer_fresh_report_required'}
$parseErrors=$null;$tokens=$null;$ast=[Management.Automation.Language.Parser]::ParseFile($source,[ref]$tokens,[ref]$parseErrors)
if($parseErrors.Count){throw 'observer_parse_rejected'}
$functions=@($ast.FindAll({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name-ceq 'Invoke-PrepareNode'},$true))
if($functions.Count-ne 1){throw 'observer_function_shape_rejected'}
$waits=@($functions[0].FindAll({param($n)$n -is [Management.Automation.Language.InvokeMemberExpressionAst] -and $n.Member.Value-ceq 'WaitForExit' -and $n.Expression -is [Management.Automation.Language.VariableExpressionAst] -and $n.Expression.VariablePath.UserPath-ceq 'child'},$true))
if($waits.Count-ne 1){throw 'observer_wait_shape_rejected'}
$global:Schema6FixtureNodeObservation=[ordered]@{sourceSha256=$ExpectedSourceSha256;sourceUnchanged=$false;breakpointRemoved=$false;calls=@();observationError=$null;path=$diagnostic}
$breakpoint=$null;$code=2
try{
 $breakpoint=Set-PSBreakpoint -Script $source -Line $waits[0].Extent.StartLineNumber -Action {
  try{
   # Read the original function's existing process/tasks. No Code/config/source,
   # result, guard or process-state assignment. The original line still executes.
   $child.WaitForExit()
   $observedStdout=$out.GetAwaiter().GetResult();$observedStderr=$err.GetAwaiter().GetResult()
   $sha=[Security.Cryptography.SHA256]::Create();try{$codeHash=([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Code)))).Replace('-','').ToLowerInvariant()}finally{$sha.Dispose()}
   $s=$global:Schema6FixtureNodeObservation
   $phase=if($s.calls.Count-eq 0){'precheck'}elseif($s.calls.Count-eq 1){'prepare'}else{'unexpected'}
   $s.calls+=@{sequence=$s.calls.Count+1;phase=$phase;codeSha256=$codeHash;executable=$child.StartInfo.FileName;arguments=$child.StartInfo.Arguments;environment=@{};exitCode=$child.ExitCode;stdout=$observedStdout;stderr=$observedStderr}
   foreach($key in @('SystemRoot','WINDIR','TEMP','TMP','COMSPEC','PATHEXT')){$s.calls[-1].environment[$key]=$child.StartInfo.EnvironmentVariables[$key]}
  }catch{$global:Schema6FixtureNodeObservation.observationError=[string]$_.Exception.Message}
  [IO.File]::WriteAllText($global:Schema6FixtureNodeObservation.path,($global:Schema6FixtureNodeObservation|ConvertTo-Json -Depth 10),[Text.UTF8Encoding]::new($false))
 }
 & $source -ConfigPath $ConfigPath -ExpectedConfigSha256 $ExpectedConfigSha256
 $code=$LASTEXITCODE
}finally{
 if($breakpoint){Remove-PSBreakpoint -Breakpoint $breakpoint;$global:Schema6FixtureNodeObservation.breakpointRemoved=(@(Get-PSBreakpoint|Where-Object{$_.Id-eq $breakpoint.Id}).Count-eq 0)}
 $global:Schema6FixtureNodeObservation.sourceUnchanged=((SourceHash)-ceq $ExpectedSourceSha256)
 [IO.File]::WriteAllText($diagnostic,($global:Schema6FixtureNodeObservation|ConvertTo-Json -Depth 10),[Text.UTF8Encoding]::new($false))
 if(!$global:Schema6FixtureNodeObservation.sourceUnchanged){throw 'observer_source_changed'}
 Remove-Variable Schema6FixtureNodeObservation -Scope Global
}
exit $code
