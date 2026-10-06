[CmdletBinding()]
param(
 [Parameter(Mandatory=$true)][string]$SessionWindowScript,
 [string]$Directory=[IO.Path]::GetTempPath()
)
$ErrorActionPreference='Stop'
# Test-side reflection only: no HWND, timer, Tick, Core, configuration, or service.
. $SessionWindowScript
Add-Type -TypeDefinition @'
using System;
using System.Diagnostics;
using System.Reflection;
using System.Threading;
public sealed class Schema6McpStopProbeThread {
 readonly Thread worker;
 Exception failure;
 public Schema6McpStopProbeThread(MethodInfo method,object target) {
  worker=new Thread(delegate(){try{method.Invoke(target,new object[]{Stopwatch.StartNew()});}catch(Exception error){failure=error;}});
  worker.IsBackground=true;
 }
 public void Start(){worker.Start();}
 public bool WaitingInsideStop { get {return (worker.ThreadState&System.Threading.ThreadState.WaitSleepJoin)!=0;} }
 public void Complete(int milliseconds){if(!worker.Join(milliseconds))throw new InvalidOperationException("synthetic_stop_thread_timeout");if(failure!=null)throw new InvalidOperationException("synthetic_stop_invocation_failed",failure);}
}
'@
$base=[IO.Path]::GetFullPath($Directory).TrimEnd('\')
if(-not [IO.Directory]::Exists($base)){throw 'synthetic_parent_missing'}
$root=Join-Path $base ('schema6-mcp-stop-probe-'+[Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($root)|Out-Null
$flags=[Reflection.BindingFlags]'NonPublic,Instance'
$type=[Schema6SessionWindow]
$stopMethod=$type.GetMethod('StopMcp',$flags)
if($null -eq $stopMethod){throw 'candidate_stop_method_missing'}
$ps=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$proof=@()
$jobs=@()
$complete=$false
try {
 foreach($case in @(
  @{name='already-failed';code=9;grace=100;mode='before';failure=$true;forced=$false},
  @{name='exit-during-grace';code=7;grace=3000;mode='during';failure=$true;forced=$false},
  @{name='natural-zero';code=0;grace=100;mode='before';failure=$true;forced=$false},
  @{name='forced-owned';code=0;grace=25;mode='force';failure=$false;forced=$true}
 )) {
  $control=Join-Path $root $case.name
  [IO.Directory]::CreateDirectory($control)|Out-Null
  $database=Join-Path $control 'synthetic.sqlite'
  $held=Join-Path $control 'held'
  $release=Join-Path $control 'release'
  $child=Join-Path $control 'child.ps1'
  [IO.File]::WriteAllText($database,'synthetic file-handle probe, not a live database')
  [IO.File]::WriteAllText($child,@'
param([string]$Database,[string]$Held,[string]$Release,[int]$ExitCode)
$ErrorActionPreference='Stop'
$stream=[IO.File]::Open($Database,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::None)
[IO.File]::WriteAllText($Held,[string]$PID)
try{while(-not [IO.File]::Exists($Release)){Start-Sleep -Milliseconds 10}}finally{$stream.Dispose()}
exit $ExitCode
'@)
  $job=[Schema6SessionJob]::new($ps,[string[]]@('-NoProfile','-NonInteractive','-File',$child,'-Database',$database,'-Held',$held,'-Release',$release,'-ExitCode',[string]$case.code),$control)
  $jobs+=$job
  $watch=[Diagnostics.Stopwatch]::StartNew()
  while(-not [IO.File]::Exists($held) -and -not $job.Exited -and $watch.ElapsedMilliseconds -lt 10000){Start-Sleep -Milliseconds 10}
  if(-not [IO.File]::Exists($held) -or $job.Exited){throw 'synthetic_holder_not_ready'}
  $busy=$false
  try{$probe=[IO.File]::Open($database,[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None);$probe.Dispose()}catch [IO.IOException]{$busy=$true}
  if(-not $busy){throw 'synthetic_file_handle_not_observed'}

  # No constructor is run: therefore no WinForms HWND, timer or Tick can exist.
  $window=[Runtime.Serialization.FormatterServices]::GetUninitializedObject($type)
  $config=New-Object 'Collections.Generic.Dictionary[string,object]'
  $config.Add('grace_ms',[int]$case.grace)
  $config.Add('database_path',$database)
  $type.GetField('mcp',$flags).SetValue($window,$job)
  $type.GetField('mcpConfiguration',$flags).SetValue($window,$config)
  $type.GetField('control',$flags).SetValue($window,$control)
  $insideGrace=$false
  if($case.mode -eq 'before') {
   [IO.File]::WriteAllText($release,'synthetic natural exit')
   if(-not $job.WaitEmpty(5000)){throw 'synthetic_natural_exit_timeout'}
   $null=$stopMethod.Invoke($window,@([Diagnostics.Stopwatch]::StartNew()))
  } elseif($case.mode -eq 'during') {
   # WaitSleepJoin is reached by the real WaitEmpty Thread.Sleep. The holder
   # remains alive until we publish release, so exit cannot precede StopMcp.
   $worker=[Schema6McpStopProbeThread]::new($stopMethod,$window)
   $worker.Start()
   $watch.Restart()
   while(-not $worker.WaitingInsideStop -and $watch.ElapsedMilliseconds -lt 2000){Start-Sleep -Milliseconds 1}
   if(-not $worker.WaitingInsideStop -or $job.Exited){throw 'synthetic_grace_not_observed'}
   $insideGrace=$true
   [IO.File]::WriteAllText($release,'synthetic exit during actual grace')
   $worker.Complete(5000)
  } else {
   $null=$stopMethod.Invoke($window,@([Diagnostics.Stopwatch]::StartNew()))
  }
  $receipt=[IO.File]::ReadAllText((Join-Path $control 'mcp-stop.json'))|ConvertFrom-Json
  $expectedCode=if($case.forced){124}else{$case.code}
  if($receipt.mcp_failure -ne $case.failure -or $receipt.forced -ne $case.forced -or $receipt.mcp_exit_code -ne $expectedCode -or $receipt.natural_exit_observed -ne $case.failure){throw ('synthetic_exit_evidence_rejected_'+$case.name)}
  if(-not $job.Exited -or -not $job.Empty -or -not $receipt.job_empty_confirmed -or -not $receipt.process_exit_confirmed -or -not $receipt.owned_tree_handles_released_confirmed){throw 'synthetic_job_empty_unconfirmed'}
  if(-not $case.forced -and $receipt.stop_method -ne 'natural_exit_without_stop_signal'){throw 'synthetic_natural_exit_misreported'}
  if($receipt.application_graceful_exit_confirmed){throw 'synthetic_graceful_claim_rejected'}
  $probe=[IO.File]::Open($database,[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
  $probe.Dispose()
  $proof+=@{name=$case.name;exit_code=$receipt.mcp_exit_code;mcp_failure=$receipt.mcp_failure;forced=$receipt.forced;job_empty_confirmed=$job.Empty;process_exit_confirmed=$job.Exited;file_handle_observed=$busy;exclusive_reopen_confirmed=$true;natural_exit_observed=$receipt.natural_exit_observed;stop_method=$receipt.stop_method;exit_triggered_inside_grace=$insideGrace}
 }
 $complete=$true
} finally {
 $allEmpty=$true
 foreach($job in $jobs) {
  try{if(-not ($job.Exited -and $job.Empty) -and -not $job.TerminateAndWait(2000)){$allEmpty=$false}}finally{$job.Dispose()}
 }
 # Delete only this generated child root after all owned Jobs are confirmed empty.
 if($complete -and $allEmpty) {
  $resolved=[IO.Path]::GetFullPath($root)
  if([IO.Path]::GetDirectoryName($resolved) -ne $base -or -not [IO.Path]::GetFileName($resolved).StartsWith('schema6-mcp-stop-probe-')){throw 'synthetic_cleanup_path_rejected'}
  foreach($item in Get-ChildItem -LiteralPath $resolved -Force -Recurse){if(($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw 'synthetic_cleanup_link_rejected'}}
  if(([IO.File]::GetAttributes($resolved) -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw 'synthetic_cleanup_link_rejected'}
  Remove-Item -LiteralPath $resolved -Recurse -Force
 }
}
@{cases=$proof;no_tick_invoked=$true;synthetic_root_cleaned=(-not [IO.Directory]::Exists($root))}|ConvertTo-Json -Depth 6 -Compress
