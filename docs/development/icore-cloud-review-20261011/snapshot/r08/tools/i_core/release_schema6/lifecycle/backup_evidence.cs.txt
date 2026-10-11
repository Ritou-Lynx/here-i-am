
public sealed class Schema6BackupEvidence : IDisposable {
 readonly string ps,release,manifest,session,control,policyPath,policyHash,loginHash,bindingPath,bindingHash,approvalHash;string planHash;readonly string[] arguments;readonly int interval;readonly bool recoveredControl;string phase;readonly Func<Dictionary<string,object>> observe;
 readonly List<BackupDurable.Lease> leases=new List<BackupDurable.Lease>();
 Dictionary<string,object> policy,permit,snapshot;Schema6BackupJob producer,worker;
 bool producerStarted,permitAccepted,attemptOpen;volatile bool failed,terminalRequested;readonly object terminalGate=new object();public bool Disposed{get;private set;}public bool DisposalDeferred{get;private set;}DateTime next=DateTime.MinValue;
 Dictionary<string,object> sourceBindings=new Dictionary<string,object>();
 string attemptId,firstAttemptId,firstAttemptHash,intentHash,workerHash,resultHash,permitHash;int sequence;Stopwatch attemptClock;
 public bool Failed{get{return failed;}}bool firstAttemptComplete,firstAttemptSuccessful;public bool FirstAttemptComplete{get{return firstAttemptComplete&&!failed;}private set{firstAttemptComplete=value;}}public bool FirstAttemptSuccessful{get{return firstAttemptSuccessful&&!failed;}private set{firstAttemptSuccessful=value;}}public string FirstAttemptId{get{return firstAttemptId;}}
 public bool Exited{get{return (producer==null||producer.Exited)&&(worker==null||worker.Exited);}}
 public bool Empty{get{return (producer==null||producer.Empty)&&(worker==null||worker.Empty);}}
 public bool CaptureComplete{get{return CaptureClosed(producer)&&CaptureClosed(worker);}}
 static bool CaptureClosed(Schema6BackupJob j){return j==null||(j.CaptureComplete&&j.InputComplete&&!j.InputFailed&&j.Stdout.Eof&&j.Stderr.Eof&&!j.Stdout.Overflow&&!j.Stderr.Overflow&&j.Stdout.Failure==null&&j.Stderr.Failure==null);}
 public bool Closed{get{return !failed&&(!producerStarted||permitAccepted)&&!attemptOpen&&Exited&&Empty&&CaptureComplete;}}
 static readonly JavaScriptSerializer serializer=new JavaScriptSerializer{MaxJsonLength=1048576,RecursionLimit=32};
 public Schema6BackupEvidence(string powerShell,string root,string manifestHash,string sessionRoot,string controlRoot,string approvedPolicy,string approvedHash,string loginConfigurationHash,string[] args,int seconds,Func<Dictionary<string,object>> observation,bool controlRecovered,string approvedBindingPath,string approvedBindingHash,string expectedApprovalHash){
  bindingPath=approvedBindingPath;bindingHash=approvedBindingHash;approvalHash=expectedApprovalHash;ps=powerShell;release=root;manifest=manifestHash;session=sessionRoot;control=controlRoot;policyPath=approvedPolicy;policyHash=approvedHash;loginHash=loginConfigurationHash;arguments=args;interval=seconds;observe=observation;recoveredControl=controlRecovered;
 }
 static byte[] Encode(object value){lock(serializer)return new UTF8Encoding(false,true).GetBytes(serializer.Serialize(value));}
 static string S(Dictionary<string,object>d,string k){return BackupStrictJson.Text(d,k);}
 static void Equal(Dictionary<string,object>d,string k,string value){if(S(d,k)!=value)throw new IOException("backup_binding_mismatch");}
 static void Hex(string x){if(!System.Text.RegularExpressions.Regex.IsMatch(x??"","^[a-f0-9]{64}$"))throw new IOException("backup_hash_contract");}
 BackupDurable.Lease Keep(string path,string hash,int max){var l=BackupDurable.Read(path,hash,max);leases.Add(l);return l;}
 static Dictionary<string,object> Obj(Dictionary<string,object>d,string k){var v=d.ContainsKey(k)?d[k] as Dictionary<string,object>:null;if(v==null)throw new IOException("backup_object");return v;}
 public void Tick(){lock(terminalGate){if(!Disposed&&!terminalRequested)TickCore();}}
 void TickCore(){
  TickRecovery();if(failed)return;
  try{
   if(!producerStarted){if(!policyLoaded){LoadPolicy();policyLoaded=true;}if(!ResolvePhase())return;producerStarted=true;LaunchProducer();return;}
   if(!permitAccepted){
    if(producer.Elapsed.ElapsedMilliseconds>120000)throw new IOException("backup_p3_timeout");
    if(!producer.Exited||!producer.Empty||!producer.CaptureComplete)return;
    CaptureReady(producer);if(producer.ExitCode!=0||producer.Stderr.ByteCount!=0)throw new IOException("backup_p3_rejected");
    var result=BackupStrictJson.Parse(producer.Stdout.Bytes,65536);BackupStrictJson.Keys(result,"format passed permitSha256","");Equal(result,"format","p3-permit-producer-result-v1");if(!BackupStrictJson.Bool(result,"passed"))throw new IOException("backup_p3_rejected");permitHash=S(result,"permitSha256");Hex(permitHash);
    AcceptPermit();permitAccepted=true;producerIdentity=Identity(producer);producerOutHash=producer.Stdout.Sha256;producerErrHash=producer.Stderr.Sha256;producerOutCount=producer.Stdout.ByteCount;producer.Dispose();producer=null;
   }
   if(worker!=null){
    if(worker.Elapsed.ElapsedMilliseconds>120000)throw new IOException("backup_worker_timeout");
    if(!worker.Exited||!worker.Empty||!worker.CaptureComplete)return;
    FinishAttempt();worker.Dispose();worker=null;next=DateTime.UtcNow.AddSeconds(interval);
   }
   if(!terminalRequested&&!recoveryFailureObserved&&worker==null&&DateTime.UtcNow>=next)StartAttempt();
  }catch(Exception e){LatchFailure(SafeCode(e));}
 }
 void LoadPolicy(){
  var source=Keep(policyPath,policyHash,65536);policy=BackupStrictJson.Parse(source.Bytes,65536);
  string pf=S(policy,"format");if(pf!="backup-evidence-policy-v1"&&pf!="backup-evidence-policy-v2")throw new IOException("backup_policy_format");BackupStrictJson.Keys(policy,"format evidenceMode producerSha256 phase sourceInventorySha256 nodeSha256 coreConfigSha256 mcpConfigSha256 automaticConfigSha256"+(pf=="backup-evidence-policy-v2"?" recoveryEntrySha256 recoveryPolicySha256 recoveryCleanupSha256":""),"");
  Equal(policy,"evidenceMode","reviewed-live");
  foreach(string k in new[]{"producerSha256","sourceInventorySha256","nodeSha256","coreConfigSha256","mcpConfigSha256","automaticConfigSha256"})Hex(S(policy,k));
  if(Array.IndexOf(new[]{"initial-activation","login-recovery","host-control-recovery"},S(policy,"phase"))<0)throw new IOException("backup_phase");
  Hex(bindingHash);Hex(approvalHash);
  binding=BackupRawBinding.Admit(Keep(bindingPath,bindingHash,1048576).Bytes,bindingPath,approvalHash);
  boundPolicy=Obj(binding,"policy");planHash=S(boundPolicy,"planSha256");Hex(planHash);
  var approvalRef=Obj(Obj(binding,"documents"),"approval");
  var approval=BackupStrictJson.Parse(Keep(S(approvalRef,"path"),approvalHash,1048576).Bytes,1048576);
  Equal(approval,"planSha256",planHash);Equal(approval,"scope","task-update-enable-run-attach-p3-p4-normal-close-once");
  var releaseManifest=BackupStrictJson.Parse(Keep(Path.Combine(release,"manifest.json"),manifest,8388608).Bytes,8388608);
  var entries=releaseManifest.ContainsKey("files")?releaseManifest["files"] as List<object>:null;if(entries==null)throw new IOException("backup_inventory");
  foreach(string relative in new[]{"tools/i_core/release_schema6/cli.mjs","tools/i_core/release_schema6/scheduler_once_schema6.ps1","tools/i_core/release_schema6/backup_bundle_schema6.ps1","tools/i_core/release_schema6/backup_key_child.mjs","tools/i_core/release_schema6/automatic_backup.mjs"}){
    Dictionary<string,object> found=null;foreach(var entry in entries){var item=entry as Dictionary<string,object>;if(item!=null&&S(item,"path")==relative){if(found!=null)throw new IOException("backup_inventory_duplicate");found=item;}}
    if(found==null)throw new IOException("backup_inventory_missing");string hash=S(found,"sha256");Hex(hash);Keep(Path.Combine(release,relative.Replace('/',Path.DirectorySeparatorChar)),hash,1048576);sourceBindings[relative]=hash;
  }
  leases.Add(BackupDurable.Image(ps,"8bb6fa8c283b4d92120b1ef249a9b311b0f804d4cabbe9981159976c8be76a5e"));
  leases.Add(BackupDurable.Image(Path.Combine(release,"runtime\\node.exe"),S(policy,"nodeSha256")));
  Keep(Path.Combine(release,"tools\\i_core\\release_schema6\\lifecycle\\p3-permit-producer.ps1"),S(policy,"producerSha256"),1048576);
 }
 void LaunchProducer(){
  string file=Path.Combine(release,"tools\\i_core\\release_schema6\\lifecycle\\p3-permit-producer.ps1");
  producer=new Schema6BackupJob();
  producer.Prepare(ps,new[]{"-NoProfile","-NonInteractive","-ExecutionPolicy","Bypass","-File",file,"-Execute","-BindingPath",bindingPath,"-ExpectedBindingSha256",bindingHash,"-ExpectedApprovalSha256",approvalHash,"-SessionDirectory",session,"-ControlDirectory",control,"-Phase",phase},session);
  CheckWorkerIdentity(producer);producer.Resume(null);
 }
 void AcceptPermit(){
  var lease=Keep(Path.Combine(control,"p3-backup-permit.json"),permitHash,65536);permit=BackupStrictJson.Parse(lease.Bytes,65536);
  BackupStrictJson.Keys(permit,"format evidenceMode attemptId phase approvalSha256 planSha256 p3ReceiptSha256 runLedgerSha256 releaseDirectory manifestSha256 sourceInventorySha256 nodeSha256 coreConfigSha256 loginConfigSha256 mcpConfigSha256 automaticConfigSha256 sessionId controlId instanceGuid sessionWindowSha256 launchSha256 readySha256 mcpStartSha256 processes tokenEqual","");
  Equal(permit,"format","p4-start-permit-v1");Equal(permit,"evidenceMode","reviewed-live");Equal(permit,"releaseDirectory",release);Equal(permit,"manifestSha256",manifest);Equal(permit,"loginConfigSha256",loginHash);
  Equal(permit,"phase",phase);
  Equal(permit,"approvalSha256",approvalHash);Equal(permit,"planSha256",planHash);
  foreach(string k in new[]{"sourceInventorySha256","nodeSha256","coreConfigSha256","mcpConfigSha256","automaticConfigSha256"})Equal(permit,k,S(policy,k));
  if(!BackupStrictJson.Bool(permit,"tokenEqual"))throw new IOException("backup_token_mismatch");
  foreach(string k in new[]{"p3ReceiptSha256","runLedgerSha256"})Hex(S(permit,k));
  var p3=BackupStrictJson.Parse(Keep(Path.Combine(control,"p3-actual-receipt.json"),S(permit,"p3ReceiptSha256"),1048576).Bytes,1048576);
  Equal(p3,"evidenceMode","reviewed-live");if(!BackupStrictJson.Bool(p3,"passed"))throw new IOException("backup_p3_not_passed");
  var ledger=BackupStrictJson.Parse(Keep(Path.Combine(control,"p3-run-ledger.json"),S(permit,"runLedgerSha256"),65536).Bytes,65536);
  Equal(ledger,"evidenceMode","reviewed-live");
  // Producer is the fixed hash-locked strict P3 implementation; here the host
  // independently rebinds the actual immutable output and current identities.
  snapshot=observe();CheckSnapshot(snapshot);foreach(string name in new[]{"sessionWindowSha256","launchSha256","readySha256","mcpStartSha256","sessionId","controlId"})Equal(permit,name,S(snapshot,name));
  SameProcesses(Obj(permit,"processes"),Obj(snapshot,"processes"));
 }
 void CheckSnapshot(Dictionary<string,object> current){
  if(!BackupStrictJson.Bool(current,"tokenEqual"))throw new IOException("backup_token_mismatch");
  Equal(current,"sessionId",Path.GetFileName(session));Equal(current,"controlId",Path.GetFileName(control));
 }
 static void SameProcesses(Dictionary<string,object>a,Dictionary<string,object>b){
  BackupStrictJson.Keys(a,"host supervisor core mcp","");BackupStrictJson.Keys(b,"host supervisor core mcp","");
  foreach(string name in new[]{"host","supervisor","core","mcp"}){var x=Obj(a,name);var y=Obj(b,name);BackupStrictJson.Keys(x,"pid startedTicks","");BackupStrictJson.Keys(y,"pid startedTicks","");if(BackupStrictJson.Count(x,"pid")!=BackupStrictJson.Count(y,"pid")||S(x,"startedTicks")!=S(y,"startedTicks"))throw new IOException("backup_process_binding");}
 }
 void CheckWorkerIdentity(Schema6BackupJob job){
  if(job.OwnerSid!=WindowsIdentity.GetCurrent().User.Value||job.SessionId!=(uint)Process.GetCurrentProcess().SessionId||!job.ImagePath.Equals(ps,StringComparison.OrdinalIgnoreCase))throw new IOException("backup_worker_identity");
 }
 object Identity(Schema6BackupJob job){return new {pid=job.Pid,startedTicks=job.StartedTicks,ownerSid=job.OwnerSid,sessionId=job.SessionId,imageSha256="8bb6fa8c283b4d92120b1ef249a9b311b0f804d4cabbe9981159976c8be76a5e",assignedToOwnedJob=job.Assigned,resumed=job.Resumed};}
 string Write(string phase,object data,string previous){return BackupDurable.Write(Path.Combine(control,"backup-"+attemptId+"-"+phase+".json"),Encode(new {format="i-core-backup-delivery-v1",attemptId=attemptId,firstAttemptId=firstAttemptId,sequence=++sequence,phase=phase,createdUtc=DateTime.UtcNow.ToString("o"),elapsedMs=attemptClock.ElapsedMilliseconds,prevReceiptSha256=previous,data=data}));}
 void StartAttempt(){
  var now=observe();CheckSnapshot(now);SameProcesses(Obj(snapshot,"processes"),Obj(now,"processes"));foreach(string k in new[]{"sessionWindowSha256","launchSha256","readySha256","mcpStartSha256"})Equal(now,k,S(snapshot,k));
  attemptId=Guid.NewGuid().ToString("N");bool first=firstAttemptId==null;if(first)firstAttemptId=attemptId;sequence=0;attemptClock=Stopwatch.StartNew();attemptOpen=true;
  if(first)firstAttemptHash=BackupDurable.Write(Path.Combine(control,"backup-first-attempt.json"),Encode(new {format="i-core-backup-first-attempt-v1",firstAttemptId=firstAttemptId,sessionId=Path.GetFileName(session),controlId=Path.GetFileName(control),permitSha256=permitHash,manifestSha256=manifest,approvalSha256=approvalHash}));
  intentHash=Write("intent",new {firstAttemptSha256=firstAttemptHash,permitSha256=permitHash,sessionId=Path.GetFileName(session),controlId=Path.GetFileName(control),manifestSha256=manifest,policySha256=policyHash,bindingSha256=bindingHash,approvalSha256=approvalHash,planSha256=planHash,approvedSourceInventorySha256=policy["sourceInventorySha256"],sourceHashes=sourceBindings,nodeSha256=policy["nodeSha256"],coreConfigSha256=policy["coreConfigSha256"],automaticConfigSha256=policy["automaticConfigSha256"],loginConfigSha256=loginHash,hostProcesses=now["processes"],sessionHashes=new[]{now["sessionWindowSha256"],now["launchSha256"],now["readySha256"],now["mcpStartSha256"]},tokenEqual=true},null);
  worker=new Schema6BackupJob();worker.Prepare(ps,arguments,session);CheckWorkerIdentity(worker);
  workerHash=Write("worker",Identity(worker),intentHash);worker.Resume(null);if(first)StartRecovery();
 }
 static void CaptureReady(Schema6BackupJob job){
  if(!job.Exited||!job.Empty||!job.CaptureComplete||!job.InputComplete||job.InputFailed||!job.Stdout.Eof||!job.Stderr.Eof||job.Stdout.Overflow||job.Stderr.Overflow||job.Stdout.Failure!=null||job.Stderr.Failure!=null)throw new IOException("backup_delivery_incomplete");
 }
 void FinishAttempt(){
  CaptureReady(worker);var envelope=BackupStrictJson.Parse(worker.Stdout.Bytes,65536);BackupStrictJson.Keys(envelope,"format passed report childCaptures","");Equal(envelope,"format","i-core-backup-wrapper-result-v3");bool wrapperPassed=BackupStrictJson.Bool(envelope,"passed");
  var captures=envelope["childCaptures"] as List<object>;if(captures==null||captures.Count>2||(wrapperPassed&&captures.Count!=2))throw new IOException("backup_capture_schema");
  for(int i=0;i<captures.Count;i++){var c=captures[i] as Dictionary<string,object>;if(c==null)throw new IOException("backup_capture_schema");BackupChildDiagnostic.Validate(c,i==0?"cli-verify":"key-child",(string)sourceBindings["tools/i_core/release_schema6/"+(i==0?"cli.mjs":"backup_key_child.mjs")],wrapperPassed);}
  var report=envelope["report"]==null?new Dictionary<string,object>():BackupStrictJson.Report(Encode(Obj(envelope,"report")));
  var now=observe();CheckSnapshot(now);SameProcesses(Obj(snapshot,"processes"),Obj(now,"processes"));foreach(string k in new[]{"sessionWindowSha256","launchSha256","readySha256","mcpStartSha256"})Equal(now,k,S(snapshot,k));
  string errorCode=null;if(worker.Stderr.ByteCount>0){var err=BackupStrictJson.Parse(worker.Stderr.Bytes,4096);BackupStrictJson.Keys(err,"rejected code phase","");if(!BackupStrictJson.Bool(err,"rejected")||S(err,"code")!="runtime_backup_wrapper_rejected")throw new IOException("backup_stderr_rejected");errorCode=S(err,"code");}
  resultHash=Write("result",new {worker=Identity(worker),stdoutByteCount=worker.Stdout.ByteCount,stdoutSha256=worker.Stdout.Sha256,stderrByteCount=worker.Stderr.ByteCount,stderrSha256=worker.Stderr.Sha256,stderrCode=errorCode,stdoutEof=true,stderrEof=true,exitCode=worker.ExitCode,jobEmpty=true,wrapperSchema="i-core-backup-wrapper-result-v3",wrapperPassed=wrapperPassed,childCaptures=captures,originalResult=report,pruned=new{present=report.ContainsKey("pruned"),value=report.ContainsKey("pruned")?report["pruned"]:null,knowledge=report.ContainsKey("pruned")?"observed":"unknown"},retentionDays=new{present=report.ContainsKey("retentionDays"),value=report.ContainsKey("retentionDays")?report["retentionDays"]:null},crossComponentAtomic=false,activation_supported=false},workerHash);
  if(!wrapperPassed||worker.ExitCode!=0||worker.Stderr.ByteCount!=0||!BackupStrictJson.Bool(report,"verified"))throw new IOException("backup_report_failed");
  var effects=Obj(report,"effectEvidence");if(!BackupStrictJson.Bool(effects,"measurementComplete")||BackupStrictJson.Bool(effects,"partial")||BackupStrictJson.Bool(report,"mirrorPending"))throw new IOException("backup_effects_incomplete");
  if(failed)throw new IOException("backup_terminal_failed");Write("commit",new {intentSha256=intentHash,workerSha256=workerHash,resultSha256=resultHash,permitSha256=permitHash,durableReadback=true,detailDeliveryComplete=true,backupEvidenceComplete=false,productionCompletenessNotAttested=true},resultHash);
  if(failed)throw new IOException("backup_terminal_failed");if(attemptId==firstAttemptId){FirstAttemptComplete=true;FirstAttemptSuccessful=true;}attemptOpen=false;
 }
 static string SafeCode(Exception e){switch(e.Message){case "backup_p3_timeout":case "backup_worker_timeout":case "backup_delivery_incomplete":case "backup_effects_incomplete":case "backup_report_failed":return e.Message;default:return "backup_evidence_rejected";}}
 void LatchFailure(string code){
  failed=true;if(attemptId==firstAttemptId&&firstAttemptId!=null){FirstAttemptComplete=false;FirstAttemptSuccessful=false;}
  try{
   string name="backup-failure-"+Guid.NewGuid().ToString("N")+".json";
   BackupDurable.Write(Path.Combine(control,name),Encode(new {format="i-core-backup-failure-v1",code=code,firstAttemptId=firstAttemptId,attemptId=attemptId,attemptOpen=attemptOpen,worker=worker==null?null:Identity(worker),producer=producer==null?null:Identity(producer),workerExited=worker!=null&&worker.Exited,workerJobEmpty=worker!=null&&worker.Empty,retryAllowed=false,detailDeliveryComplete=false,createdUtc=DateTime.UtcNow.ToString("o")}));
  }catch{FailureReceiptUnavailable=true;}
 }
 public bool FailureReceiptUnavailable{get;private set;}
 public bool WaitEmpty(int milliseconds){RequestTerminal();var wait=Stopwatch.StartNew();if(!Monitor.TryEnter(terminalGate,Math.Max(0,milliseconds)))return false;try{return !Disposed&&FinishTerminal(Math.Max(0,milliseconds-(int)wait.ElapsedMilliseconds));}finally{Monitor.Exit(terminalGate);}}
 bool FinishTerminal(int milliseconds){var timer=Stopwatch.StartNew();do{if(Exited&&Empty&&CaptureComplete){if(!failed&&attemptOpen&&worker!=null){try{FinishAttempt();}catch(Exception e){LatchFailure(SafeCode(e));}}if(!Closed&&!failed)LatchFailure("backup_terminal_unverified");return Closed;}if(timer.ElapsedMilliseconds>=milliseconds)break;Thread.Sleep(10);}while(true);return false;}
 public void MarkIncomplete(){RequestTerminal();if(!Monitor.TryEnter(terminalGate,0)){failed=true;DisposalDeferred=true;return;}try{if(!Disposed&&!Closed)LatchFailure("backup_delivery_incomplete");}finally{Monitor.Exit(terminalGate);}}
 public void Dispose(){RequestTerminal();if(!Monitor.TryEnter(terminalGate,0)){DisposalDeferred=true;failed=true;return;}try{
   if(Disposed)return;try{WriteRecoveryState("dispose");}catch{FailureReceiptUnavailable=true;}
   if(!JobClosed(producer)||!JobClosed(worker)||!JobClosed(recovery)||!JobClosed(cleanup)){DisposalDeferred=true;failed=true;return;}
   if(recovery!=null)recovery.Dispose();if(cleanup!=null)cleanup.Dispose();if(producer!=null)producer.Dispose();if(worker!=null)worker.Dispose();foreach(var lease in leases)lease.Dispose();leases.Clear();Disposed=true;
  }finally{Monitor.Exit(terminalGate);}}

