[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$SessionWindowScript,[Parameter(Mandatory=$true)][string]$Directory,[Parameter(Mandatory=$true)][ValidateSet('query','end','cancel','repeated','entry-failure','entry-failure-cancel-retry','exit-failure','timeout','final-publication-over-budget')][string]$Scenario)
$ErrorActionPreference='Stop'
# No application message loop: timer Tick and queued OnFormClosed never run.
if($Scenario -eq 'final-publication-over-budget'){
 # Test-only fault injection delays the real final publication. Production
 # configuration, timing constants and filesystem code remain untouched.
 $sourceText=[IO.File]::ReadAllText($SessionWindowScript)
 $needle='File.Move(pending,filename);'
 if(($sourceText.Split(@($needle),[StringSplitOptions]::None)).Length -ne 2){throw 'synthetic_final_publication_injection_not_unique'}
 $sourceText=$sourceText.Replace($needle,'if(Path.GetFileName(filename)=="session-exit.json")Thread.Sleep(250);'+$needle)
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
  if(scenario=="entry-failure")Directory.Move(session,Path.Combine(root,"parked-session"));
  if(scenario=="exit-failure")Directory.CreateDirectory(Path.Combine(session,"session-exit.json"));
  if(scenario=="entry-failure-cancel-retry") {
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
  var proof=new Dictionary<string,object>{{"scenario",scenario},{"cancellation_snapshot",cancellationSnapshot},{"retry_budget_fresh",retryBudgetFresh},{"budget_elapsed_at_return",Get(window,"closeBudget")==null?0:((Stopwatch)Get(window,"closeBudget")).ElapsedMilliseconds},{"calls",calls},{"on_form_closed_invoked",false},{"application_message_loop_started",false},{"reason_at_return",Get(window,"reason")},{"clean_at_return",Get(window,"clean")},{"forced_timeout_at_return",Get(window,"forcedTimeout")},{"shutdown_cancelled_at_return",Get(window,"shutdownCancelled")}};
  Write(Path.Combine(root,"handler-return.json"),proof);
  // Bypass Form.Dispose, OnFormClosed, finalizers and orderly process exit.
  Process.GetCurrentProcess().Kill();
  Thread.Sleep(Timeout.Infinite);
 }
}
'@
[SyntheticShutdownReceiptProbe]::Run([Schema6SessionWindow],$Directory,$Scenario,(Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'))
