[CmdletBinding(DefaultParameterSetName='Verify')]
param(
 [Parameter(Mandatory=$true)][ValidateSet('Create','Verify')][string]$Operation,
 [Parameter(Mandatory=$true)][string]$ReleaseDirectory,
 [Parameter(Mandatory=$true)][ValidatePattern('^[a-f0-9]{64}$')][string]$ManifestSha256,
 [Parameter(Mandatory=$true)][string]$KeyDirectory,
 [Parameter(ParameterSetName='Create',Mandatory=$true)][string]$SpecPath,
 [Parameter(ParameterSetName='Create',Mandatory=$true)][ValidatePattern('^[a-f0-9]{64}$')][string]$SpecSha256,
 [Parameter(ParameterSetName='Create',Mandatory=$true)][string]$OutputDirectory,
 [Parameter(ParameterSetName='Create')][switch]$CreateKey,
 [Parameter(ParameterSetName='Verify',Mandatory=$true)][string]$ArtifactPath,
 [Parameter(ParameterSetName='Verify',Mandatory=$true)][ValidatePattern('^[a-f0-9]{64}$')][string]$ArtifactSha256
)
$ErrorActionPreference='Stop';$key=$null;$keyLock=$null;$reloaded=$null;$exitCode=2;$before=@{}
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
 if($Operation -eq 'Create'){
  if([IO.Path]::GetFullPath($KeyDirectory).StartsWith([IO.Path]::GetFullPath($OutputDirectory).TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase) -or [String]::Equals($KeyDirectory,$OutputDirectory,[StringComparison]::OrdinalIgnoreCase)){throw 'key_output_separation_required'}
  $operationBody=@{operation='create';specPath=$SpecPath;specSha256=$SpecSha256;outputDirectory=$OutputDirectory}
 }else{$operationBody=@{operation='verify';artifactPath=$ArtifactPath;artifactSha256=$ArtifactSha256}}
  $key=Get-RuntimeBackupKey -KeyDirectory $KeyDirectory -Purpose backup -Create:$CreateKey
 # Preserve the DPAPI blob actually used for this operation until its child finishes.
 $keyLock=New-Object IO.FileStream((Join-Path $KeyDirectory 'runtime-backup.dpapi'),[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
 [RuntimeBackupFileIdentity]::RequireSingleLink($keyLock.SafeFileHandle)
 $reloaded=Get-RuntimeBackupKey -KeyDirectory $KeyDirectory -Purpose backup
 $difference=0;for($i=0;$i -lt 32;$i++){$difference=$difference -bor ($key[$i] -bxor $reloaded[$i])}
 if($difference -ne 0){throw 'custody_changed'}
 [Array]::Clear($reloaded,0,$reloaded.Length);$reloaded=$null
 $payload=[Text.Encoding]::UTF8.GetBytes(($operationBody|ConvertTo-Json -Compress))
 $report=Start-BackupChild $node @((Join-Path $PSScriptRoot 'backup_key_child.mjs'),$ReleaseDirectory,$ManifestSha256) $key $payload
 if($report.verified -ne $true -or $report.scope -ne 'inventory_only' -or $report.production_completeness_not_attested -ne $true){throw 'backup_report_invalid'}
 [Console]::Out.WriteLine(($report|ConvertTo-Json -Compress));$exitCode=0
}catch{[Console]::Error.WriteLine('{"rejected":true,"code":"runtime_backup_wrapper_rejected"}')}
finally{
 if($key){[Array]::Clear($key,0,$key.Length)};if($reloaded){[Array]::Clear($reloaded,0,$reloaded.Length)};if($keyLock){$keyLock.Dispose()}
 foreach($name in @([Environment]::GetEnvironmentVariables('Process').Keys)){[Environment]::SetEnvironmentVariable($name,$null,'Process')}
 foreach($name in $before.Keys){[Environment]::SetEnvironmentVariable($name,$before[$name],'Process')}
}
exit $exitCode