 // Recovery is a separately owned verifier. It never enters backup WaitEmpty.
 Schema6BackupJob recovery,cleanup;Dictionary<string,object> binding,boundPolicy,recoveryPolicy;
 bool policyLoaded,recoveryStarted,cleanupStarted,recoveryPassed,recoveryRetained,recoveryFailureObserved,recoveryWorkTerminated,cleanupDeliveryChecked,recoveryAcceptedAtReception;
 string initialSessionBindingHash,controlTransitionHash,recoveryStartHash,recoveryCompletionHash,recoveryFailureHash,recoveryHandoffHash,recoveryFinalDispositionHash,recoveryReceiverHash,recoveryReceiverCommitHash,recoveryReceiverRejectHash;
 object producerIdentity;string producerOutHash,producerErrHash;long producerOutCount;
 readonly Stopwatch phaseClock=Stopwatch.StartNew();
 public bool RecoveryCloseRequired{get;private set;}
 public bool RecoveryClosed{get{return (!recoveryStarted||(recoveryWorkTerminated&&recoveryReceiverCommitHash!=null&&recoveryReceiverRejectHash==null))&&JobClosed(recovery)&&JobClosed(cleanup);}}
 static bool JobClosed(Schema6BackupJob j){return j==null||j.PreparationEndedWithoutProcess||(j.Exited&&j.Empty&&CaptureClosed(j));}
 string Lifecycle(string name){return Path.Combine(release,"tools","i_core","release_schema6","lifecycle",name);}
 void CheckExpiry(){long now=(DateTime.UtcNow.Ticks-621355968000000000L)/10000;if(now<BackupStrictJson.Count(boundPolicy,"notBeforeUtcMs")||now>BackupStrictJson.Count(boundPolicy,"notAfterUtcMs"))throw new IOException("backup_approval_expired");}
 void CheckPhaseDeadline(){CheckExpiry();if(phaseClock.ElapsedMilliseconds>=30000)throw new IOException("backup_phase_timeout");}
 bool ResolvePhase(){
  CheckPhaseDeadline();
  string original=S(boundPolicy,"attemptId");if(!System.Text.RegularExpressions.Regex.IsMatch(original,"^[A-Za-z0-9_-]{1,96}$"))throw new IOException("backup_original_attempt");
  string root=Path.Combine(S(Obj(binding,"observation"),"activationRoot"),original);
  string path=Path.Combine(root,"03-initial-session-binding.json");
  BackupDurable.Lease ml;try{ml=Keep(path,null,65536);}catch(BackupPublicationOpenException error){if(error.TargetPath==path&&(error.NativeError==2||error.NativeError==32)){CheckPhaseDeadline();return false;}throw;}
  var m=BackupStrictJson.Parse(ml.Bytes,65536);
  BackupStrictJson.Keys(m,"format evidenceMode attemptId bindingSha256 approvalSha256 planSha256 instanceGuid sessionId sessionControlId sessionWindowSha256 launchSha256 readySha256 mcpStartSha256 activationClaimSha256 runReturnedSha256 activationStateSha256","");
  Equal(m,"format","i-core-initial-session-binding-v1");Equal(m,"evidenceMode","reviewed-live");Equal(m,"attemptId",original);Equal(m,"bindingSha256",bindingHash);Equal(m,"approvalSha256",approvalHash);Equal(m,"planSha256",planHash);
  foreach(string key in new[]{"sessionWindowSha256","launchSha256","readySha256","mcpStartSha256","activationClaimSha256","runReturnedSha256","activationStateSha256"})Hex(S(m,key));
  string[] names={"00-run-consumption.json","01-run-returned.json","02-enabled-state.json"};string[] keys={"activationClaimSha256","runReturnedSha256","activationStateSha256"};
  for(int i=0;i<3;i++){var doc=BackupStrictJson.Parse(Keep(Path.Combine(root,names[i]),S(m,keys[i]),262144).Bytes,262144);Equal(doc,"format",i==0?"i-core-activation-claim-v1":i==1?"i-core-run-returned-v1":"i-core-enabled-task-state-v1");if(i==0&&!BackupStrictJson.Bool(doc,"consumed")||i==1&&BackupStrictJson.Count(doc,"state")!=4||i==2&&!BackupStrictJson.Bool(doc,"enabled"))throw new IOException("backup_activation_facts");Equal(doc,"evidenceMode","reviewed-live");Equal(doc,"attemptId",original);Equal(doc,"approvalSha256",approvalHash);if(i!=1)Equal(doc,"planSha256",planHash);if(i==1){Equal(doc,"activationClaimSha256",S(m,"activationClaimSha256"));Equal(doc,"instanceGuid",S(m,"instanceGuid"));}}
  initialSessionBindingHash=ml.Hash;
  string transition=Path.Combine(control,"recovery-control-transition.json");
  if(recoveredControl){
   var tl=Keep(transition,null,65536);var t=BackupStrictJson.Parse(tl.Bytes,65536);
   BackupStrictJson.Keys(t,"format evidenceMode sessionId previousControlId controlId hostPid hostStartedTicks sessionWindowSha256 bindingSha256 approvalSha256 previousMcpEmpty previousMcpHandlesReleased previousBackupExited previousBackupEmpty previousBackupFailed createdUtc","");
   Equal(t,"format","i-core-control-recovery-transition-v1");Equal(t,"evidenceMode","reviewed-live");Equal(t,"sessionId",Path.GetFileName(session));Equal(t,"controlId",Path.GetFileName(control));Equal(t,"bindingSha256",bindingHash);Equal(t,"approvalSha256",approvalHash);
   if(S(t,"previousControlId")==Path.GetFileName(control)||!System.Text.RegularExpressions.Regex.IsMatch(S(t,"previousControlId"),"^control-[a-f0-9]{32}$"))throw new IOException("backup_control_transition");
   var host=Schema6BackupJob.GetIdentity(Process.GetCurrentProcess().Id);if(BackupStrictJson.Count(t,"hostPid")!=(long)host["pid"]||S(t,"hostStartedTicks")!=(string)host["startedTicks"])throw new IOException("backup_transition_host");
   if(!BackupStrictJson.Bool(t,"previousMcpEmpty")||!BackupStrictJson.Bool(t,"previousMcpHandlesReleased")||!BackupStrictJson.Bool(t,"previousBackupExited")||!BackupStrictJson.Bool(t,"previousBackupEmpty")||BackupStrictJson.Bool(t,"previousBackupFailed"))throw new IOException("backup_transition_unclosed");
   Equal(t,"sessionWindowSha256",Keep(Path.Combine(session,"session-window.json"),null,1048576).Hash);
   controlTransitionHash=tl.Hash;phase="host-control-recovery";
  }else{
   if(File.Exists(transition))throw new IOException("backup_unexpected_transition");
   if(S(m,"sessionId")==Path.GetFileName(session)){if(S(m,"sessionControlId")!=Path.GetFileName(control))throw new IOException("backup_unproven_control");phase="initial-activation";var now=observe();foreach(var key in new[]{"sessionWindowSha256","launchSha256","readySha256","mcpStartSha256"})Equal(m,key,S(now,key));}
   else phase="login-recovery";
  }
  if(phase!="initial-activation")LoadRecoveryPolicy();
  CheckPhaseDeadline();return true;
 }
 Dictionary<string,object> Artifact(string id,string role,string expectedHash,string exactPath,bool export){
  var list=binding.ContainsKey("artifacts")?binding["artifacts"] as List<object>:null;if(list==null)throw new IOException("backup_artifacts");
  Dictionary<string,object> found=null;foreach(var item in list){var d=item as Dictionary<string,object>;if(d!=null&&S(d,"id")==id){if(found!=null)throw new IOException("backup_artifact_duplicate");found=d;}}
  if(found==null)throw new IOException("backup_artifact_missing");Equal(found,"role",role);Equal(found,"sha256",expectedHash);if(!BackupStrictJson.Bool(found,"private"))throw new IOException("backup_artifact_private");
  if(export&&!BackupStrictJson.Bool(found,"exportJson"))throw new IOException("backup_artifact_export");
  if(exactPath!=null&&!S(found,"path").Equals(exactPath,StringComparison.OrdinalIgnoreCase))throw new IOException("backup_artifact_path");return found;
 }
 void LoadRecoveryPolicy(){
  Equal(policy,"format","backup-evidence-policy-v2");
  string entry=S(policy,"recoveryEntrySha256"),cleanupHash=S(policy,"recoveryCleanupSha256"),rp=S(policy,"recoveryPolicySha256");Hex(entry);Hex(cleanupHash);Hex(rp);
  Artifact("recovery_entrypoint","tool",entry,Lifecycle("recovery-p4-entry.ps1"),false);Artifact("recovery_cleanup","tool",cleanupHash,Lifecycle("recovery-p4-cleanup.ps1"),false);
  Keep(Lifecycle("recovery-p4-entry.ps1"),entry,1048576);Keep(Lifecycle("recovery-p4-cleanup.ps1"),cleanupHash,1048576);
  var a=Artifact("recovery_policy","identity_policy",rp,null,true);recoveryPolicy=BackupStrictJson.Parse(Keep(S(a,"path"),rp,65536).Bytes,65536);
  BackupStrictJson.Keys(recoveryPolicy,"format evidenceMode attemptId planSha256 allowedPhases namespaceVersion executeRecoveryP4 firstBackupOnly normalCloseBudgetMs coordinatorDeadlineMs","");
  Equal(recoveryPolicy,"format","i-core-recovery-p4-policy-v1");Equal(recoveryPolicy,"evidenceMode","reviewed-live");Equal(recoveryPolicy,"attemptId",S(boundPolicy,"attemptId"));Equal(recoveryPolicy,"planSha256",planHash);Equal(recoveryPolicy,"namespaceVersion","recovery-p4-evidence-namespace-v1");
  var phases=recoveryPolicy["allowedPhases"] as List<object>;var seen=new HashSet<string>();if(phases==null||phases.Count<1||phases.Count>2)throw new IOException("backup_recovery_phases");foreach(var p in phases){var x=p as string;if((x!="login-recovery"&&x!="host-control-recovery")||!seen.Add(x))throw new IOException("backup_recovery_phases");}
  if(!seen.Contains(phase)||!BackupStrictJson.Bool(recoveryPolicy,"executeRecoveryP4")||!BackupStrictJson.Bool(recoveryPolicy,"firstBackupOnly")||BackupStrictJson.Count(recoveryPolicy,"normalCloseBudgetMs")!=60000||BackupStrictJson.Count(recoveryPolicy,"coordinatorDeadlineMs")!=300000)throw new IOException("backup_recovery_policy");
 }
 string[] RecoveryArguments(string file){return new[]{"-NoProfile","-NonInteractive","-ExecutionPolicy","Bypass","-File",file,"-Execute","-BindingPath",bindingPath,"-ExpectedBindingSha256",bindingHash,"-ExpectedApprovalSha256",approvalHash,"-SessionDirectory",session,"-ControlDirectory",control,"-Phase",phase};}
 void StartRecovery(){
  if(phase=="initial-activation")return;if(recoveryStarted)throw new IOException("backup_recovery_once");recoveryStarted=true;
  try{
   recoveryStartHash=BackupDurable.Write(Path.Combine(control,"recovery-p4-start.json"),Encode(new{format="i-core-recovery-p4-start-v1",evidenceMode="reviewed-live",attemptId=S(boundPolicy,"attemptId"),phase=phase,sessionId=Path.GetFileName(session),controlId=Path.GetFileName(control),bindingSha256=bindingHash,approvalSha256=approvalHash,planSha256=planHash,permitSha256=permitHash,firstAttemptId=firstAttemptId,firstAttemptSha256=firstAttemptHash,intentSha256=intentHash,workerSha256=workerHash,recoveryEntrySha256=S(policy,"recoveryEntrySha256"),recoveryPolicySha256=S(policy,"recoveryPolicySha256"),initialSessionBindingSha256=initialSessionBindingHash,controlTransitionSha256=controlTransitionHash,producer=producerIdentity,producerExitCode=0,producerStdoutSha256=producerOutHash,producerStdoutByteCount=producerOutCount,producerStderrSha256=producerErrHash,producerStderrByteCount=0,producerStdoutEof=true,producerStderrEof=true,producerJobEmpty=true,backupResumed=true,createdUtc=DateTime.UtcNow.ToString("o")}));
   recovery=new Schema6BackupJob();recovery.Prepare(ps,RecoveryArguments(Lifecycle("recovery-p4-entry.ps1")),session,330000);CheckWorkerIdentity(recovery);
   try{recovery.Resume(null);}catch{RecoveryFailure("resume_failed");return;}
  }catch{RecoveryFailure("prepare_failed");}
 }

