# Sole standalone preparation writer. No task registration/start or mode bypass.
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$ConfigPath,[Parameter(Mandatory=$true)][ValidatePattern('^[a-f0-9]{64}$')][string]$ExpectedConfigSha256)
$ErrorActionPreference='Stop';Set-StrictMode -Version 2
$env:PSModulePath=Join-Path $PSHOME 'Modules'
$leases=New-Object 'System.Collections.Generic.List[System.IDisposable]';$exitCode=2;$report=$null
function Open-BootstrapPin([string]$Path,[string]$Expected){
 if($Expected-cnotmatch '^[a-f0-9]{64}$' -or $Path-notmatch '^[A-Za-z]:\\' -or $Path.Substring(2).Contains(':') -or [IO.Path]::GetFullPath($Path)-cne $Path){throw 'prepare_bootstrap_input_rejected'}
 for($q=$Path;$q;$q=[IO.Path]::GetDirectoryName($q)){if(([IO.File]::GetAttributes($q)-band [IO.FileAttributes]::ReparsePoint)-ne 0){throw 'prepare_bootstrap_reparse_rejected'}}
 $h=[IO.File]::Open($Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
 try{
  $owner=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value;$acl=$h.GetAccessControl()
  if($acl.GetOwner([Security.Principal.SecurityIdentifier]).Value-cne $owner){throw 'prepare_bootstrap_owner_rejected'}
  foreach($r in $acl.GetAccessRules($true,$true,[Security.Principal.SecurityIdentifier])){if($r.AccessControlType-eq 'Allow' -and $r.IdentityReference.Value-notin @($owner,'S-1-5-18','S-1-5-32-544')){throw 'prepare_bootstrap_acl_rejected'}}
  $sha=[Security.Cryptography.SHA256]::Create();try{$hash=([BitConverter]::ToString($sha.ComputeHash($h))).Replace('-','').ToLowerInvariant()}finally{$sha.Dispose()}
  if($hash-cne $Expected){throw 'prepare_bootstrap_hash_rejected'};$h.Position=0;$leases.Add($h);return $h
 }catch{$h.Dispose();throw}
}
function Invoke-PrepareNode([string]$Code){
 $arguments=@('--input-type=module','--eval',$Code,$ConfigPath,(Join-Path $PSScriptRoot 'prepare-production-login.mjs'))
 $quoted=@($arguments|ForEach-Object{if($_.Contains('"') -or $_.EndsWith('\') -or $_.Contains([char]13) -or $_.Contains([char]10)){throw 'prepare_argument_rejected'};'"'+$_+'"'})
 $info=New-Object Diagnostics.ProcessStartInfo;$info.FileName=$node;$info.Arguments=$quoted -join ' ';$info.UseShellExecute=$false;$info.CreateNoWindow=$true;$info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true
 $info.EnvironmentVariables.Clear();foreach($key in @('SystemRoot','WINDIR','TEMP','TMP','COMSPEC')){$v=[Environment]::GetEnvironmentVariable($key);if($v){$info.EnvironmentVariables[$key]=$v}};$info.EnvironmentVariables['PATHEXT']='.EXE'
 $child=New-Object Diagnostics.Process;$child.StartInfo=$info
 try{$null=$child.Start();$out=$child.StandardOutput.ReadToEndAsync();$err=$child.StandardError.ReadToEndAsync()
  # Keep the guard until the fixed Node parent really exits. Its PrepareOnly
  # invocation has its own timeout; never release the guard on a parent-only kill.
  $child.WaitForExit();$null=$err.GetAwaiter().GetResult();if($child.ExitCode-ne 0){throw 'prepare_node_rejected'};return $out.GetAwaiter().GetResult()
 }finally{$child.Dispose()}
}
try{
 if($PSVersionTable.PSVersion.Major-ne 5 -or $PSVersionTable.PSEdition-ne 'Desktop'){throw 'windows_powershell_51_required'}
 $configuration=Open-BootstrapPin $ConfigPath $ExpectedConfigSha256
 $reader=[IO.StreamReader]::new($configuration,[Text.UTF8Encoding]::new($false),$true,1024,$true);try{$config=$reader.ReadToEnd()|ConvertFrom-Json}finally{$reader.Dispose()}
 if($config.format-cne 'schema6-maintenance-login-config-v2' -or $config.ownerSid-cne [Security.Principal.WindowsIdentity]::GetCurrent().User.Value -or $config.windowId-cnotmatch '^[A-Za-z0-9][A-Za-z0-9_-]{7,79}$'){throw 'prepare_configuration_rejected'}
 $required=@('prepare-production-login.ps1','prepare-production-login.mjs','prepare_live_guard.ps1','maintenance_window.ps1','maintenance_outputs.mjs','acl_receipt.mjs','register-approved-login.ps1','register_task_primitives.ps1','task_security_policy.ps1')|ForEach-Object{Join-Path $PSScriptRoot $_}
 $required+= [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\release_schema6\package.mjs'))
 foreach($p in $required){$entry=@($config.maintenanceFiles|Where-Object{$_.path-ceq $p});if($entry.Count-ne 1){throw 'prepare_closure_pin_required'};$null=Open-BootstrapPin $p $entry[0].sha256}
 . (Join-Path $PSScriptRoot 'prepare_live_guard.ps1')
 . (Join-Path $PSScriptRoot 'maintenance_window.ps1')
 . (Join-Path $PSScriptRoot 'register_task_primitives.ps1')
 . (Join-Path $PSScriptRoot 'task_security_policy.ps1')
 Assert-PreparePrivate $config.maintenanceRoot
 if(!(Test-Path -LiteralPath (Join-Path $config.maintenanceRoot 'active-window.guard') -PathType Leaf)){throw 'prepare_existing_guard_required'}
 $leases.Add((Acquire-MaintenanceGuard $config.maintenanceRoot))
 # Revalidate all opened sources through native final-path/link-count identity.
 $leases.Add((Open-PreparePin $ConfigPath $ExpectedConfigSha256))
 foreach($entry in $config.maintenanceFiles){$leases.Add((Open-PreparePin $entry.path $entry.sha256))}
 foreach($pair in @(@($config.frozenReceiptPath,$config.frozenReceiptSha256),@($config.ownerApprovalPath,$config.ownerApprovalSha256),@($config.aclReceiptPath,$config.aclReceiptSha256),@($config.approvedXmlPath,$config.approvedXmlSha256),@($config.loginConfigurationPath,$config.loginConfigurationSha256))){$leases.Add((Open-PreparePin $pair[0] $pair[1]))}
 $manifestPath=Join-Path $config.releaseDirectory 'manifest.json';$leases.Add((Open-PreparePin $manifestPath $config.candidateManifestSha256));$manifest=Get-Content -LiteralPath $manifestPath -Raw|ConvertFrom-Json
 foreach($entry in $manifest.files){if($entry.path-notmatch '^[A-Za-z0-9_./-]+$' -or $entry.path.Contains('..') -or [IO.Path]::IsPathRooted($entry.path)){throw 'prepare_candidate_inventory_rejected'};$leases.Add((Open-PreparePin (Join-Path $config.releaseDirectory $entry.path) $entry.sha256 ([long]$entry.bytes)))}
 $node=Join-Path $config.releaseDirectory 'runtime\node.exe';$leases.Add((Open-PreparePin $node '58e74bf02fc5bbacc41dcb8bef089961cd5bddd37830b87784e4fc624d145d1f'))
 $frozen=Get-Content -LiteralPath $config.frozenReceiptPath -Raw|ConvertFrom-Json
 # The fixed literal API call has no callback or exposed internal CLI flag.
 $precheck="import {readFileSync} from 'node:fs';import {pathToFileURL} from 'node:url';const m=await import(pathToFileURL(process.argv[2]).href);await m.validatePreparationInputs(JSON.parse(readFileSync(process.argv[1],'utf8')));process.stdout.write(JSON.stringify({validated:true}));"
 $valid=(Invoke-PrepareNode $precheck)|ConvertFrom-Json;if($valid.validated-ne $true){throw 'prepare_precheck_rejected'}
 $service=New-Object -ComObject 'Schedule.Service';$service.Connect()
 Assert-PrepareLiveFrozen $config $frozen $service $leases
 $null=Assert-TaskSecurityPolicy $config ($service.GetFolder('\').GetSecurityDescriptor(7))
 $prepare="import {readFileSync} from 'node:fs';import {pathToFileURL} from 'node:url';const m=await import(pathToFileURL(process.argv[2]).href);const c=JSON.parse(readFileSync(process.argv[1],'utf8'));const r=await m.prepareProductionLogin(c,{configurationPath:process.argv[1]});process.stdout.write(JSON.stringify(r));"
 $report=(Invoke-PrepareNode $prepare)|ConvertFrom-Json
 if($report.passed-ne $true -or $report.registered-ne $false -or $report.started-ne $false){throw 'prepare_result_rejected'}
 Assert-PrepareLiveFrozen $config $frozen $service $leases
 $null=Assert-TaskSecurityPolicy $config ($service.GetFolder('\').GetSecurityDescriptor(7))
 $leases.Add((Open-PreparePin $config.outputXmlPath $config.approvedXmlSha256))
 Assert-PreparePrivate ([IO.Path]::GetDirectoryName($config.preparedReceiptPath))
 $bytes=[Text.UTF8Encoding]::new($false).GetBytes(($report|ConvertTo-Json -Depth 15)+"`n")
 $h=[IO.File]::Open($config.preparedReceiptPath,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
 try{
  # Publish no JSON until the newly opened file has the private owner/DACL.
  $acl=$h.GetAccessControl();$acl.SetOwner([Security.Principal.SecurityIdentifier]::new($config.ownerSid));$h.SetAccessControl($acl);$acl=$h.GetAccessControl()
  if($acl.GetOwner([Security.Principal.SecurityIdentifier]).Value-cne $config.ownerSid){throw 'prepare_receipt_owner_rejected'}
  foreach($r in $acl.GetAccessRules($true,$true,[Security.Principal.SecurityIdentifier])){if($r.AccessControlType-eq 'Allow' -and $r.IdentityReference.Value-notin @($config.ownerSid,'S-1-5-18','S-1-5-32-544')){throw 'prepare_receipt_acl_rejected'}}
  $h.Write($bytes,0,$bytes.Length);$h.Flush($true)
 }finally{$h.Dispose()}
 Assert-PreparePrivate $config.preparedReceiptPath;$exitCode=0
}catch{
 $code=if($_.Exception.Message-match '^[a-z][a-z0-9_]+$'){$_.Exception.Message}else{'production_login_prepare_rejected'}
 $report=@{passed=$false;code=$code;registered=$false;started=$false}
 # Rejection is stdout only: never write to a misconfigured receipt/raw path.
}finally{foreach($h in $leases){$h.Dispose()}}
[Console]::Out.WriteLine(($report|ConvertTo-Json -Depth 15 -Compress));exit $exitCode
