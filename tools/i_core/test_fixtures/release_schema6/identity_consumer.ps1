param([Parameter(Mandatory=$true)][string]$FixtureRoot,[Parameter(Mandatory=$true)][string]$TokenSource)
$ErrorActionPreference='Stop';Set-StrictMode -Version 2
$env:PSModulePath=Join-Path $PSHOME 'Modules'
Add-Type -Path $TokenSource
$report=[ordered]@{passed=$false;identity=[Schema6IdentityToken]::Current();fixedPrepare=$false;registrationValidation=$false;aclReceiptRead=$false}
function Invoke-ConsumerProcess([string]$Executable,[string[]]$Arguments){
 function Quote([string]$s){'"'+[regex]::Replace([regex]::Replace($s,'(\\*)"','$1$1\"'),'(\\+)$','$1$1')+'"'}
 $info=[Diagnostics.ProcessStartInfo]::new();$info.FileName=$Executable;$info.Arguments=($Arguments|ForEach-Object{Quote $_})-join ' '
 $info.UseShellExecute=$false;$info.CreateNoWindow=$true;$info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true
 $info.EnvironmentVariables.Clear();foreach($key in @('SystemRoot','WINDIR','TEMP','TMP','COMSPEC')){$value=[Environment]::GetEnvironmentVariable($key);if($value){$info.EnvironmentVariables[$key]=$value}};$info.EnvironmentVariables['PATHEXT']='.EXE'
 $child=[Diagnostics.Process]::new();$child.StartInfo=$info
 try{$null=$child.Start();$stdout=$child.StandardOutput.ReadToEndAsync();$stderr=$child.StandardError.ReadToEndAsync();$child.WaitForExit();$environment=@{};foreach($key in @('SystemRoot','WINDIR','TEMP','TMP','COMSPEC','PATHEXT')){$environment[$key]=$info.EnvironmentVariables[$key]};return @{executable=$Executable;arguments=$Arguments;nativeArguments=$info.Arguments;environment=$environment;exitCode=$child.ExitCode;stdout=$stdout.GetAwaiter().GetResult();stderr=$stderr.GetAwaiter().GetResult()}}finally{$child.Dispose()}
}
try {
 $plan=Get-Content -LiteralPath (Join-Path $FixtureRoot 'consumer-plan.json') -Raw|ConvertFrom-Json
 if($report.identity.sid-cne $plan.ownerSid -or $report.identity.elevated -or $report.identity.administrator -or $report.identity.integritySid-cne 'S-1-16-8192'){throw 'consumer_identity_rejected'}
 if($report.identity.windowStation-cnotmatch '^Schema6Identity-[a-f0-9]{32}$' -or $report.identity.desktop-cnotmatch '^Consumer-[a-f0-9]{32}$'){throw 'consumer_private_desktop_required'}
 . (Join-Path $plan.maintenance 'owned_artifacts.ps1')
 foreach($p in @($plan.aclReceiptPath,$plan.configPath)){Assert-OwnedArtifact $p $plan.ownerSid}
 $acl=Get-Content -LiteralPath $plan.aclReceiptPath -Raw|ConvertFrom-Json
 if(!$acl.passed -or $acl.mode-cne 'Apply' -or $acl.verified_count-ne 144 -or $acl.expected_foreign_owner_count-ne 16){throw 'actual_apply_receipt_rejected'}
 $report.aclReceiptRead=$true
 $ps=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
 $config=Get-Content -LiteralPath $plan.configPath -Raw|ConvertFrom-Json
 $node=Join-Path $plan.release 'runtime\node.exe';$module=Join-Path $plan.maintenance 'prepare-production-login.mjs'
 # Independent read-only probe using the actual pinned Node and same clean env.
 $probe="import {readFileSync} from 'node:fs';import {pathToFileURL} from 'node:url';const m=await import(pathToFileURL(process.argv[2]).href);await m.validatePreparationInputs(JSON.parse(readFileSync(process.argv[1],'utf8')));process.stdout.write(JSON.stringify({validated:true}));"
 $report.nodePrecheck=Invoke-ConsumerProcess $node @('--input-type=module','--eval',$probe,$plan.configPath,$module)
 $prepare=Join-Path $plan.maintenance 'prepare-production-login.ps1';$pins=@($config.maintenanceFiles|Where-Object{$_.path-ceq $prepare})
 if($pins.Count-ne 1){throw 'consumer_prepare_source_pin_required'}
 $report.prepareProcess=Invoke-ConsumerProcess $ps @('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',(Join-Path $PSScriptRoot 'identity_prepare_observer.ps1'),'-PrepareScript',$prepare,'-ConfigPath',$plan.configPath,'-ExpectedConfigSha256',$plan.configSha256,'-ExpectedSourceSha256',$pins[0].sha256,'-FixtureRoot',$FixtureRoot)
 $observation=Join-Path $FixtureRoot 'prepare-node-observations.json'
 if(Test-Path -LiteralPath $observation){$report.prepareNodeObservations=Get-Content -LiteralPath $observation -Raw|ConvertFrom-Json}
 if($report.prepareProcess.exitCode-ne 0){throw ('consumer_prepare_rejected:'+$report.prepareProcess.stdout)}
 if(!$report.prepareNodeObservations.sourceUnchanged -or !$report.prepareNodeObservations.breakpointRemoved -or $report.prepareNodeObservations.observationError -or @($report.prepareNodeObservations.calls).Count-ne 2){throw 'consumer_observation_rejected'}
 $prepared=$report.prepareProcess.stdout|ConvertFrom-Json
 if(!$prepared.passed -or !$prepared.fixed_prepare_validated -or $prepared.registered -or $prepared.started){throw 'consumer_prepare_report_rejected'}
 $report.fixedPrepare=$true
 $config=Get-Content -LiteralPath $plan.configPath -Raw|ConvertFrom-Json
 Assert-OwnedArtifact $config.outputXmlPath $plan.ownerSid;Assert-OwnedArtifact $config.preparedReceiptPath $plan.ownerSid
 # Same guarded input and prepared proof validation used by RegisterOnly, read-only.
 $raw=& (Join-Path $plan.release 'runtime\node.exe') (Join-Path $plan.maintenance 'prepare-production-login.mjs') --config $plan.configPath --config-sha256 $plan.configSha256 --validate-registration
 if($LASTEXITCODE-ne 0 -or !(($raw-join ''|ConvertFrom-Json).validated)){throw 'consumer_registration_validation_rejected'}
 $report.registrationValidation=$true;$report.passed=$true
} catch {$report.error=[string]$_.Exception.Message}
[IO.File]::WriteAllText((Join-Path $FixtureRoot 'consumer-result.json'),($report|ConvertTo-Json -Depth 12),[Text.UTF8Encoding]::new($false))
if(!$report.passed){exit 1}