 void RecoveryTuple(Dictionary<string,object> d,bool plan){Equal(d,"evidenceMode","reviewed-live");Equal(d,"attemptId",S(boundPolicy,"attemptId"));Equal(d,"phase",phase);Equal(d,"sessionId",Path.GetFileName(session));Equal(d,"controlId",Path.GetFileName(control));Equal(d,"bindingSha256",bindingHash);Equal(d,"approvalSha256",approvalHash);if(plan)Equal(d,"planSha256",planHash);}
 static string MaybeHash(Dictionary<string,object> d,string key){if(!d.ContainsKey(key))throw new IOException("backup_final_schema");if(d[key]==null)return null;string hash=S(d,key);Hex(hash);return hash;}
 static void SameHash(Dictionary<string,object> d,string key,string expected){if(MaybeHash(d,key)!=expected)throw new IOException("backup_final_hash");}
 Dictionary<string,object> ReadFinal(string path,string hash,int max=1048576){Hex(hash);return BackupStrictJson.Parse(Keep(path,hash,max).Bytes,max);}
 void RequireAbsent(string path){try{Keep(path,null,1048576);}catch(BackupPublicationOpenException e){if(e.TargetPath==path&&e.NativeError==2)return;throw;}throw new IOException("backup_final_veto");}
 void FinalNamespace(Dictionary<string,object> d,bool required){if(!d.ContainsKey("evidenceNamespace"))throw new IOException("backup_final_namespace");if(d["evidenceNamespace"]==null){if(required)throw new IOException("backup_final_namespace");return;}ValidateRecoveryNamespace(Obj(d,"evidenceNamespace"));}
 Dictionary<string,object> ValidateDisposition(string path,string hash,string kind,string disposition,string candidateName,string candidateHash,string previousCommit,string handoff,bool namespaceRequired){
  var d=ReadFinal(path,hash);BackupStrictJson.Keys(d,"format kind disposition evidenceMode attemptId phase sessionId controlId bindingSha256 approvalSha256 planSha256 evidenceNamespace candidateName candidateSha256 previousCommitSha256 closeHandoffSha256 code utcMs elapsedMs budgetMs authoritative","");
  Equal(d,"format","evidence-final-disposition-v1");Equal(d,"kind",kind);Equal(d,"disposition",disposition);RecoveryTuple(d,true);Equal(d,"candidateName",candidateName);SameHash(d,"candidateSha256",candidateHash);SameHash(d,"previousCommitSha256",previousCommit);SameHash(d,"closeHandoffSha256",handoff);
  if(BackupStrictJson.Bool(d,"authoritative"))throw new IOException("backup_final_authority");FinalNamespace(d,namespaceRequired);if(kind=="cleanup"&&d["evidenceNamespace"]!=null)throw new IOException("backup_cleanup_namespace");
  long utc=BackupStrictJson.Count(d,"utcMs"),elapsed=BackupStrictJson.Count(d,"elapsedMs"),budget=BackupStrictJson.Count(d,"budgetMs");if(budget!=(kind=="total"?185000:300000)||utc>(DateTime.UtcNow.Ticks-621355968000000000L)/10000)throw new IOException("backup_final_time");
  if(disposition=="commit"){Equal(d,"code","committed");if(candidateHash==null||previousCommit!=null||handoff!=null||elapsed>=budget||utc<BackupStrictJson.Count(boundPolicy,"notBeforeUtcMs")||utc>BackupStrictJson.Count(boundPolicy,"notAfterUtcMs"))throw new IOException("backup_final_commit");}else if(String.IsNullOrEmpty(S(d,"code")))throw new IOException("backup_final_code");
  return d;
 }
 string ValidateHandoff(Schema6BackupJob job,bool isCleanup,string hash,string candidateHash){
  string prefix=isCleanup?"recovery-p4-cleanup":"recovery-p4";var h=ReadFinal(Path.Combine(control,prefix+"-close-handoff.json"),hash);
  BackupStrictJson.Keys(h,"format kind evidenceMode attemptId phase sessionId controlId bindingSha256 approvalSha256 planSha256 startSha256 failureSha256 candidateSha256 helperIdentity taskDisabled disabledAnchors closeOwner requestClose closed safeClosed createdUtc","");
  Equal(h,"format","recovery-p4-close-handoff-v1");Equal(h,"kind",isCleanup?"cleanup":"recovery");RecoveryTuple(h,true);Equal(h,"startSha256",recoveryStartHash);SameHash(h,"failureSha256",isCleanup?recoveryFailureHash:null);Equal(h,"candidateSha256",candidateHash);Equal(h,"closeOwner","session-host");
  if(!BackupStrictJson.Bool(h,"taskDisabled")||!BackupStrictJson.Bool(h,"requestClose")||BackupStrictJson.Bool(h,"closed")||BackupStrictJson.Bool(h,"safeClosed"))throw new IOException("backup_handoff_state");
  var id=Obj(h,"helperIdentity");BackupStrictJson.Keys(id,"pid startedTicks ownerSid sessionId imageSha256 parentPid hostStartedTicks","");var host=Schema6BackupJob.GetIdentity(Process.GetCurrentProcess().Id);
  if(BackupStrictJson.Count(id,"pid")!=job.Pid||S(id,"startedTicks")!=job.StartedTicks||S(id,"ownerSid")!=job.OwnerSid||BackupStrictJson.Count(id,"sessionId")!=job.SessionId||S(id,"imageSha256")!="8bb6fa8c283b4d92120b1ef249a9b311b0f804d4cabbe9981159976c8be76a5e"||BackupStrictJson.Count(id,"parentPid")!=Process.GetCurrentProcess().Id||S(id,"hostStartedTicks")!=(string)host["startedTicks"])throw new IOException("backup_handoff_identity");
  var anchors=Obj(h,"disabledAnchors");BackupStrictJson.Keys(anchors,"raw definition taskSddl parentSddl cmdlet","");foreach(string key in new[]{"raw","definition","taskSddl","parentSddl","cmdlet"}){string pin=S(anchors,key);Hex(pin);Keep(Path.Combine(control,prefix+"-disable-after-"+key+".actual.txt"),pin,1048576);}Equal(anchors,"cmdlet",S(anchors,"raw"));
  DateTime utc;if(!DateTime.TryParse(S(h,"createdUtc"),System.Globalization.CultureInfo.InvariantCulture,System.Globalization.DateTimeStyles.AdjustToUniversal,out utc)||utc.ToUniversalTime()>DateTime.UtcNow)throw new IOException("backup_handoff_time");
  long stamp=(utc.ToUniversalTime().Ticks-621355968000000000L)/10000;if(stamp<BackupStrictJson.Count(boundPolicy,"notBeforeUtcMs")||stamp>BackupStrictJson.Count(boundPolicy,"notAfterUtcMs"))throw new IOException("backup_handoff_approval_time");
  return hash;
 }
 void ValidateTotalFinal(Dictionary<string,object> c){
  var ns=Obj(c,"evidenceNamespace");ValidateRecoveryNamespace(ns);string dir=Path.Combine(S(binding,"outputRoot"),S(boundPolicy,"attemptId"),S(ns,"leaf"));
  string reportHash=MaybeHash(c,"gateReportSha256"),commit=MaybeHash(c,"totalCommitSha256"),receiver=MaybeHash(c,"totalReceiverSha256");
  if(reportHash==null||commit==null||receiver==null||MaybeHash(c,"totalRejectSha256")!=null||MaybeHash(c,"totalReceiverRejectSha256")!=null||S(c,"totalDisposition")!="commit"||S(c,"totalReceiverDisposition")!="commit")throw new IOException("backup_total_final_chain");
  RequireAbsent(Path.Combine(dir,"05-total-reject.json"));RequireAbsent(Path.Combine(dir,"07-total-receiver-reject.json"));
  var gate=ReadFinal(Path.Combine(dir,"03-total-result.json"),reportHash);
  BackupStrictJson.Keys(gate,"evidenceNamespace format recordKind authoritative evidenceMode attemptId phase approvalSha256 bindingSha256 planSha256 passed healthPassed backupPassed backupEvidenceComplete overallP4Passed originalPrunedKnowledge originalPrunedValue newEffectsVerified acceptanceMode code retryAllowed containmentRequired pendingWorkPreserved healthResult healthReceiptHashes firstAttemptSha256 backupReceiptHashes originalBackupResult effectEvidence","");
  Equal(gate,"format","p4-backup-total-result-v3");Equal(gate,"recordKind","candidate");if(BackupStrictJson.Bool(gate,"authoritative"))throw new IOException("backup_total_candidate_authority");Equal(gate,"evidenceMode","reviewed-live");Equal(gate,"attemptId",S(boundPolicy,"attemptId"));Equal(gate,"phase",phase);Equal(gate,"bindingSha256",bindingHash);Equal(gate,"approvalSha256",approvalHash);Equal(gate,"planSha256",planHash);Equal(gate,"firstAttemptSha256",firstAttemptHash);Equal(gate,"code","total_passed");ValidateRecoveryNamespace(Obj(gate,"evidenceNamespace"));
  foreach(string k in new[]{"passed","healthPassed","backupPassed","backupEvidenceComplete","overallP4Passed"})if(!BackupStrictJson.Bool(gate,k))throw new IOException("backup_total_candidate_failed");if(BackupStrictJson.Bool(gate,"retryAllowed")||BackupStrictJson.Bool(gate,"containmentRequired"))throw new IOException("backup_total_candidate_failed");
  ValidateDisposition(Path.Combine(dir,"04-total-commit.json"),commit,"total","commit","03-total-result.json",reportHash,null,null,true);
  var recv=ReadFinal(Path.Combine(dir,"06-total-receiver.json"),receiver);BackupStrictJson.Keys(recv,"format evidenceMode attemptId phase sessionId controlId bindingSha256 approvalSha256 planSha256 evidenceNamespace candidateSha256 commitSha256 rejectSha256 disposition passed authoritative utcMs","");
  Equal(recv,"format","p4-total-receiver-v1");RecoveryTuple(recv,true);FinalNamespace(recv,true);SameHash(recv,"candidateSha256",reportHash);SameHash(recv,"commitSha256",commit);SameHash(recv,"rejectSha256",null);Equal(recv,"disposition","commit");if(!BackupStrictJson.Bool(recv,"passed")||BackupStrictJson.Bool(recv,"authoritative"))throw new IOException("backup_total_receiver");long utc=BackupStrictJson.Count(recv,"utcMs");if(utc<BackupStrictJson.Count(boundPolicy,"notBeforeUtcMs")||utc>BackupStrictJson.Count(boundPolicy,"notAfterUtcMs")||utc>(DateTime.UtcNow.Ticks-621355968000000000L)/10000)throw new IOException("backup_total_receiver_time");
 }

