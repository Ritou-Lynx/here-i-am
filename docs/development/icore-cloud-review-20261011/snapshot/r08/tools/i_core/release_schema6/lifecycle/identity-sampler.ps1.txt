#requires -Version 5.1
# Dormant same-process sampler. Never Stop(), Thread.Abort(), Stop-Process or task control.
# Real lease Retain/Release and shared registry are mandatory; no fallback fake lease.
function New-ReviewedIdentitySampler {
 [CmdletBinding()]param(
  [Parameter(Mandatory=$true)]$Lease,$OriginalRunInstance,$AttachedInstance,[switch]$PermitRecheck,
  [string]$EvidenceNativeRoleId='evidence_native',
  [string]$EvidenceLauncherRoleId='evidence_launcher',
  [string]$IdentityLibraryRoleId='identity_library')
 $ErrorActionPreference='Stop'
 if($null-eq$Lease -or !$Lease.PSObject.Methods['Retain'] -or !$Lease.PSObject.Methods['Release']){throw 'identity_sampler_retention_required'}
 if($null-ne$OriginalRunInstance-and$null-ne$AttachedInstance){throw 'identity_sampler_instance_ambiguous'}
 if($PermitRecheck-and$null-ne$OriginalRunInstance){throw 'identity_sampler_recheck_original_conflict'}
 if($Lease.Mode-cnotin@('reviewed-live','offline-synthetic')){throw 'identity_sampler_mode'}
 if($Lease.Mode-ceq'reviewed-live'){
  foreach($instance in @($OriginalRunInstance,$AttachedInstance)){
   if($null-ne$instance-and![Runtime.InteropServices.Marshal]::IsComObject($instance)){throw 'identity_sampler_original_com_required'}
  }
 }
 $record=Get-P4LeaseRecord $Lease
 $held=$false;$runspace=$null;$ps=$null
 try{
  $null=$Lease.Retain();$held=$true
  $utf8=[Text.UTF8Encoding]::new($false,$true)
  $native=$utf8.GetString($Lease.Bytes($EvidenceNativeRoleId))
  $launcher=$utf8.GetString($Lease.Bytes($EvidenceLauncherRoleId))
  $library=$utf8.GetString($Lease.Bytes($IdentityLibraryRoleId))
  $sourceHashes=[ordered]@{native=$Lease.Hash($EvidenceNativeRoleId);launcher=$Lease.Hash($EvidenceLauncherRoleId);identity=$Lease.Hash($IdentityLibraryRoleId)}
  $runspace=[RunspaceFactory]::CreateRunspace()
  $runspace.ApartmentState=[Threading.ApartmentState]::MTA
  $runspace.ThreadOptions=[System.Management.Automation.Runspaces.PSThreadOptions]::ReuseThread
  $runspace.Open()
  # Same object references, not remoting/job serialization or reconstructed expected.
  $runspace.SessionStateProxy.SetVariable('SamplerLease',$Lease)
  $runspace.SessionStateProxy.SetVariable('SamplerOriginal',$OriginalRunInstance)
  $runspace.SessionStateProxy.SetVariable('SamplerAttached',$AttachedInstance)
  $runspace.SessionStateProxy.SetVariable('SamplerRecord',$record)
  $runspace.SessionStateProxy.SetVariable('SamplerPermitRecheck',[bool]$PermitRecheck)
  $ps=[PowerShell]::Create();$ps.Runspace=$runspace
  $warm=@'
param($Native,$Launcher,$Library)
$ErrorActionPreference='Stop'
. ([scriptblock]::Create($Native))
Initialize-P4EvidenceNative
. ([scriptblock]::Create($Launcher))
. ([scriptblock]::Create($Library))
$actual=Get-P4LeaseRecord $SamplerLease
if(![object]::ReferenceEquals($actual,$SamplerRecord)-or![object]::ReferenceEquals($actual.Object,$SamplerLease)){throw 'identity_sampler_shared_registry'}
Initialize-ReviewedIdentity -Lease $SamplerLease
[pscustomobject]@{workerThreadId=[Threading.Thread]::CurrentThread.ManagedThreadId;sharedRegistry=$true}
'@
  $null=$ps.AddScript($warm,$false).AddArgument($native).AddArgument($launcher).AddArgument($library)
  # Compilation and own-token prewarm are intentionally outside the 2500ms sample clock.
  $warmResult=@($ps.Invoke())
  if($ps.HadErrors-or$warmResult.Count-ne1-or!$warmResult[0].sharedRegistry){throw 'identity_sampler_prewarm'}
  $threadId=[int]$warmResult[0].workerThreadId
  $ps.Commands.Clear();$ps.Streams.Error.Clear()
  return [pscustomobject]@{format='i-core-identity-sampler-v1';Mode=$Lease.Mode;Lease=$Lease;Record=$record;Runspace=$runspace;PowerShell=$ps;Async=$null;State='ready';Fused=$false;Held=$true;Disposed=$false;WorkerThreadId=$threadId;SampleCount=0;LastElapsedMs=0;LastCode=$null;SourceHashes=$sourceHashes;BeginTicks=$null;PermitRecheck=[bool]$PermitRecheck}
 }catch{
  if($ps){$ps.Dispose()};if($runspace){$runspace.Dispose()};if($held){$null=$Lease.Release()}
  throw 'identity_sampler_initialize_failed'
 }
}
function Get-ReviewedIdentitySamplerState {
 param([Parameter(Mandatory=$true)]$Sampler)
 if($Sampler.format-cne'i-core-identity-sampler-v1'){throw 'identity_sampler_invalid'}
 $running=$null-ne$Sampler.Async-and!$Sampler.Async.IsCompleted
 return [ordered]@{format='i-core-identity-sampler-state-v1';state=$Sampler.State;fused=[bool]$Sampler.Fused;running=[bool]$running;retained=[bool]$Sampler.Held;disposed=[bool]$Sampler.Disposed;workerThreadId=$Sampler.WorkerThreadId;sampleCount=$Sampler.SampleCount;lastElapsedMs=$Sampler.LastElapsedMs;lastCode=$Sampler.LastCode;permitRecheck=[bool]$Sampler.PermitRecheck}
}
function Invoke-ReviewedIdentitySampler {
 [CmdletBinding()]param([Parameter(Mandatory=$true)]$Sampler)
 $ErrorActionPreference='Stop'
 if($Sampler.format-cne'i-core-identity-sampler-v1'-or$Sampler.Disposed-or$Sampler.Fused-or$Sampler.State-cne'ready'){throw 'identity_sampler_fused_or_busy'}
 $ps=$Sampler.PowerShell
 $script=@'
$ErrorActionPreference='Stop'
$frame=Get-FreshIdentityFrame -Lease $SamplerLease -OriginalRunInstance $SamplerOriginal -AttachedInstance $SamplerAttached -PermitRecheck:$SamplerPermitRecheck
[pscustomobject]@{frame=$frame;workerThreadId=[Threading.Thread]::CurrentThread.ManagedThreadId}
'@
 $ps.Commands.Clear();$ps.Streams.Error.Clear();$null=$ps.AddScript($script,$false)
 $Sampler.State='running';$Sampler.SampleCount++;$watch=[Diagnostics.Stopwatch]::StartNew()
 try{
  $Sampler.Async=$ps.BeginInvoke();$remaining=[Math]::Max(0,2500-$watch.ElapsedMilliseconds)
  $completed=$Sampler.Async.AsyncWaitHandle.WaitOne([int]$remaining)
  if(!$completed-or$watch.Elapsed.TotalMilliseconds-ge2500){
   $Sampler.State='timed_out_retained';$Sampler.Fused=$true;$Sampler.LastCode='identity_snapshot_timeout';$Sampler.LastElapsedMs=[Math]::Ceiling($watch.Elapsed.TotalMilliseconds)
   return [ordered]@{ok=$false;code='identity_snapshot_timeout';elapsedMs=$Sampler.LastElapsedMs;frame=$null;retained=$true;fused=$true;workerThreadId=$Sampler.WorkerThreadId}
  }
  $items=@($ps.EndInvoke($Sampler.Async));$Sampler.Async=$null
  $Sampler.LastElapsedMs=[Math]::Ceiling($watch.Elapsed.TotalMilliseconds)
  if($Sampler.LastElapsedMs-ge2500){throw 'identity_snapshot_timeout'}
  if($ps.HadErrors-or$items.Count-ne1-or$null-eq$items[0].frame-or$items[0].workerThreadId-ne$Sampler.WorkerThreadId){throw 'identity_snapshot_failed'}
  $Sampler.State='ready';$Sampler.LastCode=$null
  return [ordered]@{ok=$true;code=$null;elapsedMs=$Sampler.LastElapsedMs;frame=$items[0].frame;retained=$false;leaseHeld=$true;fused=$false;workerThreadId=$Sampler.WorkerThreadId}
 }catch{
  $Sampler.Fused=$true;$Sampler.State='failed_retained';$Sampler.LastElapsedMs=[Math]::Ceiling($watch.Elapsed.TotalMilliseconds)
  $Sampler.LastCode=if($watch.Elapsed.TotalMilliseconds-ge2500){'identity_snapshot_timeout'}else{'identity_snapshot_failed'}
  return [ordered]@{ok=$false;code=$Sampler.LastCode;elapsedMs=$Sampler.LastElapsedMs;frame=$null;retained=$true;fused=$true;workerThreadId=$Sampler.WorkerThreadId}
 }
}
function Complete-ReviewedIdentitySampler {
 [CmdletBinding()]param([Parameter(Mandatory=$true)]$Sampler)
 $ErrorActionPreference='Stop'
 if($Sampler.format-cne'i-core-identity-sampler-v1'){throw 'identity_sampler_invalid'}
 if($Sampler.Disposed){return Get-ReviewedIdentitySamplerState $Sampler}
 # An outstanding COM/CIM call is not stopped, aborted or disposed underneath.
 if($null-ne$Sampler.Async-and!$Sampler.Async.IsCompleted){return Get-ReviewedIdentitySamplerState $Sampler}
 if($null-ne$Sampler.Async){try{$null=$Sampler.PowerShell.EndInvoke($Sampler.Async)}catch{};$Sampler.Async=$null}
 $Sampler.PowerShell.Dispose();$Sampler.Runspace.Dispose()
 if($Sampler.Held){$null=$Sampler.Lease.Release();$Sampler.Held=$false}
 $Sampler.Disposed=$true;$Sampler.State='disposed'
 return Get-ReviewedIdentitySamplerState $Sampler
}
