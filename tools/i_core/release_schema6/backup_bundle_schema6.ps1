[CmdletBinding(DefaultParameterSetName='Verify')]
param(
 [Parameter(Mandatory=$true)][ValidateSet('Create','Verify','RestoreInspection','SetupPortable','RestorePortable','Automatic')][string]$Operation,
 [Parameter(Mandatory=$true)][string]$ReleaseDirectory,
 [Parameter(Mandatory=$true)][ValidatePattern('^[a-f0-9]{64}$')][string]$ManifestSha256,
 [string]$KeyDirectory,
 [Parameter(ParameterSetName='Create',Mandatory=$true)][string]$SpecPath,
 [Parameter(ParameterSetName='Create',Mandatory=$true)][ValidatePattern('^[a-f0-9]{64}$')][string]$SpecSha256,
 [Parameter(ParameterSetName='SetupPortable',Mandatory=$true)][Parameter(ParameterSetName='RestorePortable',Mandatory=$true)][Parameter(ParameterSetName='Create',Mandatory=$true)][Parameter(ParameterSetName='RestoreInspection',Mandatory=$true)][string]$OutputDirectory,
 [Parameter(ParameterSetName='Create')][switch]$CreateKey,
 [Parameter(ParameterSetName='RestorePortable',Mandatory=$true)][Parameter(ParameterSetName='Verify',Mandatory=$true)][Parameter(ParameterSetName='RestoreInspection',Mandatory=$true)][string]$ArtifactPath,
 [Parameter(ParameterSetName='Verify',Mandatory=$true)][Parameter(ParameterSetName='RestoreInspection',Mandatory=$true)][ValidatePattern('^[a-f0-9]{64}$')][string]$ArtifactSha256,
 [Parameter(ParameterSetName='RestoreInspection',Mandatory=$true)][ValidatePattern('^[a-f0-9]{64}$')][string]$ExpectedDatabaseFingerprintSha256,
 [Parameter(ParameterSetName='SetupPortable',Mandatory=$true)][ValidatePattern('^[a-f0-9]{64}$')][string]$BackupSetId,
 [Parameter(ParameterSetName='RestorePortable',Mandatory=$true)][string]$EnvelopePath,
 [Parameter(ParameterSetName='RestorePortable',Mandatory=$true)][ValidatePattern('^[a-f0-9]{64}$')][string]$EnvelopeSha256,
 [Parameter(ParameterSetName='RestorePortable',Mandatory=$true)][string]$BindingPath,
 [Parameter(ParameterSetName='RestorePortable',Mandatory=$true)][ValidatePattern('^[a-f0-9]{64}$')][string]$BindingSha256,
 [Parameter(ParameterSetName='Automatic',Mandatory=$true)][string]$ConfigPath,
 [Parameter(ParameterSetName='Automatic',Mandatory=$true)][ValidatePattern('^[a-f0-9]{64}$')][string]$ConfigSha256
)
$ErrorActionPreference='Stop';$key=$null;$keyLock=$null;$reloaded=$null;$exitCode=2;$before=@{};$passwordBytes=$null;$secretFrame=$null;$schedulerLock=$null;$phase='release_validation'
foreach($entry in [Environment]::GetEnvironmentVariables('Process').GetEnumerator()){$before[$entry.Key]=$entry.Value}
function Assert-ReleasePath([string]$Path) {
 if(![IO.Path]::IsPathRooted($Path) -or [IO.Path]::GetFullPath($Path) -cne $Path -or $Path.Substring(2).Contains(':')){throw 'release_path_invalid'}
 $current=$Path
 while($current){$item=Get-Item -LiteralPath $current -Force;if($item.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'release_link_rejected'};$next=[IO.Path]::GetDirectoryName($current);if(!$next -or $next -eq $current){break};$current=$next}
}
function Quote-Argument([string]$Value) {
 if($Value.Contains('"') -or $Value.Contains("`n") -or $Value.Contains("`r")){throw 'argument_invalid'}
 return '"'+$Value.TrimEnd('\')+'"'
}
function Start-BackupChild([string]$Node,[string[]]$Arguments,[byte[]]$Secret,[byte[]]$Payload) {
 $info=New-Object Diagnostics.ProcessStartInfo;$info.FileName=$Node;$info.Arguments=($Arguments|ForEach-Object {Quote-Argument $_}) -join ' '
 $info.UseShellExecute=$false;$info.CreateNoWindow=$true;$info.RedirectStandardInput=$true;$info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true
 $info.EnvironmentVariables.Clear();foreach($n in @('SYSTEMROOT','WINDIR','TEMP','TMP','COMSPEC')){if($before.ContainsKey($n)){$info.EnvironmentVariables[$n]=$before[$n]}elseif($before.ContainsKey($n.ToLowerInvariant())){$info.EnvironmentVariables[$n]=$before[$n.ToLowerInvariant()]}}
 $process=New-Object Diagnostics.Process;$process.StartInfo=$info
 try {
  if(!$process.Start()){throw 'child_start_failed'}
  $outTask=$process.StandardOutput.ReadToEndAsync();$errorTask=$process.StandardError.ReadToEndAsync()
  if($Secret){$process.StandardInput.BaseStream.Write($Secret,0,$Secret.Length)}
  if($Payload){$process.StandardInput.BaseStream.Write($Payload,0,$Payload.Length)}
  $process.StandardInput.Close();$process.WaitForExit();$stdout=$outTask.GetAwaiter().GetResult();$stderr=$errorTask.GetAwaiter().GetResult()
  if($process.ExitCode -ne 0 -or $stdout.Length -gt 65536){throw 'verified_child_rejected'}
  return ($stdout|ConvertFrom-Json)
 } finally {$process.Dispose()}
}
try {
 if($Operation -ne 'RestorePortable' -and !$KeyDirectory){throw 'key_directory_required'}
 if($Operation -ne $PSCmdlet.ParameterSetName){throw 'operation_parameters_mismatch'}
 $env:PSModulePath=Join-Path $PSHOME 'Modules'
 Assert-ReleasePath $ReleaseDirectory
 $expected=Join-Path $ReleaseDirectory 'tools\i_core\release_schema6'
 if(![String]::Equals($PSScriptRoot,$expected,[StringComparison]::OrdinalIgnoreCase)){throw 'wrapper_release_mismatch'}
 $manifestPath=Join-Path $ReleaseDirectory 'manifest.json';Assert-ReleasePath $manifestPath
 if((Get-Item -LiteralPath $manifestPath).Length -gt 8388608 -or (Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash.ToLowerInvariant() -ne $ManifestSha256){throw 'manifest_hash_mismatch'}
 $manifest=Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8|ConvertFrom-Json
 if($manifest.format -ne 'i-core-schema6-preflight-candidate-v1' -or $manifest.files.Count -lt 1 -or $manifest.files.Count -gt 10000){throw 'manifest_contract_mismatch'}
 $seen=@{}
 foreach($file in $manifest.files){
  if($file.path -notmatch '^[A-Za-z0-9_./-]+$' -or $file.path -match '(^|/)\.\.?(/|$)' -or $file.path.StartsWith('/') -or $file.path.Contains('//') -or $seen.ContainsKey($file.path)){throw 'manifest_path_invalid'}
  $seen[$file.path]=$true;$source=Join-Path $ReleaseDirectory $file.path;Assert-ReleasePath $source
  if((Get-Item -LiteralPath $source).Length -ne $file.bytes -or (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash.ToLowerInvariant() -ne $file.sha256){throw 'release_file_changed'}
 }
 $actual=@(Get-ChildItem -LiteralPath $ReleaseDirectory -Recurse -Force -File)
 if($actual.Count -ne ($seen.Count+1)){throw 'release_inventory_mismatch'}
 foreach($file in $actual){Assert-ReleasePath $file.FullName;$relative=$file.FullName.Substring($ReleaseDirectory.Length+1).Replace('\','/');if($relative -ne 'manifest.json' -and !$seen.ContainsKey($relative)){throw 'release_inventory_mismatch'}}
 $node=Join-Path $ReleaseDirectory 'runtime\node.exe'
 if((Get-FileHash -LiteralPath $node -Algorithm SHA256).Hash.ToLowerInvariant() -ne '58e74bf02fc5bbacc41dcb8bef089961cd5bddd37830b87784e4fc624d145d1f'){throw 'node_hash_mismatch'}
 foreach($name in @([Environment]::GetEnvironmentVariables('Process').Keys)){if($name.ToUpperInvariant() -notin @('SYSTEMROOT','WINDIR','TEMP','TMP','COMSPEC')){[Environment]::SetEnvironmentVariable($name,$null,'Process')}}
 # Full pinned package validation precedes loading any key material.
 $verified=Start-BackupChild $node @((Join-Path $PSScriptRoot 'cli.mjs'),'verify',$ReleaseDirectory,$ManifestSha256) $null $null
 if($verified.manifest_sha256 -ne $ManifestSha256){throw 'release_verification_failed'}
 $env:PSModulePath=Join-Path $PSHOME 'Modules'
 . (Join-Path $PSScriptRoot 'key_custody.ps1') -Action Library -KeyDirectory $KeyDirectory -Purpose backup
 if($Operation -in @('Create','SetupPortable','RestoreInspection') -and $OutputDirectory){
  if([IO.Path]::GetFullPath($KeyDirectory).StartsWith([IO.Path]::GetFullPath($OutputDirectory).TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase) -or [String]::Equals($KeyDirectory,$OutputDirectory,[StringComparison]::OrdinalIgnoreCase)){throw 'key_output_separation_required'}
 }
 if($Operation -eq 'SetupPortable'){$operationBody=@{operation='setup_portable';outputDirectory=$OutputDirectory;backupSetId=$BackupSetId}}
 elseif($Operation -eq 'RestorePortable'){$operationBody=@{operation='restore_portable';envelopePath=$EnvelopePath;envelopeSha256=$EnvelopeSha256;bindingPath=$BindingPath;bindingSha256=$BindingSha256;artifactPath=$ArtifactPath;outputDirectory=$OutputDirectory}}
 elseif($Operation -eq 'Automatic'){
  $phase='automatic_config';Assert-BackupPrivateAcl $ConfigPath
  if((Get-Item -LiteralPath $ConfigPath).Length -gt 1048576 -or (Get-FileHash -LiteralPath $ConfigPath -Algorithm SHA256).Hash.ToLowerInvariant() -ne $ConfigSha256){throw 'automatic_config_anchor_mismatch'}
  $automaticConfig=Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8|ConvertFrom-Json
  Assert-BackupPlainPath $automaticConfig.policy.outputRoot
  $lockPath=Join-Path $automaticConfig.policy.outputRoot '.automatic.lock';Assert-BackupPlainPath $lockPath -Missing
  # Persistent pathname, ephemeral OS ownership: a crashed/killed process drops
  # this handle automatically. A leftover file never means a live writer.
  $existingLock=Test-Path -LiteralPath $lockPath
  if($existingLock){Assert-BackupPrivateAcl $lockPath}
  $phase='automatic_lock_open';$schedulerLock=New-Object IO.FileStream($lockPath,[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
  $phase='automatic_lock_identity';[RuntimeBackupFileIdentity]::RequireSingleLink($schedulerLock.SafeFileHandle)
  $phase='automatic_lock_acl'
  if(!$existingLock){Set-BackupPrivateAcl $lockPath $false}else{Assert-BackupPrivateAcl $lockPath}
  $operationBody=@{operation='automatic';configPath=$ConfigPath;configSha256=$ConfigSha256}
 }
 elseif($Operation -eq 'Create'){
  if([IO.Path]::GetFullPath($KeyDirectory).StartsWith([IO.Path]::GetFullPath($OutputDirectory).TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase) -or [String]::Equals($KeyDirectory,$OutputDirectory,[StringComparison]::OrdinalIgnoreCase)){throw 'key_output_separation_required'}
  $operationBody=@{operation='create';specPath=$SpecPath;specSha256=$SpecSha256;outputDirectory=$OutputDirectory}
 }elseif($Operation -eq 'RestoreInspection'){
  if([IO.Path]::GetFullPath($KeyDirectory).StartsWith([IO.Path]::GetFullPath($OutputDirectory).TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase) -or [String]::Equals($KeyDirectory,$OutputDirectory,[StringComparison]::OrdinalIgnoreCase)){throw 'key_output_separation_required'}
  $operationBody=@{operation='restore_inspection';artifactPath=$ArtifactPath;artifactSha256=$ArtifactSha256;outputDirectory=$OutputDirectory;expectedDatabaseFingerprintSha256=$ExpectedDatabaseFingerprintSha256}
 }else{$operationBody=@{operation='verify';artifactPath=$ArtifactPath;artifactSha256=$ArtifactSha256}}
 if($Operation -ne 'RestorePortable'){
  $phase='dpapi_load';$key=Get-RuntimeBackupKey -KeyDirectory $KeyDirectory -Purpose backup -Create:$CreateKey
 # Preserve the DPAPI blob actually used for this operation until its child finishes.
 $keyLock=New-Object IO.FileStream((Join-Path $KeyDirectory 'runtime-backup.dpapi'),[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
 [RuntimeBackupFileIdentity]::RequireSingleLink($keyLock.SafeFileHandle)
 $reloaded=Get-RuntimeBackupKey -KeyDirectory $KeyDirectory -Purpose backup
 $difference=0;for($i=0;$i -lt 32;$i++){$difference=$difference -bor ($key[$i] -bxor $reloaded[$i])}
 if($difference -ne 0){throw 'custody_changed'}
 [Array]::Clear($reloaded,0,$reloaded.Length);$reloaded=$null
 }else{$key=New-Object byte[] 32}
 if($Operation -in @('SetupPortable','RestorePortable')){
  function Read-PortablePasswordBytes {
   $secure=Read-Host 'Recovery passphrase (at least 16 UTF-8 bytes)' -AsSecureString;$ptr=[IntPtr]::Zero;$chars=$null
   try{$ptr=[Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure);$chars=New-Object char[] $secure.Length;for($j=0;$j -lt $chars.Length;$j++){$chars[$j]=[char][Runtime.InteropServices.Marshal]::ReadInt16($ptr,$j*2)};$bytes=[Text.Encoding]::UTF8.GetBytes($chars);if($bytes.Length -lt 16 -or $bytes.Length -gt 1024){[Array]::Clear($bytes,0,$bytes.Length);throw 'password_length'};return ,$bytes}
   finally{if($chars){[Array]::Clear($chars,0,$chars.Length)};if($ptr -ne [IntPtr]::Zero){[Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr)};$secure.Dispose()}
  }
  $passwordBytes=Read-PortablePasswordBytes
  if($Operation -eq 'SetupPortable'){$confirm=Read-PortablePasswordBytes;try{$diff=$passwordBytes.Length -bxor $confirm.Length;for($j=0;$j -lt [Math]::Min($passwordBytes.Length,$confirm.Length);$j++){$diff=$diff -bor ($passwordBytes[$j] -bxor $confirm[$j])};if($diff -ne 0){throw 'password_confirmation'}}finally{[Array]::Clear($confirm,0,$confirm.Length)}}
  $secretFrame=New-Object byte[] (40+$passwordBytes.Length);[Array]::Copy($key,0,$secretFrame,0,32);[Array]::Copy([Text.Encoding]::ASCII.GetBytes('IPW1'),0,$secretFrame,32,4);$n=[BitConverter]::GetBytes([uint32]$passwordBytes.Length);[Array]::Reverse($n);[Array]::Copy($n,0,$secretFrame,36,4);[Array]::Copy($passwordBytes,0,$secretFrame,40,$passwordBytes.Length)
 }else{$secretFrame=$key}
 $payload=[Text.Encoding]::UTF8.GetBytes(($operationBody|ConvertTo-Json -Compress))
 $phase='verified_child';$report=Start-BackupChild $node @((Join-Path $PSScriptRoot 'backup_key_child.mjs'),$ReleaseDirectory,$ManifestSha256) $secretFrame $payload
 if($report.verified -ne $true -or $report.scope -ne 'inventory_only' -or $report.production_completeness_not_attested -ne $true){throw 'backup_report_invalid'}
 [Console]::Out.WriteLine(($report|ConvertTo-Json -Compress));$exitCode=0
}catch{[Console]::Error.WriteLine((@{rejected=$true;code='runtime_backup_wrapper_rejected';phase=$phase}|ConvertTo-Json -Compress))}
finally{
 if($schedulerLock){$schedulerLock.Dispose()}
 if($passwordBytes){[Array]::Clear($passwordBytes,0,$passwordBytes.Length)};if($secretFrame){[Array]::Clear($secretFrame,0,$secretFrame.Length)}
 if($key){[Array]::Clear($key,0,$key.Length)};if($reloaded){[Array]::Clear($reloaded,0,$reloaded.Length)};if($keyLock){$keyLock.Dispose()}
 foreach($name in @([Environment]::GetEnvironmentVariables('Process').Keys)){[Environment]::SetEnvironmentVariable($name,$null,'Process')}
 foreach($name in $before.Keys){[Environment]::SetEnvironmentVariable($name,$before[$name],'Process')}
}
exit $exitCode