 sealed class RecoveryDelivery {public bool Accepted;public string Kind,Completion,Commit,Reject,Handoff;}
 RecoveryDelivery ReadRecoveryDelivery(Schema6BackupJob job,bool isCleanup){
  if(!JobClosed(job))throw new IOException("backup_recovery_not_terminal");CaptureReady(job);if(job.Stderr.ByteCount!=0)throw new IOException("backup_recovery_stderr");
  string prefix=isCleanup?"recovery-p4-cleanup":"recovery-p4",kind=isCleanup?"cleanup":"recovery";
  var r=BackupStrictJson.Parse(job.Stdout.Bytes,65536);BackupStrictJson.Keys(r,"format passed completionSha256 commitSha256 rejectSha256 closeHandoffSha256 containmentAttempted containmentCompleted retained disposition code","");
  Equal(r,"format",isCleanup?"recovery-p4-cleanup-result-v2":"recovery-p4-entry-result-v2");if(BackupStrictJson.Bool(r,"containmentCompleted"))throw new IOException("backup_helper_closed_claim");
  var d=new RecoveryDelivery{Kind=kind,Completion=MaybeHash(r,"completionSha256"),Commit=MaybeHash(r,"commitSha256"),Reject=MaybeHash(r,"rejectSha256"),Handoff=MaybeHash(r,"closeHandoffSha256")};
  foreach(string key in new[]{"passed","containmentAttempted","containmentCompleted","retained"})BackupStrictJson.Bool(r,key);if(String.IsNullOrEmpty(S(r,"code")))throw new IOException("backup_recovery_result_code");
  string disposition=S(r,"disposition");if(disposition=="unknown"||d.Completion==null)throw new IOException("backup_recovery_unknown");
  var c=ReadFinal(Path.Combine(control,prefix+"-completion.json"),d.Completion);
  string totalKeys=" totalCommitSha256 totalRejectSha256 totalDisposition totalReceiverSha256 totalReceiverRejectSha256 totalReceiverDisposition";
  BackupStrictJson.Keys(c,(isCleanup?"format evidenceMode attemptId phase sessionId controlId bindingSha256 approvalSha256 planSha256 startSha256 failureSha256 evidenceNamespace passed containmentAttempted containmentCompleted retained taskDisabled closed safeClosed code completedUtc recordKind authoritative":"format evidenceMode attemptId phase sessionId controlId bindingSha256 approvalSha256 planSha256 startSha256 gateReportSha256 evidenceNamespace passed containmentAttempted containmentCompleted retained code completedUtc taskDisabled closed safeClosed recordKind authoritative")+totalKeys,"");
  Equal(c,"format",isCleanup?"recovery-p4-cleanup-completion-v2":"recovery-p4-completion-v2");Equal(c,"recordKind","candidate");RecoveryTuple(c,true);Equal(c,"startSha256",recoveryStartHash);if(isCleanup)Equal(c,"failureSha256",recoveryFailureHash);
  if(BackupStrictJson.Bool(c,"authoritative")||BackupStrictJson.Bool(c,"closed")||BackupStrictJson.Bool(c,"safeClosed")||BackupStrictJson.Bool(c,"containmentCompleted"))throw new IOException("backup_candidate_closed_claim");
  foreach(string key in new[]{"passed","containmentAttempted","containmentCompleted","retained","taskDisabled","closed","safeClosed","authoritative"})BackupStrictJson.Bool(c,key);foreach(string key in new[]{"totalCommitSha256","totalRejectSha256","totalReceiverSha256","totalReceiverRejectSha256"})MaybeHash(c,key);foreach(string key in new[]{"totalDisposition","totalReceiverDisposition"})if(S(c,key)!="commit"&&S(c,key)!="reject"&&S(c,key)!="unknown"&&S(c,key)!="not-run")throw new IOException("backup_total_disposition");if(String.IsNullOrEmpty(S(c,"code")))throw new IOException("backup_candidate_code");DateTime completed;if(!DateTime.TryParse(S(c,"completedUtc"),System.Globalization.CultureInfo.InvariantCulture,System.Globalization.DateTimeStyles.AdjustToUniversal,out completed)||completed.ToUniversalTime()>DateTime.UtcNow)throw new IOException("backup_candidate_time");
  FinalNamespace(c,false);if(isCleanup){if(c["evidenceNamespace"]!=null||MaybeHash(c,"totalCommitSha256")!=null||MaybeHash(c,"totalRejectSha256")!=null||MaybeHash(c,"totalReceiverSha256")!=null||MaybeHash(c,"totalReceiverRejectSha256")!=null||S(c,"totalDisposition")!="not-run"||S(c,"totalReceiverDisposition")!="not-run")throw new IOException("backup_cleanup_total");}
  if(disposition=="commit"){
   if(isCleanup||job.ExitCode!=0||!BackupStrictJson.Bool(r,"passed")||!BackupStrictJson.Bool(c,"passed")||BackupStrictJson.Bool(r,"retained")||BackupStrictJson.Bool(c,"retained")||BackupStrictJson.Bool(c,"taskDisabled")||d.Commit==null||d.Reject!=null||d.Handoff!=null)throw new IOException("backup_recovery_commit");
   foreach(string k in new[]{"containmentAttempted","containmentCompleted"})if(BackupStrictJson.Bool(r,k)||BackupStrictJson.Bool(c,k))throw new IOException("backup_recovery_commit_containment");
   RequireAbsent(Path.Combine(control,prefix+"-reject.json"));RequireAbsent(Path.Combine(control,prefix+"-close-handoff.json"));
   ValidateDisposition(Path.Combine(control,prefix+"-commit.json"),d.Commit,kind,"commit",prefix+"-completion.json",d.Completion,null,null,true);
   ValidateTotalFinal(c);CheckExpiry();if(job.Elapsed.ElapsedMilliseconds>=300000||failed||terminalRequested||!FirstAttemptSuccessful||!FirstAttemptComplete)throw new IOException("backup_recovery_final_admission");
   d.Accepted=true;
  }else if(disposition=="reject"){
   if(job.ExitCode!=2||BackupStrictJson.Bool(r,"passed")||d.Reject==null||d.Handoff==null||!BackupStrictJson.Bool(r,"containmentAttempted"))throw new IOException("backup_recovery_reject");
   if(d.Commit!=null)ValidateDisposition(Path.Combine(control,prefix+"-commit.json"),d.Commit,kind,"commit",prefix+"-completion.json",d.Completion,null,null,!isCleanup);
   else RequireAbsent(Path.Combine(control,prefix+"-commit.json"));
   var finalReject=ValidateDisposition(Path.Combine(control,prefix+"-reject.json"),d.Reject,kind,"reject",prefix+"-completion.json",d.Completion,d.Commit,d.Handoff,false);if((finalReject["evidenceNamespace"]==null)!=(c["evidenceNamespace"]==null))throw new IOException("backup_final_namespace_mismatch");
   ValidateHandoff(job,isCleanup,d.Handoff,d.Completion);d.Accepted=false;
  }else throw new IOException("backup_recovery_disposition");
  return d;
 }
 void GuardRecoveryReception(RecoveryDelivery d){
  if(!JobClosed(recovery)||!JobClosed(cleanup))throw new IOException("backup_recovery_not_terminal");
  if(d.Accepted){CheckExpiry();if(recovery.Elapsed.ElapsedMilliseconds>=300000||failed||terminalRequested||!FirstAttemptSuccessful||!FirstAttemptComplete)throw new IOException("backup_recovery_final_admission");RequireAbsent(Path.Combine(control,"recovery-p4-reject.json"));RequireAbsent(Path.Combine(control,"recovery-p4-close-handoff.json"));}
 }
 void PublishRecoveryReception(RecoveryDelivery d){
  GuardRecoveryReception(d);string commitHash=null;
  try{
   string receiver=BackupDurable.Write(Path.Combine(control,"recovery-p4-host-receiver.json"),Encode(new{format="i-core-recovery-p4-host-receiver-v1",evidenceMode="reviewed-live",attemptId=S(boundPolicy,"attemptId"),phase=phase,sessionId=Path.GetFileName(session),controlId=Path.GetFileName(control),bindingSha256=bindingHash,approvalSha256=approvalHash,planSha256=planHash,startSha256=recoveryStartHash,kind=d.Kind,acceptance=d.Accepted,authoritative=false,completionSha256=d.Completion,commitSha256=d.Commit,rejectSha256=d.Reject,closeHandoffSha256=d.Handoff,coordinator=RecoveryJobState(recovery),cleanup=RecoveryJobState(cleanup),createdUtc=DateTime.UtcNow.ToString("o")}));
   recoveryReceiverHash=receiver;GuardRecoveryReception(d);
   commitHash=BackupDurable.Write(Path.Combine(control,"recovery-p4-host-commit.json"),Encode(new{format="i-core-recovery-p4-host-disposition-v1",disposition="commit",evidenceMode="reviewed-live",attemptId=S(boundPolicy,"attemptId"),phase=phase,sessionId=Path.GetFileName(session),controlId=Path.GetFileName(control),bindingSha256=bindingHash,approvalSha256=approvalHash,planSha256=planHash,receiverSha256=receiver,acceptance=d.Accepted,physicalWorkTerminated=true,closeHandoffSha256=d.Handoff,hostExitConfirmed=false,createdUtc=DateTime.UtcNow.ToString("o")}));
   GuardRecoveryReception(d);recoveryReceiverCommitHash=commitHash;recoveryCompletionHash=d.Completion;recoveryHandoffHash=d.Handoff;recoveryFinalDispositionHash=d.Reject??d.Commit;recoveryPassed=d.Accepted&&!recoveryFailureObserved;recoveryAcceptedAtReception=recoveryPassed;recoveryWorkTerminated=true;recoveryRetained=false;RecoveryCloseRequired=!d.Accepted;
  }catch{
   recoveryPassed=false;recoveryRetained=true;recoveryWorkTerminated=false;RecoveryCloseRequired=false;
   try{recoveryReceiverRejectHash=BackupDurable.Write(Path.Combine(control,"recovery-p4-host-reject.json"),Encode(new{format="i-core-recovery-p4-host-disposition-v1",disposition="reject",evidenceMode="reviewed-live",attemptId=S(boundPolicy,"attemptId"),phase=phase,sessionId=Path.GetFileName(session),controlId=Path.GetFileName(control),bindingSha256=bindingHash,approvalSha256=approvalHash,planSha256=planHash,receiverSha256=recoveryReceiverHash,previousCommitSha256=commitHash,acceptance=false,physicalWorkTerminated=false,closeHandoffSha256=d.Handoff,hostExitConfirmed=false,code="receiver_final_rejected",createdUtc=DateTime.UtcNow.ToString("o")}));}catch{FailureReceiptUnavailable=true;}
   throw;
  }
 }
 void TickRecovery(){
  if(!recoveryStarted||recoveryWorkTerminated)return;
  if(!recoveryFailureObserved){
   try{
    if(failed||terminalRequested)throw new IOException("backup_recovery_terminal");
    if(recovery==null||recovery.Elapsed.ElapsedMilliseconds>=300000){RecoveryFailure("deadline");}
    else if(JobClosed(recovery)){var d=ReadRecoveryDelivery(recovery,false);if(!d.Accepted)recoveryFailureObserved=true;PublishRecoveryReception(d);return;}
   }catch{RecoveryFailure("coordinator_failed");}
  }
  if(cleanupStarted&&cleanup!=null&&!cleanupDeliveryChecked){
   try{
    if(cleanup.Elapsed.ElapsedMilliseconds>=300000){cleanupDeliveryChecked=true;recoveryRetained=true;return;}
    if(!JobClosed(cleanup)||!JobClosed(recovery))return;
    var d=ReadRecoveryDelivery(cleanup,true);if(d.Accepted)throw new IOException("backup_cleanup_accepted");cleanupDeliveryChecked=true;PublishRecoveryReception(d);
   }catch{cleanupDeliveryChecked=true;recoveryRetained=true;recoveryPassed=false;FailureReceiptUnavailable=true;}
  }
 }
 void RecoveryFailure(string code){
  recoveryPassed=false;recoveryRetained=true;RecoveryCloseRequired=false;if(recoveryFailureObserved)return;recoveryFailureObserved=true;
  try{
   string state=recovery==null||recovery.Pid==0?"not-created":!recovery.Resumed?"suspended":recovery.Exited?"exited":"running";
   recoveryFailureHash=BackupDurable.Write(Path.Combine(control,"recovery-p4-launch-failure.json"),Encode(new{format="i-core-recovery-p4-launch-failure-v1",evidenceMode="reviewed-live",phase=phase,sessionId=Path.GetFileName(session),controlId=Path.GetFileName(control),bindingSha256=bindingHash,approvalSha256=approvalHash,startSha256=recoveryStartHash,code=code,coordinator=recovery==null||recovery.Pid==0?null:Identity(recovery),coordinatorState=state,createdUtc=DateTime.UtcNow.ToString("o")}));
   if(recoveryStartHash!=null&&!cleanupStarted){cleanupStarted=true;cleanup=new Schema6BackupJob();cleanup.Prepare(ps,RecoveryArguments(Lifecycle("recovery-p4-cleanup.ps1")),session,330000);CheckWorkerIdentity(cleanup);cleanup.Resume(null);}
  }catch{FailureReceiptUnavailable=true;}
  try{WriteRecoveryState("failed");}catch{FailureReceiptUnavailable=true;}
 }

