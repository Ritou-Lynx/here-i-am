[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$ConfigurationPath,[Parameter(Mandatory=$true)][ValidatePattern('^[a-f0-9]{64}$')][string]$ConfigurationSha256)
$ErrorActionPreference='Stop'
$env:PSModulePath="$PSHOME\Modules"
$handles=@();$hostLease=$null;$imageLease=$null
function Hash-File([string]$Path){return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()}
function Read-Pinned([string]$Path,[string]$Hash){
 Pin-BootstrapFile $Path
 $script:handles += [IO.File]::Open($Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
 if((Hash-File $Path)-cne $Hash){throw 'session_close_input_changed'}
 return (Get-Content -LiteralPath $Path -Raw|ConvertFrom-Json)
}

# Self-contained pre-execution boundary; candidate code is not loaded here.
# Current-user candidate boundary. Same-user/admin compromise is outside this contract.
function Assert-BootstrapPath([string]$Target, [switch]$Root) {
  if ($Target -notmatch '^[A-Za-z]:[\\/]' -or $Target.Substring(2).Contains(':') -or
      -not ([IO.Path]::GetFullPath($Target).Equals($Target.Replace('/','\'),[StringComparison]::OrdinalIgnoreCase))) { throw 'canonical_absolute_path_required' }
  $current = $Target
  while ($current) {
    if (([IO.File]::GetAttributes($current) -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'linked_path_rejected' }
    $parent = [IO.Directory]::GetParent($current)
    $current = if ($parent) { $parent.FullName } else { $null }
  }
  $sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
  $acl = Get-Acl -LiteralPath $Target
  if ($acl.GetOwner([Security.Principal.SecurityIdentifier]).Value -ne $sid) { throw 'protected_owner_mismatch' }
  if ($Root -and -not $acl.AreAccessRulesProtected) { throw 'protected_root_required' }
  $own = $false
  foreach ($rule in $acl.GetAccessRules($true,$true,[Security.Principal.SecurityIdentifier])) {
    if ($rule.AccessControlType -eq 'Allow') {
      if ($rule.IdentityReference.Value -notin @($sid,'S-1-5-18','S-1-5-32-544')) { throw 'protected_acl_required' }
      if ($rule.IdentityReference.Value -eq $sid -and ($rule.FileSystemRights -band [Security.AccessControl.FileSystemRights]::FullControl) -eq [Security.AccessControl.FileSystemRights]::FullControl) { $own = $true }
    }
  }
  if (-not $own) { throw 'protected_user_control_required' }
}


Add-Type -TypeDefinition @"
using System;using System.IO;using System.Text;using System.Runtime.InteropServices;using Microsoft.Win32.SafeHandles;
public static class CloseInputFileIdentity {
 [StructLayout(LayoutKind.Sequential)]struct Info{public uint a,b,c,d,e,f,g,h,i,j,links,k,l;}
 [DllImport("kernel32.dll",SetLastError=true)]static extern bool GetFileInformationByHandle(SafeFileHandle h,out Info i);
 [DllImport("kernel32.dll",CharSet=CharSet.Unicode)]static extern uint GetFinalPathNameByHandle(SafeFileHandle h,StringBuilder b,uint n,uint flags);
 public static void Check(FileStream f,string path){Info i;var b=new StringBuilder(32768);uint n=GetFinalPathNameByHandle(f.SafeFileHandle,b,32768,0);if(!GetFileInformationByHandle(f.SafeFileHandle,out i)||i.links!=1||n==0||n>=32768||!String.Equals(b.ToString(),@"\\?\"+path,StringComparison.OrdinalIgnoreCase))throw new IOException("session_close_file_identity");}
}
"@
function Pin-BootstrapFile([string]$Path){
 Assert-BootstrapPath $Path
 $h=[IO.File]::Open($Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
 try{[CloseInputFileIdentity]::Check($h,$Path);$script:handles += $h}catch{$h.Dispose();throw}
}
function Assert-CloseOverlayManifest($m){
 if($m.format-cne'i-core-schema6-preflight-candidate-v1'-or$m.source_tree_kind-cne'private-candidate-overlay-v1'-or$m.base_checkout_context_only-isnot[bool]-or!$m.base_checkout_context_only-or$m.activation_supported-isnot[bool]-or$m.activation_supported){throw 'session_close_overlay_provenance'}
 if($m.base_checkout_commit-cnotmatch'^[a-f0-9]{40}$'-or$m.base_checkout_commit-cne$m.source_commit-or$m.core_commit-cne$m.source_commit-or$m.wrapper_commit-cne$m.source_commit-or$m.runtime_profile-cne'schema6-owned-lifecycle-v1'){throw 'session_close_overlay_provenance'}
 foreach($key in @('base_frozen_source_inventory_sha256','source_patch_sha256','dependency_inventory_sha256','candidate_inventory_sha256')){if($m.$key-cnotmatch'^[a-f0-9]{64}$'){throw 'session_close_overlay_provenance'}}
 if($m.policy.companion_upload_mode-cne'legacy_b3'-or$m.policy.companion_reply_jobs-isnot[bool]-or$m.policy.companion_reply_jobs-or$m.policy.activity_enabled-isnot[bool]-or$m.policy.activity_enabled-or$m.policy.domain_policy-cne'owner_managed'-or(@($m.policy.PSObject.Properties.Name)|Sort-Object)-join','-cne'activity_enabled,companion_reply_jobs,companion_upload_mode,domain_policy'){throw 'session_close_overlay_policy'}
 if($m.files-isnot[Array]-or$m.files.Count-lt1-or$m.files.Count-gt256-or($m.actual_files-isnot[int]-and$m.actual_files-isnot[long])-or$m.actual_files-ne$m.files.Count){throw 'session_close_release_inventory'}
 $map=New-Object 'System.Collections.Generic.Dictionary[string,object]' ([StringComparer]::Ordinal)
 $folded=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
 foreach($entry in $m.files){
  if((@($entry.PSObject.Properties.Name)|Sort-Object)-join','-cne'bytes,path,sha256'-or$entry.path-isnot[string]-or$entry.path-cnotmatch'^(?:runtime/node\.exe|tools/i_core/[A-Za-z0-9_-]+(?:/[A-Za-z0-9_-]+)*\.[A-Za-z0-9]+)$'-or$entry.path.Contains('..')-or$entry.sha256-cnotmatch'^[a-f0-9]{64}$'-or($entry.bytes-isnot[int]-and$entry.bytes-isnot[long])-or$entry.bytes-lt0-or$entry.bytes-gt134217728-or!$folded.Add($entry.path)){throw 'session_close_release_inventory'}
  $map.Add($entry.path,$entry)
 }
 if(!$map.ContainsKey('runtime/node.exe')-or$map['runtime/node.exe'].sha256-cne'58e74bf02fc5bbacc41dcb8bef089961cd5bddd37830b87784e4fc624d145d1f'){throw 'session_close_release_runtime'}
 [string[]]$orderedNames=@($map.Keys);[Array]::Sort($orderedNames,[StringComparer]::Ordinal)
 $entries=@(foreach($name in $orderedNames){$entry=$map[$name];[ordered]@{path=$name;bytes=[long]$entry.bytes;sha256=[string]$entry.sha256}})
 $bytes=[Text.UTF8Encoding]::new($false).GetBytes((ConvertTo-Json -InputObject $entries -Compress -Depth 5))
 $sha=[Security.Cryptography.SHA256]::Create()
 try{$digest=([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-','').ToLowerInvariant()}finally{$sha.Dispose()}
 if($digest-cne$m.candidate_inventory_sha256){throw 'session_close_overlay_inventory_hash'}
 return $orderedNames
}
function Assert-BootstrapRelease([string]$Root,[string]$Hash){
 Assert-BootstrapPath $Root -Root
 $mp=Join-Path $Root 'manifest.json';Pin-BootstrapFile $mp
 if($Hash-cnotmatch '^[a-f0-9]{64}$'-or (Hash-File $mp)-cne $Hash){throw 'session_close_release_manifest'}
 $m=Get-Content -LiteralPath $mp -Raw|ConvertFrom-Json
 $selected=@(Assert-CloseOverlayManifest $m)
 $script:legacyPackage=$false
 if($m.core_schema_version-ne 6-or $m.node_version-cne 'v24.14.1'-or $m.pinned_node_sha256-cne '58e74bf02fc5bbacc41dcb8bef089961cd5bddd37830b87784e4fc624d145d1f'){throw 'session_close_release_contract'}
 $actual=@(Get-ChildItem -LiteralPath $Root -Recurse -Force|ForEach-Object{Assert-BootstrapPath $_.FullName;if(-not $_.PSIsContainer){$_.FullName.Substring($Root.Length+1).Replace('\','/')}})
 if(@(Compare-Object (($selected+@('manifest.json'))|Sort-Object) ($actual|Sort-Object)).Count-ne 0){throw 'session_close_release_inventory'}
 foreach($e in $m.files){$p=Join-Path $Root $e.path;Pin-BootstrapFile $p;if((Get-Item -LiteralPath $p).Length-ne $e.bytes-or (Hash-File $p)-cne $e.sha256){throw 'session_close_release_content'}}
 if((Hash-File (Join-Path $Root 'runtime/node.exe'))-cne $m.pinned_node_sha256){throw 'session_close_release_runtime'}
}

try{
 # The caller pins this approved maintenance input; its own bytes are retained.
 Assert-BootstrapPath ([IO.Path]::GetDirectoryName($ConfigurationPath)) -Root
 Pin-BootstrapFile $ConfigurationPath
 Pin-BootstrapFile $PSCommandPath
 if((Hash-File $ConfigurationPath)-cne $ConfigurationSha256){throw 'session_close_input_changed'}
 $c=Get-Content -LiteralPath $ConfigurationPath -Raw|ConvertFrom-Json
 if($c.format-cne 'schema6-session-close-approved-v1'-or $c.approved-ne $true){throw 'session_close_approval_required'}
 $release=$c.releaseDirectory;$lifecycle=Join-Path $release 'tools/i_core/release_schema6/lifecycle'
 $ps=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
 Assert-BootstrapRelease $release $c.manifestSha256
 $helper=Join-Path $PSScriptRoot 'process_image_binding.ps1'
 Pin-BootstrapFile $helper
 if((Hash-File $helper)-cne $c.processImageBindingSha256-or (Hash-File $PSCommandPath)-cne $c.maintenanceScriptSha256){throw 'session_close_source_changed'}
 . $helper
 Initialize-ProcessImageBindingNative
 $ps=Join-Path ([ProcessImageBindingNative]::WindowsDirectory()) 'System32\WindowsPowerShell\v1.0\powershell.exe'
 if($c.host.imagePath-ine $ps-or $c.host.ownerSid-cne [Security.Principal.WindowsIdentity]::GetCurrent().User.Value){throw 'session_close_owner_binding'}
 $imageLease=Assert-ProcessImageFile $c.host.imagePath $c.host.imageSha256
 # Only fully hashed, ACL-checked and pinned candidate bytes may execute.
 & $ps -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $lifecycle 'start_schema6.ps1') -ManifestSha256 $c.manifestSha256 | Out-Null
 if($LASTEXITCODE-ne 0){throw 'session_close_release_rejected'}
 . (Join-Path $lifecycle 'protected_paths.ps1')
 Assert-ProtectedPath ([IO.Path]::GetDirectoryName($ConfigurationPath)) -Root
 $pinned=Read-Pinned $ConfigurationPath $ConfigurationSha256
 if(($pinned|ConvertTo-Json -Depth 12)-cne ($c|ConvertTo-Json -Depth 12)){throw 'session_close_input_changed'}
 $helper=Join-Path $PSScriptRoot 'process_image_binding.ps1'
 Assert-ProtectedPath $helper
 if((Hash-File $helper)-cne $c.processImageBindingSha256-or (Hash-File $PSCommandPath)-cne $c.maintenanceScriptSha256){throw 'session_close_source_changed'}
 . $helper
 $login=Read-Pinned $c.loginConfigurationPath $c.loginConfigurationSha256
 if($login.format-cne 'schema6-login-v1'-or $login.release_directory-cne $release-or $login.manifest_sha256-cne $c.manifestSha256-or $login.owner_sid-cne $c.host.ownerSid){throw 'session_close_login_binding'}
 Assert-ProtectedPath $c.sessionDirectory -Root
 Assert-ProtectedPath $c.controlDirectory -Root
 if([IO.Path]::GetDirectoryName($c.sessionDirectory)-cne $login.control_root-or [IO.Path]::GetDirectoryName($c.controlDirectory)-cne $c.sessionDirectory){throw 'session_close_directory_binding'}
 $window=Read-Pinned (Join-Path $c.sessionDirectory 'session-window.json') $c.windowSha256
 $launch=Read-Pinned (Join-Path $c.controlDirectory 'launch.json') $c.launchSha256
 $ready=Read-Pinned (Join-Path $c.controlDirectory 'ready.json') $c.readySha256
 if($window.hook_ready-ne $true-or $window.manifest_sha256-cne $c.manifestSha256-or [int]$window.pid-ne [int]$c.host.pid-or [long]$window.hwnd-ne [long]$c.host.hwnd){throw 'session_close_window_binding'}
 if($launch.token-cne $ready.token-or $launch.manifest_sha256-cne $c.manifestSha256-or $ready.manifest_sha256-cne $c.manifestSha256-or $launch.release-cne $release-or $launch.state-cne $login.state_directory-or $launch.configuration_file-cne $login.core_configuration_path-or $ready.configuration_sha256-cne $login.core_configuration_sha256){throw 'session_close_core_binding'}
 if($c.host.imagePath-ine $ps-or $c.host.ownerSid-cne [Security.Principal.WindowsIdentity]::GetCurrent().User.Value){throw 'session_close_owner_binding'}

 Add-Type -TypeDefinition @"
using System;
using System.Text;
using System.Runtime.InteropServices;
using System.Security.Principal;
public sealed class ApprovedSessionCloseLease:IDisposable {
 IntPtr process;
 [DllImport("kernel32.dll",SetLastError=true)]static extern IntPtr OpenProcess(uint access,bool inherit,int id);
 [DllImport("kernel32.dll")]static extern bool CloseHandle(IntPtr h);
 [DllImport("kernel32.dll")]static extern bool GetProcessTimes(IntPtr h,out long created,out long exit,out long kernel,out long user);
 [DllImport("kernel32.dll",CharSet=CharSet.Unicode)]static extern bool QueryFullProcessImageName(IntPtr h,uint flags,StringBuilder value,ref uint size);
 [DllImport("kernel32.dll")]static extern uint GetProcessId(IntPtr h);
 [DllImport("kernel32.dll")]static extern uint WaitForSingleObject(IntPtr h,uint timeout);
 [DllImport("kernel32.dll")]static extern bool GetExitCodeProcess(IntPtr h,out uint code);
 [DllImport("kernel32.dll")]static extern bool ProcessIdToSessionId(uint pid,out uint sid);
 [DllImport("advapi32.dll",SetLastError=true)]static extern bool OpenProcessToken(IntPtr process,uint access,out IntPtr token);
 [DllImport("user32.dll")]static extern uint GetWindowThreadProcessId(IntPtr hwnd,out uint pid);
 [DllImport("user32.dll")]static extern bool IsWindowVisible(IntPtr hwnd);
 [DllImport("user32.dll")]static extern IntPtr GetAncestor(IntPtr hwnd,uint flags);
 [DllImport("user32.dll",SetLastError=true)]static extern IntPtr SendMessageTimeout(IntPtr hwnd,uint message,IntPtr wp,IntPtr lp,uint flags,uint timeout,out IntPtr result);
 public ApprovedSessionCloseLease(int pid){process=OpenProcess(0x00101000,false,pid);if(process==IntPtr.Zero)throw new InvalidOperationException("session_close_process_unavailable");}
 public void Validate(int pid,long ticks,string image,string owner,uint session,long window,uint thread){
  if(WaitForSingleObject(process,0)!=258||GetProcessId(process)!=(uint)pid)throw new InvalidOperationException("session_close_process_changed");
  long c,e,k,u;uint size=32768,sid;var name=new StringBuilder(32768);
  if(!GetProcessTimes(process,out c,out e,out k,out u)||DateTime.FromFileTimeUtc(c).Ticks!=ticks||!QueryFullProcessImageName(process,0,name,ref size)||!String.Equals(name.ToString(),image,StringComparison.OrdinalIgnoreCase)||!ProcessIdToSessionId((uint)pid,out sid)||sid!=session)throw new InvalidOperationException("session_close_process_changed");
  IntPtr token;if(!OpenProcessToken(process,8,out token))throw new InvalidOperationException("session_close_owner_unavailable");
  try{using(var identity=new WindowsIdentity(token)){if(identity.User.Value!=owner)throw new InvalidOperationException("session_close_owner_binding");}}finally{CloseHandle(token);}
  uint actual;IntPtr hwnd=new IntPtr(window);if(GetWindowThreadProcessId(hwnd,out actual)!=thread||actual!=(uint)pid||GetAncestor(hwnd,2)!=hwnd||IsWindowVisible(hwnd))throw new InvalidOperationException("session_close_window_changed");
 }
 public void CloseWindow(int pid,long window,uint thread){
  uint actual;IntPtr hwnd=new IntPtr(window);if(GetWindowThreadProcessId(hwnd,out actual)!=thread||actual!=(uint)pid||WaitForSingleObject(process,0)!=258)throw new InvalidOperationException("session_close_window_changed");
  IntPtr result;if(SendMessageTimeout(hwnd,0x0010,IntPtr.Zero,IntPtr.Zero,2,5000,out result)==IntPtr.Zero)throw new InvalidOperationException("session_close_message_timeout");
 }
 public bool WaitClosed(uint timeout){uint exit;return WaitForSingleObject(process,timeout)==0&&GetExitCodeProcess(process,out exit)&&exit==0;}
 public void Dispose(){if(process!=IntPtr.Zero){CloseHandle(process);process=IntPtr.Zero;}}
}
"@
 $hostLease=[ApprovedSessionCloseLease]::new([int]$c.host.pid)
 $hostLease.Validate([int]$c.host.pid,[long]$c.host.startedTicks,[string]$c.host.imagePath,[string]$c.host.ownerSid,[uint32]$c.host.sessionId,[long]$c.host.hwnd,[uint32]$c.host.threadId)
 # For old packages the OS evidence above supplies the absent session/TID metadata.
 if(($window.PSObject.Properties.Name-contains 'session_id')-and [uint32]$window.session_id-ne [uint32]$c.host.sessionId){throw 'session_close_session_changed'}
 if(($window.PSObject.Properties.Name-contains 'thread_id')-and [uint32]$window.thread_id-ne [uint32]$c.host.threadId){throw 'session_close_thread_changed'}
 if(Test-Path -LiteralPath $c.outputPath){throw 'session_close_output_exists'}
 Assert-ProtectedPath ([IO.Path]::GetDirectoryName($c.outputPath)) -Root
 if($c.outputPath.StartsWith($login.state_directory+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'session_close_output_inside_state'}
 $closeWatch=[Diagnostics.Stopwatch]::StartNew()
 $hostLease.CloseWindow([int]$c.host.pid,[long]$c.host.hwnd,[uint32]$c.host.threadId)
 $remaining=30000-$closeWatch.ElapsedMilliseconds
 if($remaining-le 0-or -not $hostLease.WaitClosed([uint32]$remaining)-or $closeWatch.ElapsedMilliseconds-ge 30000){throw 'session_close_exit_unconfirmed'}
 $externalCloseElapsed=$closeWatch.ElapsedMilliseconds
 if(Test-Path -LiteralPath (Join-Path $c.sessionDirectory 'session-exit-over-budget.json')){throw 'session_close_budget_unconfirmed'}
 $paths=@{
  child=(Join-Path $c.controlDirectory 'child.json');guardian=(Join-Path $c.controlDirectory 'guardian.json')
  supervisor=(Join-Path $c.controlDirectory 'supervisor.json');close=(Join-Path $c.controlDirectory 'session-close.json')
  exit=(Join-Path $c.sessionDirectory 'session-exit.json');marker=(Join-Path $login.state_directory 's6-lifecycle.json')
 }
 $r=@{};$hashes=@{}
 foreach($name in $paths.Keys){Assert-ProtectedPath $paths[$name];$hashes[$name]=Hash-File $paths[$name];$r[$name]=Read-Pinned $paths[$name] $hashes[$name]}
 foreach($name in @('child','supervisor','marker')){if($r[$name].token-cne $launch.token-or $r[$name].manifest_sha256-cne $c.manifestSha256){throw 'session_close_receipt_binding'}}
 if($r.child.phase-cne 'clean_closed'-or $r.child.store_close_confirmed-ne $true-or $r.child.listener_closed_confirmed-ne $true-or $r.marker.phase-cne 'clean_closed'-or $r.marker.configuration_sha256-cne $login.core_configuration_sha256){throw 'session_close_core_unconfirmed'}
 $s=$r.supervisor;$g=$r.guardian
 foreach($key in @('child_receipt_confirmed','guardian_receipt_confirmed','lock_released_confirmed')){if($s.$key-ne $true){throw 'session_close_supervisor_unconfirmed'}}
 foreach($key in @('job_empty_confirmed','child_exit_confirmed','child_exit_code_confirmed','guardian_exit_confirmed','guardian_exit_code_confirmed')){if($s.result.$key-ne $true){throw 'session_close_supervisor_unconfirmed'}}
 if($s.result.child_exit_code-ne 0-or $s.result.guardian_exit_code-ne 0-or $s.result.termination_requested-ne $false-or $g.run_id-cne $launch.token-or $g.result.job_empty_confirmed-ne $true-or $g.result.parent_exit_observed-ne $false){throw 'session_close_supervisor_unconfirmed'}
 if($r.close.manifest_sha256-cne $c.manifestSha256-or $r.close.clean_closed-ne $true-or $r.close.completion_confirmed-ne $true-or $r.close.core_forced-ne $false-or $r.close.database_exclusive_open_confirmed-ne $true){throw 'session_close_window_unconfirmed'}
 foreach($key in @('clean_closed','core_job_empty_confirmed','backup_job_empty_confirmed','mcp_job_empty_confirmed','mcp_owned_tree_handles_released_confirmed')){if($r.exit.$key-ne $true){throw 'session_close_exit_unconfirmed'}}
 $legacyExitManifestAbsent=$legacyPackage-and -not ($r.exit.PSObject.Properties.Name-contains 'manifest_sha256')
 if((-not $legacyExitManifestAbsent-and $r.exit.manifest_sha256-cne $c.manifestSha256)-or $r.close.budget_ms-ne 30000-or $r.exit.budget_ms-ne 30000-or $r.close.elapsed_ms-lt 0-or $r.close.elapsed_ms-ge 30000-or $r.exit.elapsed_ms-lt 0-or $r.exit.elapsed_ms-ge 30000){throw 'session_close_budget_unconfirmed'}
 if($r.exit.forced_timeout-ne $false-or $r.exit.termination_requested-ne $false-or $r.exit.mcp_failure-ne $false){throw 'session_close_exit_unconfirmed'}
 if($login.mcp_configuration_path){
  $startPath=Join-Path $c.controlDirectory 'mcp-start.json';$stopPath=Join-Path $c.controlDirectory 'mcp-stop.json'
  $start=Read-Pinned $startPath (Hash-File $startPath);$stop=Read-Pinned $stopPath (Hash-File $stopPath)
  if($start.core_token-cne $launch.token-or $start.manifest_sha256-cne $c.manifestSha256-or $start.pid-ne $stop.pid-or $start.started_ticks-cne $stop.started_ticks-or $stop.scope-cne 'owned_mcp_job_only'-or $stop.mcp_failure-ne $false){throw 'session_close_mcp_binding'}
  foreach($key in @('job_empty_confirmed','process_exit_confirmed','owned_tree_handles_released_confirmed')){if($stop.$key-ne $true){throw 'session_close_mcp_unconfirmed'}}
  $hashes.mcpStop=Hash-File $stopPath
 }
 $database=Join-Path $login.state_directory 'i-core.sqlite';Assert-ProtectedPath $database
 foreach($suffix in @('-wal','-shm','-journal')){if(Test-Path -LiteralPath ($database+$suffix)){throw 'session_close_sidecars_present'}}
 $dbLease=[IO.File]::Open($database,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::None)
 $digest=[Security.Cryptography.SHA256]::Create()
 try{$actualHash=([BitConverter]::ToString($digest.ComputeHash($dbLease))).Replace('-','').ToLowerInvariant();if($actualHash-cne $r.marker.database_sha256){throw 'session_close_database_changed'}}finally{$digest.Dispose();$dbLease.Dispose()}
 $report=@{format='schema6-approved-session-close-v1';closed=$true;manifestSha256=$c.manifestSha256;configurationSha256=$ConfigurationSha256;originalHostExitConfirmed=$true;externalCloseElapsedMs=$externalCloseElapsed;budgetMs=30000;legacyExitManifestAbsent=$legacyExitManifestAbsent;wmCloseOnly=$true;coreForced=$false;databaseExclusiveOpenConfirmed=$true;receiptSha256=$hashes;custodyAuthenticated=$false;offlineSwitchMustVerifyCustody=$true}
 $bytes=[Text.UTF8Encoding]::new($false).GetBytes(($report|ConvertTo-Json -Depth 6))
 $out=[IO.File]::Open($c.outputPath,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
 try{$out.Write($bytes,0,$bytes.Length);$out.Flush($true)}finally{$out.Dispose()}
 $report|ConvertTo-Json -Depth 6 -Compress
}catch{[Console]::Error.WriteLine('approved_session_close_rejected');exit 2}
finally{if($hostLease){$hostLease.Dispose()};if($imageLease){$imageLease.lease.Dispose()};foreach($h in $handles){$h.Dispose()}}
