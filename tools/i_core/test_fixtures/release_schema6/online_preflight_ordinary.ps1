param([Parameter(Mandatory=$true)][string]$NodePath,[Parameter(Mandatory=$true)][string]$ArgumentsBase64)
$ErrorActionPreference='Stop';Set-StrictMode -Version 2
. (Join-Path $PSScriptRoot 'ordinary_fixture.ps1')
Invoke-OrdinaryFixtureIfElevated $PSCommandPath $PSBoundParameters
Add-Type -Path (Join-Path $PSScriptRoot 'identity_token.cs')
$identity=[Schema6IdentityToken]::Current()
if($identity.elevated -or $identity.administrator -or $identity.owner-cne $identity.sid -or $identity.integritySid-cne 'S-1-16-8192'){throw 'online_fixture_ordinary_token_required'}
function Quote-NativeArgument([string]$Value){
 return '"'+[regex]::Replace([regex]::Replace($Value,'(\\*)"','$1$1\"'),'(\\+)$','$1$1')+'"'
}
$json=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($ArgumentsBase64))
$null=$json|ConvertFrom-Json
$info=[Diagnostics.ProcessStartInfo]::new();$info.FileName=$NodePath
$info.Arguments=(Quote-NativeArgument (Join-Path $PSScriptRoot 'online_preflight_fixture.mjs'))+' '+(Quote-NativeArgument $json)
$info.UseShellExecute=$false;$info.CreateNoWindow=$true;$info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true
# Host proof is for the outer dispatcher only. The real Node fixture and its
# production adapter retain their original OS-only clean environment.
$info.EnvironmentVariables.Clear()
foreach($name in @('SystemRoot','WINDIR','TEMP','TMP','COMSPEC')){$value=[Environment]::GetEnvironmentVariable($name);if($null-ne $value){$info.EnvironmentVariables[$name]=$value}}
$info.EnvironmentVariables['PATHEXT']='.EXE'
$child=[Diagnostics.Process]::new();$child.StartInfo=$info
try{
 if(!$child.Start()){throw 'online_fixture_child_start_failed'}
 $stdout=$child.StandardOutput.ReadToEndAsync();$stderr=$child.StandardError.ReadToEndAsync();$child.WaitForExit()
 $output=$stdout.GetAwaiter().GetResult();$errors=$stderr.GetAwaiter().GetResult()
 # Success goes through PowerShell's success stream so the limited dispatcher
 # can capture JSON; diagnostic stderr cannot contaminate that JSON.
 if($output){Write-Output $output}
 if($errors){Write-Error -Message $errors -ErrorAction Continue}
 exit $child.ExitCode
}finally{$child.Dispose()}