 object RecoveryJobState(Schema6BackupJob j){
  if(j==null)return null;
  bool exited=false,empty=false,captured=false;try{exited=j.Exited;empty=j.Empty;captured=CaptureClosed(j);}catch{}
  return new{identity=j.Pid==0?null:Identity(j),preparationEndedWithoutProcess=j.PreparationEndedWithoutProcess,exited=exited,jobEmpty=empty,captureComplete=captured,exitCode=exited?(object)j.ExitCode:null,stdoutEof=j.Stdout!=null&&j.Stdout.Eof,stderrEof=j.Stderr!=null&&j.Stderr.Eof,stdoutByteCount=j.Stdout==null?(object)null:j.Stdout.ByteCount,stdoutSha256=j.Stdout==null?null:j.Stdout.Sha256,stderrByteCount=j.Stderr==null?(object)null:j.Stderr.ByteCount,stderrSha256=j.Stderr==null?null:j.Stderr.Sha256,handlesHeld=j.HandlesHeld,prepareFailure=j.PrepareFailure};
 }
 public bool RecoveryAcceptance{get{return recoveryAcceptedAtReception;}}
 public bool RecoveryCurrentlyValid{get{return recoveryAcceptedAtReception&&!recoveryFailureObserved&&!failed&&!terminalRequested;}}
 public object RecoveryFinalReferences{get{return new{receiverSha256=recoveryReceiverHash,receiverCommitSha256=recoveryReceiverCommitHash,receiverRejectSha256=recoveryReceiverRejectHash,finalDispositionSha256=recoveryFinalDispositionHash,closeHandoffSha256=recoveryHandoffHash,hostExitConfirmed=false};}}
 public object RecoveryState{get{return new{started=recoveryStarted,passed=RecoveryAcceptance,acceptedAtReception=RecoveryAcceptance,currentAcceptanceValid=RecoveryCurrentlyValid,backupCurrentlyFailed=failed,terminalRequested=terminalRequested,rejected=recoveryFailureObserved,retained=recoveryRetained||failed,safeClosed=false,coordinatorClosed=RecoveryClosed,physicalWorkTerminated=recoveryWorkTerminated,taskDisabledVerified=recoveryHandoffHash!=null,manualInterventionRequired=!RecoveryClosed,completionSha256=recoveryCompletionHash,finalReferences=RecoveryFinalReferences,coordinator=RecoveryJobState(recovery),cleanup=RecoveryJobState(cleanup)};}}
 public void WriteRecoveryState(string reason){if(recoveryStarted)BackupDurable.Write(Path.Combine(control,"recovery-p4-host-"+reason+"-"+Guid.NewGuid().ToString("N")+".json"),Encode(new{format="i-core-recovery-p4-host-state-v1",evidenceMode="reviewed-live",sessionId=Path.GetFileName(session),controlId=Path.GetFileName(control),reason=reason,state=RecoveryState,createdUtc=DateTime.UtcNow.ToString("o")}));}

