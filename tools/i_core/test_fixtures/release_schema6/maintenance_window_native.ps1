param([string]$ModulePath,[string]$Mode='suite',[string]$Root)
$ErrorActionPreference='Stop';Set-StrictMode -Version 2
$env:PSModulePath=Join-Path $PSHOME 'Modules'
. $ModulePath
if($Mode-eq 'contender'){
 try {$w=Open-MaintenanceWindow -MaintenanceRoot $Root -WindowId 'window-parallel';Close-MaintenanceWindow $w;exit 10}catch{$cause=$_.Exception;while($cause.InnerException){$cause=$cause.InnerException};if(($cause.HResult-band 0xffff)-ne 32){throw};exit 0}
}
$Root=Join-Path ([IO.Path]::GetTempPath()) ('maintenance-window-fixture-'+[Guid]::NewGuid().ToString('N'))
$null=[IO.Directory]::CreateDirectory($Root)
$w=$null;$w2=$null;$guard=$null
function Check($Value,[string]$Code){if(-not $Value){throw $Code}}
function Bytes([string]$p){return [Convert]::ToBase64String([IO.File]::ReadAllBytes($p))}
try{
 # Deliberately stale legacy lock and receipt bytes must neither block nor change.
 $old=Join-Path $Root 'freeze-legacy-runtime.lock';[IO.File]::WriteAllBytes($old,[byte[]]@(1,4,9,16))
 $legacy=Join-Path $Root 'frozen-legacy-runtime-ready.json';[IO.File]::WriteAllText($legacy,'synthetic-old-receipt')
 $guardPath=Join-Path $Root 'active-window.guard';[IO.File]::WriteAllBytes($guardPath,[byte[]]@(65,66,0,67))
 $oldBytes=Bytes $old;$legacyBytes=Bytes $legacy;$guardBytes=Bytes $guardPath
 $rootAcl=(Get-Acl -LiteralPath $Root).Sddl
 $oldAcl=(Get-Acl -LiteralPath $old).Sddl
 $w=Open-MaintenanceWindow -MaintenanceRoot $Root -WindowId 'window-first'
 # Run the actual ACL Apply consumer's directory assertion, without invoking
 # Apply or granting it access to any production path.
 $aclSource=Join-Path ([IO.Path]::GetDirectoryName($ModulePath)) 'acl-cutover-maintenance.ps1'
 $tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseFile($aclSource,[ref]$tokens,[ref]$errors)
 Check ($errors.Count-eq 0) 'acl_consumer_parse_failed'
 $fn=$ast.Find({param($n)$n-is [Management.Automation.Language.FunctionDefinitionAst]-and $n.Name-ceq 'Assert-PrivateDirectory'},$true)
 . ([scriptblock]::Create($fn.Extent.Text))
 function Assert-Plain([string]$p){Assert-MaintenancePlainDirectory $p}
 $owner=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
 Assert-PrivateDirectory $w.Directory
 Check ((Get-Acl -LiteralPath $Root).Sddl-ceq $rootAcl) 'existing_root_acl_changed'
 Check ((Get-Acl -LiteralPath $old).Sddl-ceq $oldAcl) 'legacy_artifact_acl_changed'
 $before=(Get-Acl -LiteralPath $w.Directory).Sddl
 $rejected=$false;try{Protect-NewMaintenanceWindow $w.Directory}catch{$rejected=$true}
 Check $rejected 'nonempty_window_reprotected'
 Check ((Get-Acl -LiteralPath $w.Directory).Sddl-ceq $before) 'nonempty_window_acl_changed'
 Check (Test-Path -LiteralPath $w.PhaseReceiptsDirectory -PathType Container) 'phase_directory_missing'
 # Contention is verified in another OS process, not a mocked FileStream.
 $ps=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
 $args=@('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',$PSCommandPath,'-ModulePath',$ModulePath,'-Mode','contender','-Root',$Root)
 $pi=[Diagnostics.ProcessStartInfo]::new();$pi.FileName=$ps;$pi.Arguments=($args|ForEach-Object {'"'+$_+'"'})-join ' ';$pi.UseShellExecute=$false;$pi.CreateNoWindow=$true
 $child=[Diagnostics.Process]::Start($pi);try{Check ($child.WaitForExit(15000)) 'contender_timeout';Check ($child.ExitCode-eq 0) 'parallel_window_entered'}finally{if(-not $child.HasExited){$child.Kill()};$child.Dispose()}
 Check (-not (Test-Path -LiteralPath (Join-Path $Root 'windows\window-parallel'))) 'contender_created_window'
 Close-MaintenanceWindow $w;$w=$null
 $first=Join-Path $Root 'windows\window-first\entry.lock';$firstBytes=Bytes $first
 $rejected=$false
 try {$bad=Open-MaintenanceWindow -MaintenanceRoot $Root -WindowId 'window-first';Close-MaintenanceWindow $bad}catch{if($_.Exception.Message-cne 'window_id_already_used'){throw};$rejected=$true}
 Check $rejected 'same_window_reentered'
 $w2=Open-MaintenanceWindow -MaintenanceRoot $Root -WindowId 'window-second';Close-MaintenanceWindow $w2;$w2=$null
 Check ((Bytes $first)-ceq $firstBytes) 'first_lock_changed'
 Check ((Bytes $old)-ceq $oldBytes) 'legacy_lock_changed'
 Check ((Bytes $legacy)-ceq $legacyBytes) 'legacy_receipt_changed'
 Check ((Bytes $guardPath)-ceq $guardBytes) 'guard_bytes_changed'
 # Existing receipt directory reserves even an interrupted/failed WindowId.
 $crashed=Join-Path $Root 'windows\interrupted';$null=[IO.Directory]::CreateDirectory($crashed)
 $rejected=$false;try{$bad=Open-MaintenanceWindow -MaintenanceRoot $Root -WindowId 'interrupted';Close-MaintenanceWindow $bad}catch{$rejected=$true};Check $rejected 'interrupted_window_reused'
 $rejected=$false;try{$bad=Open-MaintenanceWindow -MaintenanceRoot $Root -WindowId '..';Close-MaintenanceWindow $bad}catch{$rejected=$true};Check $rejected 'traversal_window_accepted'
 $guard=Acquire-MaintenanceGuard $Root
 $rejected=$false;try{$bad=Open-MaintenanceWindow -MaintenanceRoot $Root -WindowId 'window-guarded';Close-MaintenanceWindow $bad}catch{$rejected=$true};Check $rejected 'stage_guard_bypassed'
 $guard.Dispose();$guard=$null
 $links=Join-Path $Root 'hardlink-case';$null=[IO.Directory]::CreateDirectory($links)
 $null=New-Item -ItemType HardLink -Path (Join-Path $links 'active-window.guard') -Target $old
 $rejected=$false;try{$bad=Open-MaintenanceWindow -MaintenanceRoot $links -WindowId 'window-linked';Close-MaintenanceWindow $bad}catch{$rejected=$true};Check $rejected 'hardlinked_guard_accepted'
 Check ((Bytes $old)-ceq $oldBytes) 'hardlink_target_changed'
 $after=Open-MaintenanceWindow -MaintenanceRoot $Root -WindowId 'after-failure';Close-MaintenanceWindow $after
 [ordered]@{passed=$true;parallelRejected=$true;sameWindowRejected=$true;freshWindowAccepted=$true;oldBytesPreserved=$true;guardBytesPreserved=$true;interruptedWindowRejected=$true;traversalRejected=$true;stageGuardRejected=$true;hardlinkGuardRejected=$true;formalAclConsumerPassed=$true;existingAclsPreserved=$true;nonemptyProtectionRejected=$true}|ConvertTo-Json -Compress
}finally{
 if($guard){$guard.Dispose()};Close-MaintenanceWindow $w;Close-MaintenanceWindow $w2
 # Delete only the synthetic directory we created under the OS temp directory.
 $resolved=[IO.Path]::GetFullPath($Root);$temp=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\'
 if($resolved.StartsWith($temp,[StringComparison]::OrdinalIgnoreCase)-and [IO.Path]::GetFileName($resolved).StartsWith('maintenance-window-fixture-')){Remove-Item -LiteralPath $resolved -Recurse -Force}
}
