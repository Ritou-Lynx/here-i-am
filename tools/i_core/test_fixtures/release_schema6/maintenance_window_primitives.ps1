param([string]$Source)
$ErrorActionPreference='Stop';Set-StrictMode -Version 2
$env:PSModulePath=Join-Path $PSHOME 'Modules'
# Load exact reviewed function ASTs only; never invoke the production entry body.
$tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseFile($Source,[ref]$tokens,[ref]$errors)
if($errors.Count){throw 'source_parse_failed'}
$names=@('Fail','Hash','Plain','FileStamp','FrozenFiles','ExternalCheck','SameAlive','KillBound')
foreach($name in $names){$function=$ast.Find({param($a)$a-is [Management.Automation.Language.FunctionDefinitionAst]-and $a.Name-ceq $name},$true);if(-not $function){throw 'function_missing'};. ([scriptblock]::Create($function.Extent.Text))}
$entryPath=Join-Path ([IO.Path]::GetDirectoryName($Source)) 'enter-maintenance-window.ps1'
$entryAst=[Management.Automation.Language.Parser]::ParseFile($entryPath,[ref]$tokens,[ref]$errors)
foreach($name in @('Assert-EntryPlain','Get-EntryHandleHash','Assert-EntryPrivate')){$fn=$entryAst.Find({param($a)$a-is [Management.Automation.Language.FunctionDefinitionAst]-and $a.Name-ceq $name},$true);. ([scriptblock]::Create($fn.Extent.Text))}
$native=$ast.Find({param($a)$a-is [Management.Automation.Language.CommandAst]-and $a.GetCommandName()-eq 'Add-Type'},$true)
& ([scriptblock]::Create($native.Extent.Text))
$root=Join-Path ([IO.Path]::GetTempPath()) ('maintenance-window-primitives-'+[Guid]::NewGuid().ToString('N'))
$null=[IO.Directory]::CreateDirectory($root);$copyDirectory=Join-Path $root 'copy';$null=[IO.Directory]::CreateDirectory($copyDirectory)
$config=[pscustomobject]@{databasePath=(Join-Path $root 'synthetic.sqlite');approvalsPath=(Join-Path $root 'approvals.json');grantsPath=(Join-Path $root 'grants.json')}
$script:drift=$false;$script:rawFrozen=@();$child=$null
function Check($ok,[string]$code){if(-not $ok){throw $code}}
try{
 $entryFile=Join-Path $root 'entry-config.json';[IO.File]::WriteAllText($entryFile,'{"synthetic":true}')
 $sid=[Security.Principal.WindowsIdentity]::GetCurrent().User
 $acl=[Security.AccessControl.FileSecurity]::new();$acl.SetOwner($sid);$acl.SetAccessRuleProtection($true,$false)
 $acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new($sid,'FullControl','Allow'));Set-Acl -LiteralPath $entryFile -AclObject $acl
 Assert-EntryPlain $entryFile
 $handle=[IO.File]::Open($entryFile,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
 try{
  Assert-EntryPrivate $handle $sid.Value;Check ((Get-EntryHandleHash $handle)-ceq (Hash $entryFile)) 'entry_handle_hash_mismatch'
  $rejected=$false;try{[IO.File]::WriteAllText($entryFile,'replaced')}catch{$rejected=$true};Check $rejected 'entry_write_lease_bypassed'
  $rejected=$false;try{[IO.File]::Delete($entryFile)}catch{$rejected=$true};Check $rejected 'entry_delete_lease_bypassed'
 }finally{$handle.Dispose()}
 foreach($suffix in @('','-wal','-shm','-journal')){[IO.File]::WriteAllText(($config.databasePath+$suffix),'synthetic-'+$suffix)}
 foreach($name in @('approvals','grants')){[IO.File]::WriteAllText((Join-Path $root ($name+'.json')),'{}');[IO.File]::WriteAllText((Join-Path $copyDirectory ($name+'.json')),'{}')}
 $validation=[pscustomobject]@{rawAfter=@(@('','-wal','-shm','-journal')|ForEach-Object{FileStamp ($config.databasePath+$_)});external=[pscustomobject]@{approvals=(FileStamp $config.approvalsPath);grants=(FileStamp $config.grantsPath)}}
 $null=FrozenFiles $validation -Record;$null=FrozenFiles $validation
 foreach($suffix in @('','-wal','-shm','-journal')){
  $p=$config.databasePath+$suffix;$original=[IO.File]::ReadAllBytes($p);$modified=$original.Clone();$modified[0]=$modified[0]-bxor 1;[IO.File]::WriteAllBytes($p,$modified)
  $rejected=$false;try{$null=FrozenFiles $validation}catch{$rejected=$true};Check $rejected ('frozen_mutation_accepted_'+$suffix)
  [IO.File]::WriteAllBytes($p,$original)
 }
 # Online rawAfter SHM is also strict when establishing the frozen baseline.
 $p=$config.databasePath+'-shm';$bytes=[IO.File]::ReadAllBytes($p);$changed=$bytes.Clone();$changed[0]=$changed[0]-bxor 1;[IO.File]::WriteAllBytes($p,$changed)
 $rejected=$false;try{$null=FrozenFiles $validation -Record}catch{$rejected=$true};Check $rejected 'initial_shm_mutation_accepted';[IO.File]::WriteAllBytes($p,$bytes)
 $p=$config.databasePath+'-journal';$bytes=[IO.File]::ReadAllBytes($p);Remove-Item -LiteralPath $p
 $rejected=$false;try{$null=FrozenFiles $validation}catch{$rejected=$true};Check $rejected 'sidecar_disappearance_accepted';[IO.File]::WriteAllBytes($p,$bytes)
 # Only this fixture-owned child is inspected/killed. A forged start-time binding cannot kill it.
 $ps=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
 $pi=[Diagnostics.ProcessStartInfo]::new();$pi.FileName=$ps;$pi.Arguments='-NoProfile -NonInteractive -Command "Start-Sleep -Seconds 60"';$pi.UseShellExecute=$false;$pi.CreateNoWindow=$true
 $child=[Diagnostics.Process]::Start($pi);$null=$child.Handle
 $binding=[pscustomobject]@{pid=$child.Id;started_ticks=$child.StartTime.ToUniversalTime().Ticks.ToString();path=$child.MainModule.FileName;sha256=(Hash $child.MainModule.FileName)}
 Check (SameAlive $binding) 'owned_child_missing'
 $wrong=[pscustomobject]@{pid=$binding.pid;started_ticks='1';path=$binding.path;sha256=$binding.sha256}
 $rejected=$false;try{KillBound $wrong}catch{$rejected=$true};Check $rejected 'forged_identity_killed';Check (-not $child.HasExited) 'child_killed_after_rejection'
 KillBound $binding;Check ($child.WaitForExit(3000)) 'bound_child_not_stopped'
 [ordered]@{passed=$true;allFourByteMutationsRejected=$true;initialShmMutationRejected=$true;sidecarDisappearanceRejected=$true;forgedProcessIdentityRejected=$true;boundProcessStopped=$true;entryPinnedReadStable=$true}|ConvertTo-Json -Compress
}finally{
 if($child){if(-not $child.HasExited){$child.Kill();$null=$child.WaitForExit(3000)};$child.Dispose()}
 $resolved=[IO.Path]::GetFullPath($root);$temp=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\'
 if($resolved.StartsWith($temp,[StringComparison]::OrdinalIgnoreCase)-and [IO.Path]::GetFileName($resolved).StartsWith('maintenance-window-primitives-')){Remove-Item -LiteralPath $resolved -Recurse -Force}
}
