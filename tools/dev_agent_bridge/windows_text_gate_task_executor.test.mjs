// Managed candidate tests only. Never invoke actual executor/helper, CLI, WFP or UAC.
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, writeFileSync, mkdtempSync, realpathSync, rmSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
const local = name => fileURLToPath(new URL(name, import.meta.url));
const source = local('./windows_text_gate_task_executor.cs');
const dependencies = new Map([
  [local('./windows_text_gate_isolation_helper.cs'), 'd22017641d9f8df750f6db7db9319b8c1930a726a8575ff1ffabfde0d5ffdcd8'],
  [local('./windows_text_gate_appid_startup_helper.cs'), 'c777023495ccdbf3b52663f49683f5d84dcfd03a36b3d280a75c925f37b7a1ea'],
  [local('../../tmp/p6-r7-review/native-appid-coordinator-candidate-15.cs'), 'c1f07e9487b8ce25d0acc2d5bbb03b69c975cbb7e448698d288ff6263cff9311'],
  [local('../../tmp/p6-r7-review/native-appid-matrix-contract-01.cs'), 'f70ffb86ce5efea2572532e1986f77dde9622893ad4b90a74f9ec40da5ba6774'],
  [local('./windows_text_gate_appid_matrix_native.cs'), 'f2d3b35a1e6d1763930ba7f9a82ab8dbb595e02d5d720216a0161dbce8a0d0ab'],
]);
const hash = file => createHash('sha256').update(readFileSync(file)).digest('hex');
const code = readFileSync(source, 'utf8');
const harness = String.raw`
using System;using System.Collections.Generic;using System.IO;using System.Threading;using System.Reflection;using System.Runtime.Serialization;
namespace HereIAm.R7 {public static class TaskExecutorManagedHarness {
 static int checks;static void Check(bool ok){if(!ok)throw new Exception("managed_case_"+checks);checks++;}
 static void Reject(Action action){bool rejected=false;try{action();}catch{rejected=true;}Check(rejected);}
 static Guid id=new Guid("11111111-2222-4333-8444-555555555555");
 static Dictionary<string,object> Frame(string kind){return new Dictionary<string,object>{{"attempt_id",id.ToString("D")},{"seq",1},{"command_id",1},{"type",kind}};}
 static void RejectFrame(Dictionary<string,object> value){Reject(delegate{new TaskProtocol(id,32123).Read(TaskJson.Json(value));});}
 public static int Main(string[] args){
  var close=Frame("close");Check((string)new TaskProtocol(id,32123).Read(TaskJson.Json(close))["type"]=="close");
  foreach(string key in new[]{"seq","command_id"})foreach(object bad in new object[]{0,-1,2,1.0,"1",true,null,2147483648L}){var f=Frame("close");f[key]=bad;if(bad is double){Reject(delegate{new TaskProtocol(id,32123).Read(TaskJson.Json(f).Replace("\""+key+"\":1","\""+key+"\":1.0"));});}else RejectFrame(f);}
  foreach(string value in new[]{"11111111-2222-4333-8444-555555555556","11111111222243338444555555555555","11111111-2222-4333-8444-55555555555A"}){var f=Frame("close");f["attempt_id"]=value;RejectFrame(f);}
  var extra=Frame("close");extra["executable"]="evil.exe";RejectFrame(extra);
  var peer=Frame("verify_peer");peer["tuple"]=new Dictionary<string,object>{{"family",4},{"protocol","tcp"},{"local_address","127.0.0.1"},{"local_port",32123},{"remote_address","127.0.0.1"},{"remote_port",50000}};Check(new TaskProtocol(id,32123).Read(TaskJson.Json(peer)).Count==5);
  foreach(string key in new[]{"family","protocol","local_address","local_port","remote_address","remote_port"}){var tuple=(Dictionary<string,object>)peer["tuple"];object original=tuple[key];tuple[key]=key.Contains("port")?(object)0:key=="family"?(object)6:"invalid";RejectFrame(peer);tuple[key]=original;}
  var unicode=TaskJson.Parse("{\"msg\":\"中文 😀 < > & \\\"\",\"x\":{\"a\":1},\"y\":{\"a\":2}}");Check(unicode.Count==3);
  foreach(string bad in new[]{"{\"x\":{\"a\":1,\"a\":2}}","{\"x\":[{\"a\":1,\"\\u0061\":2}]}","{\"a\":+1}","{\"a\":.1}","{\"a\":1e}","{\"a\":truefalse}","{\"a\":\"\\x41\"}"})Reject(delegate{TaskJson.Parse(bad);});
  var transcript=new List<string>();var emitter=new TaskEmitter(id,delegate(string s){transcript.Add((string)TaskJson.Parse(s)["type"]);});
  emitter.Emit("started",null);emitter.DrainAndDispatch(1,delegate{emitter.Emit("rpc",null);},delegate{Check(transcript.Count==2);});emitter.Emit("rpc",null);Check(String.Join(",",transcript.ToArray())=="started,rpc,written,rpc");
  Reject(delegate{emitter.DrainAndDispatch(2,delegate{throw new IOException();},delegate{throw new Exception("write_must_not_run");});});Check(transcript.Count==4);
  using(var entered=new ManualResetEvent(false))using(var release=new ManualResetEvent(false)){
   var writer=new Thread(delegate(){emitter.Dispatch(3,delegate{entered.Set();Check(release.WaitOne(2000));});});writer.Start();Check(entered.WaitOne(1000));
   var output=new Thread(delegate(){emitter.Emit("rpc",null);});output.Start();Check(!output.Join(30));release.Set();Check(writer.Join(2000)&&output.Join(2000));Check(transcript[4]=="written"&&transcript[5]=="rpc");
  }
  string file=Path.Combine(args[0],"exclusive-lease.json"),read=null;Exception failure=null;
  using(var writer=new FileStream(file,FileMode.CreateNew,FileAccess.Write,FileShare.None))using(var attempted=new ManualResetEvent(false)){
   var reader=new Thread(delegate(){try{read=TaskCheck.WaitReadCore(delegate{return false;},delegate{attempted.Set();return File.ReadAllText(file);},2000);}catch(Exception e){failure=e;}});reader.Start();Check(attempted.WaitOne(1000));Check(!reader.Join(50));byte[] bytes=System.Text.Encoding.UTF8.GetBytes("complete");writer.Write(bytes,0,bytes.Length);writer.Flush(true);Check(!reader.Join(50));writer.Dispose();Check(reader.Join(2500));Check(failure==null&&read=="complete");
  }
  var files=(TaskFiles)FormatterServices.GetUninitializedObject(typeof(TaskFiles));typeof(TaskFiles).GetField("Cwd",BindingFlags.Instance|BindingFlags.NonPublic).SetValue(files,@"D:\fixed\project0");var validate=typeof(TaskExecutorProgram).GetMethod("ValidateRpc",BindingFlags.Static|BindingFlags.NonPublic);
  foreach(string method in new[]{"config/value/write","account/login/start","thread/resume","process/spawn","command/exec"}){var rpc=TaskJson.Parse("{\"id\":1,\"method\":\""+method+"\",\"params\":{}}");Reject(delegate{validate.Invoke(null,new object[]{rpc,files});});}
  foreach(string method in new[]{"configRequirements/read","initialized"}){var rpc=TaskJson.Parse(method=="initialized"?"{\"method\":\"initialized\",\"params\":{}}":"{\"id\":1,\"method\":\"configRequirements/read\",\"params\":{}}");validate.Invoke(null,new object[]{rpc,files});Check(true);}
  var config=TaskJson.Parse("{\"id\":1,\"method\":\"config/read\",\"params\":{\"cwd\":\"D:\\\\other\",\"includeLayers\":true}}");Reject(delegate{validate.Invoke(null,new object[]{config,files});});
  var refresh=TaskJson.Parse("{\"id\":1,\"method\":\"account/read\",\"params\":{\"refreshToken\":true}}");Reject(delegate{validate.Invoke(null,new object[]{refresh,files});});
  string routeFlag=" -c \"features.respect_system_proxy=false\"";
  foreach(int port in new[]{1,32123,65535}){string baseline=CliStartupContract.Arguments(port);foreach(bool authenticated in new[]{false,true}){string actual=TaskLaunchContract.Arguments(port,authenticated),expected=authenticated?baseline.Replace("requires_openai_auth=false","requires_openai_auth=true"):baseline;Check(actual==expected+routeFlag);Check(actual.IndexOf(routeFlag,StringComparison.Ordinal)==actual.Length-routeFlag.Length);}}
  string work=@"D:\private\attempt\work",dedicated=@"C:\private\dedicated",system=@"C:\Windows",environment=CliStartupContract.EnvironmentBlock(system,work);
  // This harness receives synthetic proxy variables only; the candidate must never inherit them.
  Check(Environment.GetEnvironmentVariable("NO_PROXY")=="synthetic.invalid");
  foreach(bool authenticated in new[]{false,true}){string actual=TaskLaunchContract.EnvironmentBlock(system,work,authenticated,authenticated?dedicated:null),expected=authenticated?environment.Replace("CODEX_HOME="+Path.Combine(work,"empty-home")+"\0","CODEX_HOME="+dedicated+"\0"):environment;Check(actual.Replace("NO_PROXY=127.0.0.1\0","")==expected);string[] entries=actual.Split(new char[]{'\0'});Check(entries.Length==13&&entries[11]==""&&entries[12]=="");var keys=new HashSet<string>(StringComparer.OrdinalIgnoreCase);string previous=null;for(int i=0;i<11;i++){int separator=entries[i].IndexOf('=');Check(separator>0);string key=entries[i].Substring(0,separator);Check(keys.Add(key));Check(previous==null||StringComparer.OrdinalIgnoreCase.Compare(previous,key)<0);previous=key;}Check(keys.SetEquals(new[]{"APPDATA","CODEX_HOME","HOME","LOCALAPPDATA","NO_PROXY","PATH","SystemRoot","TEMP","TMP","USERPROFILE","WINDIR"}));Check(!actual.Contains("synthetic.invalid")&&!actual.Contains("P6_UNTRUSTED")&&!actual.Contains("HTTP_PROXY=")&&!actual.Contains("HTTPS_PROXY=")&&!actual.Contains("ALL_PROXY="));}
  Check(Array.IndexOf(TaskLaunchContract.ForbiddenHomeEntries(false),"skills")>=0);Check(Array.IndexOf(TaskLaunchContract.ForbiddenHomeEntries(true),"skills")<0);foreach(string forbidden in new[]{"config.toml","AGENTS.md","AGENTS.override.md","plugins","hooks.json",".codex"})Check(Array.IndexOf(TaskLaunchContract.ForbiddenHomeEntries(true),forbidden)>=0);
  Check(TaskLaunchContract.Authenticated("chatgpt")&&!TaskLaunchContract.Authenticated("no_auth"));foreach(string mode in new[]{"openai","CHATGPT","true","",null})Reject(delegate{TaskLaunchContract.Authenticated(mode);});
  var account=TaskJson.Parse("{\"id\":2,\"method\":\"account/read\",\"params\":{\"refreshToken\":false}}");Reject(delegate{validate.Invoke(null,new object[]{account,files});});typeof(TaskFiles).GetField("Authenticated",BindingFlags.Instance|BindingFlags.NonPublic).SetValue(files,true);validate.Invoke(null,new object[]{account,files});Check(true);Reject(delegate{validate.Invoke(null,new object[]{refresh,files});});((Dictionary<string,object>)account["params"])["apiKey"]="not_allowed";Reject(delegate{validate.Invoke(null,new object[]{account,files});});
  typeof(TaskFiles).GetField("Attempt",BindingFlags.Instance|BindingFlags.NonPublic).SetValue(files,id);typeof(TaskFiles).GetField("SelfHash",BindingFlags.Instance|BindingFlags.NonPublic).SetValue(files,new string('a',64));var journal=new Dictionary<string,object>{{"schema","p6_r7_task_owned_v2"},{"attempt_id",id.ToString("D")},{"scope_id",TaskPaths.Scope(id).ToString("D")},{"auth_mode","chatgpt"},{"home_class","dedicated_existing"},{"nonce",new string('b',64)},{"owner_pid",12},{"owner_creation","123"},{"owner_sha256",new string('a',64)},{"owner_token_digest",new string('c',64)},{"cli_sha256",CliStartupContract.Pin},{"broker_port",32123},{"phase","prepared"},{"child_pid",null},{"child_creation",null}};Check(TaskRecords.Validate(TaskJson.Json(journal),files).Count==15);
  journal["auth_mode"]="no_auth";Reject(delegate{TaskRecords.Validate(TaskJson.Json(journal),files);});journal["auth_mode"]="chatgpt";journal["home_class"]="fresh_attempt";Reject(delegate{TaskRecords.Validate(TaskJson.Json(journal),files);});journal["home_class"]="dedicated_existing";
  var lease=TaskRecords.Lease(journal,"install",20,456,new string('d',64));Check((string)lease["auth_mode"]=="chatgpt"&&(string)lease["home_class"]=="dedicated_existing");var helperReceipt=TaskRecords.Receipt(journal,"install",20,456,new string('e',64),123);Check(TaskRecords.VerifyReceipt(TaskJson.Json(helperReceipt),journal,"install",20,456,new string('e',64),123)==123);helperReceipt["auth_mode"]="no_auth";Reject(delegate{TaskRecords.VerifyReceipt(TaskJson.Json(helperReceipt),journal,"install",20,456,new string('e',64),123);});
  typeof(TaskFiles).GetField("Authenticated",BindingFlags.Instance|BindingFlags.NonPublic).SetValue(files,false);Reject(delegate{TaskRecords.Validate(TaskJson.Json(journal),files);});journal["auth_mode"]="no_auth";journal["home_class"]="fresh_attempt";Check(TaskRecords.Validate(TaskJson.Json(journal),files).Count==15);
  var receipt=new TaskClosure();Check(!receipt.Complete&&(bool)receipt.Receipt()["cleanup_pending"]);Check(receipt.Receipt().Count==7);Check(!(bool)receipt.Receipt()["process_close_observed"]&&!(bool)receipt.Receipt()["stdio_eof_verified"]);
  foreach(TaskStartupStage stage in Enum.GetValues(typeof(TaskStartupStage))){TaskStartupTrace.Stage=stage;foreach(Exception diagnostic in new Exception[]{new BoundaryError("PRIVATE_PATH_AND_SID",5),new BoundaryError("PRIVATE_PATH_AND_SID",87),new BoundaryError("PRIVATE_PATH_AND_SID",UInt32.MaxValue),new BoundaryError("PRIVATE_PATH_AND_SID"),new IOException("PRIVATE_PATH_AND_SID"),new UnauthorizedAccessException("PRIVATE_PATH_AND_SID"),new Exception("PRIVATE_PATH_AND_SID")}){string result=TaskStartupTrace.Code(diagnostic);Check(result.Length<=80&&System.Text.RegularExpressions.Regex.IsMatch(result,"\\Atask_[a-z0-9_]+\\z")&&!result.Contains("PRIVATE"));}}
  TaskStartupTrace.Stage=TaskStartupStage.job_limits;Check(TaskStartupTrace.Code(new BoundaryError("ignored",87))=="task_job_limits_win32_87");TaskStartupTrace.Stage=TaskStartupStage.files_dedicated_pin;Check(TaskStartupTrace.Code(new BoundaryError("ignored",5))=="task_files_dedicated_pin_win32_5");TaskStartupTrace.Stage=(TaskStartupStage)999;Check(TaskStartupTrace.Code(new Exception("secret"))=="task_unknown_failed");
  var launchFailure=new TaskHelperRun();TaskStartupTrace.Stage=TaskStartupStage.helper_shell_execute;launchFailure.Capture(new BoundaryError("PRIVATE_SOURCE_1",1223));TaskStartupTrace.Stage=TaskStartupStage.helper_handle_close;launchFailure.Capture(new BoundaryError("PRIVATE_SOURCE_2",5));Exception captured=null;try{launchFailure.RequireAccepted();}catch(Exception error){captured=error;}Check(captured!=null&&TaskStartupTrace.Code(captured)=="task_helper_shell_execute_win32_1223");Check(captured.InnerException==null&&!captured.Message.Contains("PRIVATE"));Check(!launchFailure.Accepted&&!launchFailure.Exited&&!launchFailure.Receipt&&!launchFailure.LiveBound&&!launchFailure.Launched);
  foreach(TaskStartupStage stage in Enum.GetValues(typeof(TaskStartupStage))){if(!stage.ToString().StartsWith("helper_",StringComparison.Ordinal))continue;var outcome=new TaskHelperRun();TaskStartupTrace.Stage=stage;outcome.Capture(new BoundaryError("PRIVATE_HELPER_VALUE",UInt32.MaxValue));TaskStartupTrace.Stage=TaskStartupStage.runtime;Exception diagnostic=null;try{outcome.RequireAccepted();}catch(Exception error){diagnostic=error;}Check(diagnostic!=null&&TaskStartupTrace.Code(diagnostic)=="task_"+stage+"_win32_4294967295"&&!outcome.Accepted);}
  var success=new TaskHelperRun{Launched=true,LiveBound=true,Exited=true,Exit=0,Receipt=true,Handles=true};success.RequireAccepted();Check(success.Accepted);success.Receipt=false;Reject(delegate{success.RequireAccepted();});Check(!success.Accepted&&success.Exited&&!success.Receipt);
  string local=@"C:\private\Local",physical=TaskHomeContract.PhysicalHome(local);Check(physical==Path.Combine(local,@"Packages\OpenAI.Codex_2p2nqsd0c76g0\LocalCache\Local\HereIAm\Runtime\p6-text-only-codex"));Check(TaskHomeContract.ExactPhysical(physical,local));Check(TaskHomeContract.ExactPhysical(physical.ToUpperInvariant(),local));Check(!TaskHomeContract.ExactPhysical(Path.Combine(local,@"HereIAm\Runtime\p6-text-only-codex"),local));Check(!TaskHomeContract.ExactPhysical(physical.Replace("OpenAI.Codex_2p2nqsd0c76g0","OpenAI.Codex_otherfamily"),local));Check(!TaskHomeContract.ExactPhysical(physical+"-other",local));Check(!TaskHomeContract.ExactPhysical(physical.Replace("LocalCache","LocalState"),local));
  var directory=new MatrixNativeApi.FileInfo{Attributes=0x10,Volume=17,IndexHigh=12,IndexLow=34};Check(TaskHomeContract.SameDirectory(directory,directory));foreach(string field in new[]{"Volume","IndexHigh","IndexLow"}){object altered=directory;var member=typeof(MatrixNativeApi.FileInfo).GetField(field,BindingFlags.Instance|BindingFlags.NonPublic);member.SetValue(altered,(uint)99);Check(!TaskHomeContract.SameDirectory(directory,(MatrixNativeApi.FileInfo)altered));}foreach(uint attributes in new uint[]{0,0x400,0x410}){var altered=directory;altered.Attributes=attributes;Check(!TaskHomeContract.SameDirectory(directory,altered)&&!TaskHomeContract.SameDirectory(altered,directory));}var zero=directory;zero.IndexHigh=zero.IndexLow=0;Check(!TaskHomeContract.SameDirectory(zero,zero));

  var finalBinding=TaskFinalContract.Binding(journal);Check(finalBinding.Count==10&&!finalBinding.ContainsKey("owner_token_digest"));
  foreach(string key in new List<string>(finalBinding.Keys)){var missing=new Dictionary<string,object>(finalBinding);missing.Remove(key);Reject(delegate{TaskFinalContract.Report(missing,null,null,false,0,"operation_failure",true,false,new TaskClosure());});var wrong=new Dictionary<string,object>(finalBinding);wrong[key]=new Dictionary<string,object>{{"private","must_not_copy"}};Reject(delegate{TaskFinalContract.Report(wrong,null,null,false,0,"operation_failure",true,false,new TaskClosure());});}
  var extraFinalBinding=new Dictionary<string,object>(finalBinding);extraFinalBinding["owner_token_digest"]=new string('a',64);Reject(delegate{TaskFinalContract.Report(extraFinalBinding,null,null,false,0,"operation_failure",true,false,new TaskClosure());});
  var completeClosure=new TaskClosure{Process=true,Job=true,Stdio=true,Rules=true,Handles=true,Helpers=true};
  var finalReport=TaskFinalContract.Report(finalBinding,23,456,true,0,"input_eof",true,false,completeClosure);
  Check(finalReport.Count==21&&Object.Equals(finalReport["schema"],"p6_r7_task_final_receipt_v1")&&Object.Equals(finalReport["requires_actual_exit_0_or_3"],true)&&Object.Equals(finalReport["receipt_write_state"],"pending_actual_exit_commit"));
  Check(Object.Equals(finalReport["shutdown_trigger"],"input_eof")&&Object.Equals(finalReport["stdout_final_emit_succeeded"],false)&&Object.Equals(finalReport["operation_failed"],true));
  Check(TaskExitPolicy.Code(true,true,true,false,true,false)==3);Check(TaskExitPolicy.Code(true,false,true,true,true,false)==0);
  Check(TaskExitPolicy.Code(true,false,true,true,false,false)==4);Check(TaskExitPolicy.Code(true,true,true,false,false,false)==4);Check(TaskExitPolicy.Code(true,false,true,true,true,true)==4);
  foreach(string field in new[]{"Process","Job","Stdio","Rules","Handles","Helpers"}){var member=typeof(TaskClosure).GetField(field,BindingFlags.Instance|BindingFlags.NonPublic);member.SetValue(completeClosure,false);var incomplete=TaskFinalContract.Report(finalBinding,23,456,true,1,"close_command",false,true,completeClosure);Check((bool)((Dictionary<string,object>)incomplete["receipt"])["cleanup_pending"]);Check(TaskExitPolicy.Code(true,false,completeClosure.Complete,true,true,false)==4);member.SetValue(completeClosure,true);}
  foreach(string trigger in new[]{"",null,"eof","PRIVATE_PATH","input_eof_other"})Reject(delegate{TaskFinalContract.Report(finalBinding,23,456,true,0,trigger,false,true,completeClosure);});
  Reject(delegate{TaskFinalContract.Report(finalBinding,23,null,true,0,"input_eof",false,true,completeClosure);});Reject(delegate{TaskFinalContract.Report(finalBinding,null,null,true,0,"input_eof",false,true,completeClosure);});Reject(delegate{TaskFinalContract.Report(finalBinding,23,456,true,1,"input_eof",false,true,completeClosure);});Reject(delegate{TaskFinalContract.Report(finalBinding,23,456,true,0,"close_command",false,true,completeClosure);});
  var noChild=new TaskClosure();var early=TaskFinalContract.Report(finalBinding,null,null,false,0,"operation_failure",true,false,noChild);Check(early["child_pid"]==null&&early["child_creation"]==null&&(bool)((Dictionary<string,object>)early["receipt"])["cleanup_pending"]);Check(TaskExitPolicy.Code(false,true,noChild.Complete,false,true,false)==4);
  byte[] finalBytes=System.Text.Encoding.UTF8.GetBytes(TaskJson.Json(finalReport));
  foreach(string failurePoint in new[]{"none","ancestor_pin","acl","duplicate_file","open","output_pin_before","write","flush","output_pin_after","post_pin","write_close","evidence_close","write_close_throw","evidence_close_throw"}){
   var events=new List<string>();int verifyCalls=0,outputChecks=0;bool opened=false;
   Action verify=delegate{events.Add(++verifyCalls==1?"pre_verify":"post_verify");if(verifyCalls==1&&(failurePoint=="ancestor_pin"||failurePoint=="acl")||verifyCalls==2&&failurePoint=="post_pin")throw new IOException("PRIVATE");};
   Func<bool> absent=delegate{events.Add("absent");return failurePoint!="duplicate_file";};
   Action open=delegate{events.Add("open");if(failurePoint=="open")throw new IOException("PRIVATE");opened=true;};
   Action<byte[]> write=delegate(byte[] bytes){events.Add("write");Check(opened&&bytes==finalBytes);if(failurePoint=="write")throw new IOException("PRIVATE");};
   Action flush=delegate{events.Add("flush");if(failurePoint=="flush")throw new IOException("PRIVATE");};
   Action verifyOutput=delegate{events.Add(++outputChecks==1?"output_pin_before":"output_pin_after");if(outputChecks==1&&failurePoint=="output_pin_before"||outputChecks==2&&failurePoint=="output_pin_after")throw new IOException("PRIVATE");};
   Func<bool> closeOutput=delegate{events.Add("write_close");if(failurePoint=="write_close_throw")throw new IOException("PRIVATE");return failurePoint!="write_close";};
   Func<bool> closeEvidence=delegate{events.Add("evidence_close");if(failurePoint=="evidence_close_throw")throw new IOException("PRIVATE");return failurePoint!="evidence_close";};
   bool committed=TaskFinalWrite.Run(finalBytes,verify,absent,open,write,flush,verifyOutput,closeOutput,closeEvidence);
   Check(committed==(failurePoint=="none"));Check(events[events.Count-2]=="write_close"&&events[events.Count-1]=="evidence_close");
   Check(TaskExitPolicy.Code(true,false,true,true,committed,false)==(committed?0:4));Check(TaskExitPolicy.Code(true,true,true,false,committed,false)==(committed?3:4));
   if(failurePoint=="none")Check(String.Join(",",events.ToArray())=="pre_verify,absent,open,output_pin_before,write,flush,output_pin_after,post_verify,write_close,evidence_close");
   if(failurePoint=="duplicate_file"||failurePoint=="ancestor_pin"||failurePoint=="acl")Check(!events.Contains("open")&&!events.Contains("write"));
  }
  int finalCloses=0;Check(!TaskFinalWrite.Run(new byte[16385],delegate{throw new Exception("must_not_verify");},delegate{return true;},delegate{},delegate(byte[] b){},delegate{},delegate{},delegate{finalCloses++;return true;},delegate{finalCloses++;return true;}));Check(finalCloses==2);
  int closes=0;var ledger=new MatrixHandleLedger(delegate(IntPtr handle){closes++;return handle.ToInt64()!=22||closes>=3;});ledger.Own(new IntPtr(11));ledger.Own(new IntPtr(22));Check(!ledger.CloseAll()&&!ledger.Empty&&!ledger.AllCloseCallsSucceeded);Check(!ledger.CloseAll()&&ledger.Empty&&!ledger.AllCloseCallsSucceeded&&MatrixHandleLedger.AnyCloseFailure);Check(TaskExitPolicy.Code(false,true,false,true,true,MatrixHandleLedger.AnyCloseFailure)==4);
  Console.WriteLine("{\"managed_assertions\":"+checks+",\"native_executed\":false}");return 0;
 }
}}
`;
test('native task executor compile and managed protocol/lifecycle checks only', t => {
  const baseline = new Map([...dependencies, [source, hash(source)]]);
  for (const [file, pin] of baseline) assert.equal(hash(file), pin);
  const parent = local('../../tmp/p6-r7-helper/');
  const tmp = mkdtempSync(path.join(parent, 'task-executor-test-'));
  t.after(() => {
    for (const [file, pin] of baseline) assert.equal(hash(file), pin);
    const canonical = realpathSync(tmp);
    assert.equal(path.dirname(canonical), realpathSync(parent));
    assert.match(path.basename(canonical), /^task-executor-test-/);
    rmSync(canonical, { recursive: true, force: true });
  });
  const compile = (main, output, extra = []) => {
    const result = spawnSync(String.raw`C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe`,
      ['/nologo', '/platform:x64', '/target:exe', '/warnaserror+', '/reference:System.Web.Extensions.dll', `/main:${main}`, `/out:${output}`, ...dependencies.keys(), source, ...extra],
      { encoding: 'utf8', windowsHide: true, timeout: 30000 });
    assert.equal(result.status, 0, result.stdout + result.stderr);
  };
  const exe = path.join(tmp, 'executor.exe');
  compile('HereIAm.R7.TaskExecutorProgram', exe);
  for (const arg of ['--plan', '--self-test', '--invalid-managed-test']) {
    const result = spawnSync(exe, [arg], { encoding: 'utf8', windowsHide: true, timeout: 20000 });
    assert.equal(result.status, arg === '--invalid-managed-test' ? 2 : 0, result.stdout + result.stderr);
    assert.equal(result.stderr, '');
    const report = JSON.parse(result.stdout);
    assert.equal(report.schema, 'p6_r7_task_executor_v1');
    for (const field of ['native_executed', 'production_isolation_passed', 'human_gate_passed']) assert.equal(report[field], false);
    assert.equal(report.auth_mode, 'no_auth');
    assert.equal(report.real_upstream_requests, 0);
    assert.equal(report.model_turns_requested, 0);
    if (arg === '--self-test') assert.ok(report.assertions_passed >= 95);
  }
  const harnessFile = path.join(tmp, 'managed.cs'), harnessExe = path.join(tmp, 'managed.exe');
  writeFileSync(harnessFile, harness);
  compile('HereIAm.R7.TaskExecutorManagedHarness', harnessExe, [harnessFile]);
  const result = spawnSync(harnessExe, [tmp], { encoding: 'utf8', windowsHide: true, timeout: 20000,
    env: { SystemRoot: String.raw`C:\Windows`, WINDIR: String.raw`C:\Windows`,
      NO_PROXY: 'synthetic.invalid', HTTP_PROXY: 'http://synthetic.invalid',
      HTTPS_PROXY: 'http://synthetic.invalid', ALL_PROXY: 'http://synthetic.invalid', P6_UNTRUSTED: 'synthetic.invalid' } });
  assert.equal(result.status, 0, result.stdout + result.stderr);
  const report = JSON.parse(result.stdout);
  assert.equal(report.native_executed, false);
  assert.ok(report.managed_assertions >= 500); t.diagnostic(`managed harness: ${report.managed_assertions} assertions; native --self-test: 95 assertions; no actual execution`);
});
test('native candidate keeps fixed launch, checked cleanup, and private metadata boundaries', () => {
  assert.match(code, /CliStartupContract\.Arguments\(port\)/);
  assert.match(code, /true,0x8040c,arena\.Text\(files\.EnvironmentBlock\(\)\)/);
  assert.match(code, /CancelSynchronousIo\(call\.nativeThread\)/);
  assert.match(code, /emit\.DrainAndDispatch\(command/);
  assert.match(code, /frames<64&&bytes<=TaskJson\.MaxFrameBytes&&reads\+\+<256/);
  assert.match(code, /Path\.Combine\(original\.Directory,"final-receipt\.json"\)/);
  assert.match(code, /Native\.CreateFileW\(path,0xc0000000u,1,IntPtr\.Zero,1,0x00200000u,IntPtr\.Zero\)/);
  assert.match(code, /FlushFileBuffers\(handle\)/);
  assert.match(code, /MatrixNativeApi\.HashHandle\(handle\)==expectedBodyHash/);
  assert.match(code, /evidence=new TaskFiles\(original\.Attempt,user,false,original\.Authenticated\)/);
  assert.match(code, /requires_actual_exit_0_or_3/);
  assert.match(code, /receipt_write_state","pending_actual_exit_commit/);
  assert.ok(code.lastIndexOf('durableCommitSucceeded=finalReceipt.Commit(') > code.lastIndexOf('closure.Handles=TaskNativeWrite.ClosePending()'));
  assert.ok(code.lastIndexOf('closure.Handles=TaskNativeWrite.ClosePending()') > code.lastIndexOf('emit.Emit("closed"'));
  assert.ok(code.lastIndexOf('TaskExitPolicy.Code(started,failed,closure.Complete,finalEmitSucceeded,durableCommitSucceeded,MatrixHandleLedger.AnyCloseFailure)') > code.lastIndexOf('durableCommitSucceeded=finalReceipt.Commit('));
  const durable = code.slice(code.indexOf('    internal static class TaskFinalWrite'), code.indexOf('    internal sealed class TaskBoundary'));
  assert.doesNotMatch(durable, /owner_token_digest|Directory\.Create|FileMode\.Create|TaskPaths\.DedicatedHome|WriteAllText|\.Read\(/);
  assert.doesNotMatch(code, /MediumIdentity\.OfProcess\(|GetEnvironmentVariables\(|auth\.json|transcript\.json|Process\.Start\(/);
  assert.match(code, /uint status=Native\.FwpmEngineClose0\(engine\); if\(status==0\)engine=IntPtr.Zero;else closeOk=false/);
  const copied = code.slice(code.indexOf('    internal sealed class TaskBoundary'), code.indexOf('    internal sealed class TaskPipes'));
  const original = readFileSync([...dependencies.keys()][2], 'utf8');
  const begin = original.indexOf('    internal sealed class CoordinatorBoundary : IDisposable {');
  const end = original.indexOf('    internal static class CoordinatorFilterNative', begin);
  const normalized = copied.replaceAll('TaskBoundary', 'CoordinatorBoundary')
    .replace('bool closeOk=true; IntPtr engine;', 'IntPtr engine;')
    .replace('internal bool CloseVerified() { if(engine==IntPtr.Zero)return closeOk; uint status=Native.FwpmEngineClose0(engine); if(status==0)engine=IntPtr.Zero;else closeOk=false;return closeOk&&engine==IntPtr.Zero; } public void Dispose() { CloseVerified(); }', 'public void Dispose() { if(engine!=IntPtr.Zero) Native.FwpmEngineClose0(engine); engine=IntPtr.Zero; }');
  assert.equal(normalized.trim(), original.slice(begin, end).trim(), 'only checked engine-close delta from frozen WFP implementation');
});