 int terminalPublished;
 public void RequestTerminal(){
  terminalRequested=true;if(Interlocked.CompareExchange(ref terminalPublished,1,0)!=0)return;
  try{BackupDurable.Write(Path.Combine(control,"backup-terminal-requested.json"),Encode(new{format="i-core-backup-terminal-v1",evidenceMode="reviewed-live",bindingSha256=bindingHash,approvalSha256=approvalHash,sessionId=Path.GetFileName(session),controlId=Path.GetFileName(control),phase=phase,failed=failed,createdUtc=DateTime.UtcNow.ToString("o")}));}
  catch{failed=true;FailureReceiptUnavailable=true;}
 }
 void ValidateRecoveryNamespace(Dictionary<string,object> ns){
BackupStrictJson.Keys(ns,"version phase sessionId controlId leaf recoveryPolicySha256 startSha256 permitSha256 firstAttemptId firstAttemptSha256","");
   string sid=Path.GetFileName(session),cid=Path.GetFileName(control);if(!System.Text.RegularExpressions.Regex.IsMatch(sid,"^session-[a-f0-9]{32}$")||!System.Text.RegularExpressions.Regex.IsMatch(cid,"^control-[a-f0-9]{32}$"))throw new IOException("backup_recovery_tuple");
   string leaf="recovery-p4-v1--"+phase+"--"+sid+"--"+cid;
   Equal(ns,"version","recovery-p4-evidence-namespace-v1");Equal(ns,"phase",phase);Equal(ns,"sessionId",sid);Equal(ns,"controlId",cid);Equal(ns,"leaf",leaf);Equal(ns,"recoveryPolicySha256",S(policy,"recoveryPolicySha256"));Equal(ns,"startSha256",recoveryStartHash);Equal(ns,"permitSha256",permitHash);Equal(ns,"firstAttemptId",firstAttemptId);Equal(ns,"firstAttemptSha256",firstAttemptHash);

 }
}
