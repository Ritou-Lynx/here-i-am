[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$SessionWindowScript,[Parameter(Mandatory=$true)][string]$Directory,[Parameter(Mandatory=$true)][ValidateSet('query','end','cancel','repeated','entry-failure','entry-failure-cancel-retry','exit-failure','timeout','final-publication-over-budget','late-close-publication','late-worker-no-core')][string]$Scenario)
$ErrorActionPreference='Stop'
# No application message loop: timer Tick and queued OnFormClosed never run.
if($Scenario -eq 'final-publication-over-budget'){
 # Test-only fault injection delays the real final publication. Production
 # configuration, timing constants and filesystem code remain untouched.
 $sourceText=[IO.File]::ReadAllText($SessionWindowScript)
 $needle='file.Flush(true);}File.Move(pending,filename);'
 if(($sourceText.Split(@($needle),[StringSplitOptions]::None)).Length -ne 2){throw 'synthetic_final_publication_injection_not_unique'}
 $sourceText=$sourceText.Replace($needle,'file.Flush(true);}if(Path.GetFileName(filename)=="session-exit.json")Thread.Sleep(250);File.Move(pending,filename);')
 . ([ScriptBlock]::Create($sourceText))
 }elseif($Scenario -in @('late-close-publication','late-worker-no-core')){
 # Gates exist only in this fixture's compiled source, never the production file.
 $sourceText=[IO.File]::ReadAllText($SessionWindowScript)
 $typeAnchor='public sealed class Schema6SessionWindow : Form {'
 $gateFields='
  public static readonly ManualResetEvent SyntheticWorkerReached=new ManualResetEvent(false);
  public static readonly ManualResetEvent SyntheticWorkerRelease=new ManualResetEvent(false);
  public static int SyntheticWorkerThread;
  static void SyntheticPauseWorker() {
    SyntheticWorkerThread=Thread.CurrentThread.ManagedThreadId;
    SyntheticWorkerReached.Set();
    if(!SyntheticWorkerRelease.WaitOne(15000))throw new InvalidOperationException("synthetic_worker_gate_timeout");
  }
'
 if(($sourceText.Split(@($typeAnchor),[StringSplitOptions]::None)).Length -ne 2){throw 'synthetic_worker_type_anchor_not_unique'}
 $sourceText=$sourceText.Replace($typeAnchor,$typeAnchor+[Environment]::NewLine+$gateFields)
 if($Scenario -eq 'late-worker-no-core'){
  $gateAnchor='ClosePhase("close_worker_entered");'
  $replacement=$gateAnchor+'SyntheticPauseWorker();'
 }else{
  $gateAnchor='// Flush is outside the publication gate'
  $replacement='SyntheticPauseWorker();'+[Environment]::NewLine+'      '+$gateAnchor
 }
 if(($sourceText.Split(@($gateAnchor),[StringSplitOptions]::None)).Length -ne 2){throw 'synthetic_worker_gate_anchor_not_unique'}
 $sourceText=$sourceText.Replace($gateAnchor,$replacement)
 . ([ScriptBlock]::Create($sourceText))
}else{. $SessionWindowScript}
Add-Type -ReferencedAssemblies System.Windows.Forms,System.Web.Extensions -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Text;
using System.Threading;
using System.Web.Script.Serialization;
using System.Windows.Forms;
public static class SyntheticShutdownReceiptProbe {
 static readonly BindingFlags Hidden=BindingFlags.Instance|BindingFlags.NonPublic;
 static readonly JavaScriptSerializer Json=new JavaScriptSerializer();
 static void Set(object window,string name,object value) {window.GetType().GetField(name,Hidden).SetValue(window,value);}
 static object Get(object window,string name) {return window.GetType().GetField(name,Hidden).GetValue(window);}
 static void AdvanceRunningBudget(Stopwatch budget) {
  // Advance the real, still-running watch only after the worker reaches its gate.
  var field=typeof(Stopwatch).GetField("elapsed",Hidden)??typeof(Stopwatch).GetField("_elapsed",Hidden);
  if(field==null||!budget.IsRunning)throw new InvalidOperationException("synthetic_running_stopwatch_required");
  long remainingTicks=(29900-budget.ElapsedMilliseconds)*Stopwatch.Frequency/1000;
  if(remainingTicks<0)throw new InvalidOperationException("synthetic_gate_reached_too_late");
  field.SetValue(budget,(long)field.GetValue(budget)+remainingTicks);
  if(budget.ElapsedMilliseconds<29890||budget.ElapsedMilliseconds>30000)throw new InvalidOperationException("synthetic_stopwatch_advance_unconfirmed");
 }
 static int HostExitCode(object window) {return (int)window.GetType().GetMethod("HostExitCode",Hidden).Invoke(window,new object[0]);}
 static void Write(string filename,object value) {
  byte[] bytes=Encoding.UTF8.GetBytes(Json.Serialize(value));
  using(var file=new FileStream(filename,FileMode.CreateNew,FileAccess.Write,FileShare.None)){file.Write(bytes,0,bytes.Length);file.Flush(true);}
 }
 static Dictionary<string,object> Send(Form window,string session,string control,int number,int wparam) {
  object[] arguments={Message.Create(window.Handle,number,new IntPtr(wparam),new IntPtr(0x40000000))};
  Stopwatch timer=Stopwatch.StartNew();
  string error=null;
  try{window.GetType().GetMethod("WndProc",Hidden).Invoke(window,arguments);}catch(TargetInvocationException exception){error=exception.InnerException.GetType().Name;}
  // Capture on return before any pumping or cleanup can manufacture evidence.
  bool exitAtReturn=File.Exists(Path.Combine(session,"session-exit.json"));
  bool closeAtReturn=File.Exists(Path.Combine(control,"session-close.json"));
  var entries=new Dictionary<string,object>();
  if(Directory.Exists(session))foreach(string file in Directory.GetFiles(session,"session-message-*.json"))entries[Path.GetFileName(file)]=Json.DeserializeObject(File.ReadAllText(file));
  return new Dictionary<string,object>{{"message",number},{"wparam",wparam},{"result",((Message)arguments[0]).Result.ToInt64()},{"error",error},{"elapsed_ms",timer.ElapsedMilliseconds},{"exit_at_return",exitAtReturn},{"close_at_return",closeAtReturn},{"entries_at_return",entries}};
 }
 public static void Run(Type type,string root,string scenario,string powerShell) {
  string session=Path.Combine(root,"session"),control=Path.Combine(root,"control"),state=Path.Combine(root,"state");
  Directory.CreateDirectory(session);Directory.CreateDirectory(control);Directory.CreateDirectory(state);
  object[] args={powerShell,root,new string('a',64),state,control,session,Path.Combine(root,"unused-config.json"),false,new string[0],300,0,""};
  Form window=(Form)Activator.CreateInstance(type,args);
  // Only this fixture-owned hidden HWND exists; no OS shutdown is requested.
  IntPtr ownWindow=window.Handle;
  var calls=new List<Dictionary<string,object>>();
  object cancellationSnapshot=null;
  bool retryBudgetFresh=false;
  object lateWorkerProof=null;
  if(scenario=="entry-failure")Directory.Move(session,Path.Combine(root,"parked-session"));
  if(scenario=="exit-failure")Directory.CreateDirectory(Path.Combine(session,"session-exit.json"));
  if(scenario=="late-close-publication"||scenario=="late-worker-no-core") {
   var reached=(ManualResetEvent)type.GetField("SyntheticWorkerReached").GetValue(null);
   var releaseWorker=(ManualResetEvent)type.GetField("SyntheticWorkerRelease").GetValue(null);
   var finished=(ManualResetEvent)Get(window,"finished");
   try {
    calls.Add(Send(window,session,control,0x0011,0));
    if(!reached.WaitOne(10000))throw new InvalidOperationException("synthetic_real_worker_did_not_reach_gate");
    bool pendingBefore=Directory.GetFiles(control,"session-close.json.*.pending").Length==1;
    AdvanceRunningBudget((Stopwatch)Get(window,"closeBudget"));
    calls.Add(Send(window,session,control,0x0016,1));
    bool finishedBefore=finished.WaitOne(0),cleanBefore=(bool)Get(window,"clean");
    int hostBefore=HostExitCode(window);
    string exitBefore=File.ReadAllText(Path.Combine(session,"session-exit.json"));
    releaseWorker.Set();
    if(!finished.WaitOne(10000))throw new InvalidOperationException("synthetic_real_worker_did_not_finish_after_release");
    string close=Path.Combine(control,"session-close.json");
    lateWorkerProof=new Dictionary<string,object>{
      {"real_worker_thread",type.GetField("SyntheticWorkerThread").GetValue(null)},
      {"handler_thread",Thread.CurrentThread.ManagedThreadId},
      {"core_absent",Get(window,"core")==null},{"pending_close_before_timeout",pendingBefore},
      {"finished_before_release",finishedBefore},{"clean_at_handler_return",cleanBefore},
      {"host_exit_code_at_handler_return",hostBefore},{"finished_after_release",finished.WaitOne(0)},
      {"clean_after_release",Get(window,"clean")},{"host_exit_code_after_release",HostExitCode(window)},
      {"exit_unchanged_after_release",exitBefore==File.ReadAllText(Path.Combine(session,"session-exit.json"))},
      {"close_after_release",File.Exists(close)?Json.DeserializeObject(File.ReadAllText(close)):null},
      {"pending_close_after_release",Directory.GetFiles(control,"session-close.json.*.pending").Length}
    };
   }finally{releaseWorker.Set();}
  }
  else if(scenario=="entry-failure-cancel-retry") {
   Directory.Move(session,Path.Combine(root,"parked-session"));
   calls.Add(Send(window,session,control,0x0011,0));
   object oldBudget=Get(window,"closeBudget");
   Directory.Move(Path.Combine(root,"parked-session"),session);
   calls.Add(Send(window,session,control,0x0016,0));
   cancellationSnapshot=new Dictionary<string,object>{{"budget_reset",Get(window,"closeBudget")==null},{"closing",Get(window,"closing")},{"shutdown_requested",Get(window,"shutdownRequested")},{"message_receipt_failed",Get(window,"messageReceiptFailed")}};
   calls.Add(Send(window,session,control,0x0011,0));
   retryBudgetFresh=Get(window,"closeBudget")!=null&&!Object.ReferenceEquals(oldBudget,Get(window,"closeBudget"));
   calls.Add(Send(window,session,control,0x0016,1));
  }
  else if(scenario=="final-publication-over-budget") {
   Set(window,"closing",1);Set(window,"clean",true);
   ((ManualResetEvent)Get(window,"finished")).Set();
   Set(window,"closeBudget",Stopwatch.StartNew());
   Thread.Sleep(29800);
   calls.Add(Send(window,session,control,0x0016,1));
  }
  else if(scenario=="timeout") {Set(window,"closing",1);Set(window,"closeBudget",Stopwatch.StartNew());calls.Add(Send(window,session,control,0x0011,0));calls.Add(Send(window,session,control,0x0016,1));}
  else if(scenario=="end"||scenario=="exit-failure")calls.Add(Send(window,session,control,0x0016,1));
  else {
   calls.Add(Send(window,session,control,0x0011,0));
   if(scenario=="cancel")calls.Add(Send(window,session,control,0x0016,0));
   if(scenario=="repeated") {calls.Add(Send(window,session,control,0x0011,0));calls.Add(Send(window,session,control,0x0016,1));calls.Add(Send(window,session,control,0x0016,1));}
  }
  var proof=new Dictionary<string,object>{{"scenario",scenario},{"late_worker",lateWorkerProof},{"cancellation_snapshot",cancellationSnapshot},{"retry_budget_fresh",retryBudgetFresh},{"budget_elapsed_at_return",Get(window,"closeBudget")==null?0:((Stopwatch)Get(window,"closeBudget")).ElapsedMilliseconds},{"calls",calls},{"on_form_closed_invoked",false},{"application_message_loop_started",false},{"reason_at_return",Get(window,"reason")},{"clean_at_return",Get(window,"clean")},{"forced_timeout_at_return",Get(window,"forcedTimeout")},{"shutdown_cancelled_at_return",Get(window,"shutdownCancelled")}};
  Write(Path.Combine(root,"handler-return.json"),proof);
  // Bypass Form.Dispose, OnFormClosed, finalizers and orderly process exit.
  Process.GetCurrentProcess().Kill();
  Thread.Sleep(Timeout.Infinite);
 }
}
'@
[SyntheticShutdownReceiptProbe]::Run([Schema6SessionWindow],$Directory,$Scenario,(Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'))
