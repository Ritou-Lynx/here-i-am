import {createHash,randomUUID} from 'node:crypto';
import {spawn} from 'node:child_process';
import {mkdirSync,writeFileSync,openSync,closeSync,fsyncSync,readFileSync,existsSync,unlinkSync,rmdirSync} from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {backupFilePrimitives as f} from './backup_bundle.mjs';
import {cleanEnvironment} from './package.mjs';
import {observeDueCustodyInventory,assertUnchanged} from './custody_inventory.mjs';
export const APPROVED_TASKS=Object.freeze([{"taskPath":"\\","taskName":"HereIAm-iCoreSchema6-cleanclose-20261008-2c01de5b"},{"taskPath":"\\","taskName":"HereIAm-iCoreSchema6-chatgpt-20261009-f90058f2"}]);
const TASK_KEYS=['raw','definition','taskSddl','parentSddl','cmdlet'],HASH=/^[a-f0-9]{64}$/;
const TASK_LIMIT=1024*1024,ALL_TASK_LIMIT=10*1024*1024;
const sha=b=>createHash('sha256').update(b).digest('hex');
const fail=code=>{throw Object.assign(new Error(code),{code});};
const exact=(v,keys)=>v&&typeof v==='object'&&!Array.isArray(v)&&JSON.stringify(Object.keys(v).sort())===JSON.stringify([...keys].sort());
const equal=(a,b)=>JSON.stringify(a)===JSON.stringify(b);
const canonical=p=>typeof p==='string'&&path.isAbsolute(p)&&path.normalize(p)===p&&!p.includes(':',2)&&!p.includes('\0');
const retainedExports=new Set();
export function validateDueInventoryPolicy(value,spec){
 if(!exact(value,['format','custodyDirectory','tasks'])||value.format!=='i-core-due-inventory-v1'||!canonical(value.custodyDirectory))fail('due_inventory_policy');
 if(!Array.isArray(value.tasks)||value.tasks.length!==2)fail('due_task_scope');
 for(let i=0;i<2;i++)if(!exact(value.tasks[i],['taskPath','taskName'])||value.tasks[i].taskPath!==APPROVED_TASKS[i].taskPath||value.tasks[i].taskName!==APPROVED_TASKS[i].taskName)fail('due_task_scope');
 f.validate(spec);
 const anchors=spec.entries.filter(e=>e.role==='recovery_custody'&&path.basename(e.source_path)==='current-head.json');
 if(anchors.length!==1||path.dirname(anchors[0].source_path).toLowerCase()!==value.custodyDirectory.toLowerCase())fail('due_custody_scope');
 return value;
}
function privateDirectory(p){if(existsSync(p))fail('due_fresh_required');mkdirSync(p,{mode:0o700});f.protect(p);f.safe(p,true);}
function writePrivate(p,bytes){const fd=openSync(p,'wx',0o600);try{writeFileSync(fd,bytes);fsyncSync(fd);}finally{closeSync(fd);}f.safe(p);return sha(bytes);}
export function exportApprovedTasks(request){
 const {tasks,requestNonce}=request;
 if(!Array.isArray(tasks)||tasks.length!==2||tasks.some((t,i)=>t.taskPath!==APPROVED_TASKS[i].taskPath||t.taskName!==APPROVED_TASKS[i].taskName)||typeof requestNonce!=='string'||!/^[a-f0-9-]{36}$/.test(requestNonce))fail('due_task_scope');
 const executable='C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe';
 if(sha(readFileSync(executable))!=='8bb6fa8c283b4d92120b1ef249a9b311b0f804d4cabbe9981159976c8be76a5e')fail('due_task_runtime');
 const adapter=fileURLToPath(new URL('./export_backup_tasks.ps1',import.meta.url));
 return new Promise((resolve,reject)=>{
  const child=spawn(executable,['-NoProfile','-NonInteractive','-WindowStyle','Hidden','-ExecutionPolicy','Bypass','-File',adapter,'-Execute'],{windowsHide:true,env:cleanEnvironment(),stdio:['pipe','pipe','pipe']});
  const chunks=[];let count=0,errCount=0,ended=false,rejected=false,inputDone=false,inputFailed=false,outEof=false,errEof=false,exit=null;
  retainedExports.add(child);
  const rejectOnce=code=>{if(!rejected){rejected=true;reject(Object.assign(new Error(code),{code}));}for(const c of chunks)c.fill(0);chunks.length=0;};
  const timer=setTimeout(()=>rejectOnce('due_task_export_timeout'),15000);
  child.stdin.on('error',()=>{inputFailed=true;rejectOnce('due_task_export_input');});
  child.stdin.end(JSON.stringify({format:'i-core-backup-task-export-request-v1',requestNonce,tasks}),()=>{inputDone=true;});
  child.stdout.on('data',c=>{count+=c.length;if(count>16*1024*1024)rejectOnce('due_task_export_limit');else if(!rejected)chunks.push(Buffer.from(c));});
  child.stderr.on('data',c=>{errCount+=c.length;if(errCount)rejectOnce('due_task_export_stderr');});
  child.stdout.on('end',()=>{outEof=true;});child.stderr.on('end',()=>{errEof=true;});
  child.on('error',()=>rejectOnce('due_task_export_spawn'));
  child.on('exit',code=>{exit=code;});
  child.on('close',()=>{
   clearTimeout(timer);retainedExports.delete(child);ended=true;
   if(rejected)return;
   if(exit!==0||!outEof||!errEof||!inputDone||inputFailed||errCount){rejectOnce('due_task_export_terminal');return;}
   const bytes=Buffer.concat(chunks);try{const v=JSON.parse(bytes.toString('utf8'));resolve(v);}catch{rejectOnce('due_task_export_json');}finally{bytes.fill(0);for(const c of chunks)c.fill(0);}
  });
  // Deadline/overflow never kills or detaches the exporter. Its handles remain
  // referenced and drained; inherited owned-Job membership keeps host closure strict.
 });
}
function validateTaskObservation(value,tasks,requestNonce,notBefore){
 if(!exact(value,['format','requestNonce','capturedUtcMs','tasks'])||value.format!=='i-core-backup-task-export-v1'||value.requestNonce!==requestNonce||!Number.isSafeInteger(value.capturedUtcMs)||value.capturedUtcMs<notBefore||value.capturedUtcMs>Date.now()||!Array.isArray(value.tasks)||value.tasks.length!==2)fail('due_task_observation');
 let total=0;const entries=[];
 for(let i=0;i<2;i++){
  const item=value.tasks[i],expected=tasks[i];
  if(!exact(item,['taskPath','taskName','actualPath','files'])||item.taskPath!==expected.taskPath||item.taskName!==expected.taskName||item.actualPath!==expected.taskPath+expected.taskName||!exact(item.files,TASK_KEYS))fail('due_task_identity');
  const files={};
  for(const key of TASK_KEYS){
   const x=item.files[key];if(!exact(x,['bytes','sha256','base64'])||!Number.isSafeInteger(x.bytes)||x.bytes<1||x.bytes>TASK_LIMIT||!HASH.test(x.sha256??'')||typeof x.base64!=='string'||x.base64.length>Math.ceil(TASK_LIMIT/3)*4)fail('due_task_bytes');
   const bytes=Buffer.from(x.base64,'base64');if(bytes.length!==x.bytes||bytes.toString('base64')!==x.base64||sha(bytes)!==x.sha256||(total+=bytes.length)>ALL_TASK_LIMIT)fail('due_task_bytes');
   files[key]={bytes,sha256:x.sha256};
  }
  if(files.raw.sha256!==files.cmdlet.sha256)fail('due_task_export_disagrees');
  entries.push({taskPath:item.taskPath,taskName:item.taskName,actualPath:item.actualPath,files});
 }
 return {capturedUtcMs:value.capturedUtcMs,entries};
}
function taskVector(obs){return obs.entries.map(e=>({taskPath:e.taskPath,taskName:e.taskName,actualPath:e.actualPath,files:Object.fromEntries(TASK_KEYS.map(k=>[k,e.files[k].sha256]))}));}
export async function prepareDueInventory({specTemplate,dynamicInventory,outputRoot},taskExporter=exportApprovedTasks){
 validateDueInventoryPolicy(dynamicInventory,specTemplate);f.safe(outputRoot,true);
 const scratch=path.join(outputRoot,'.due-inventory-'+randomUUID());privateDirectory(scratch);
 const created=[];let original,observed,checked=false,closed=false;
 const write=(name,bytes)=>{const p=path.join(scratch,name);const hash=writePrivate(p,bytes);created.push(p);return {p,hash};};
 const failure=(code,newSuccessReceiptPublished=false)=>{try{writePrivate(path.join(outputRoot,'.due-inventory-failure-'+randomUUID()+'.json'),Buffer.from(JSON.stringify({format:'i-core-due-inventory-failure-v1',code:/^[a-z_]+$/.test(code??'')?code:'due_inventory_failed',newSuccessReceiptPublished,scratchDirectory:scratch,crossComponentAtomic:false,failedUtcMs:Date.now()})));}catch{}};
 try{
  original=observeDueCustodyInventory({specTemplate,custodyDirectory:dynamicInventory.custodyDirectory});
  const firstNonce=randomUUID(),firstStarted=Date.now();
  observed=validateTaskObservation(await taskExporter({tasks:dynamicInventory.tasks,requestNonce:firstNonce}),dynamicInventory.tasks,firstNonce,firstStarted);
  const spec=original.spec;
  for(let i=0;i<observed.entries.length;i++)for(const key of TASK_KEYS){
   const bytes=observed.entries[i].files[key].bytes,item=write('task-'+i+'-'+key+'.txt',bytes);
   spec.entries.push({role:'task',name:'due-task-export/task-'+i+'/'+key+'.txt',source_path:item.p,sha256:item.hash});
  }
  const provenance={format:'i-core-due-inventory-observation-v1',capturedUtcMs:observed.capturedUtcMs,custody:original.sourceVector,tasks:taskVector(observed),crossComponentAtomic:false,activationAuthority:false};
  const meta=write('observation.json',Buffer.from(JSON.stringify(provenance)));spec.entries.push({role:'configuration',name:'due-inventory/observation.json',source_path:meta.p,sha256:meta.hash});
  f.validate(spec);assertUnchanged(original.sourceVector);
  return {
   specTemplate:spec,
   async assertAfter(){
    if(closed||checked)fail('due_inventory_once');
    assertUnchanged(original.sourceVector);
    const nextNonce=randomUUID(),nextStarted=Date.now();
    const after=validateTaskObservation(await taskExporter({tasks:dynamicInventory.tasks,requestNonce:nextNonce}),dynamicInventory.tasks,nextNonce,nextStarted);
    if(after.capturedUtcMs<observed.capturedUtcMs||!equal(taskVector(after),taskVector(observed)))fail('due_task_changed');
    assertUnchanged(original.sourceVector);
    for(const file of spec.entries.filter(e=>e.name.startsWith('due-task-export/')||e.name==='due-inventory/observation.json'))if(f.readStable(file.source_path).sha256!==file.sha256)fail('due_attachment_changed');
    checked=true;
   },
   fail(code,newSuccessReceiptPublished=false){failure(code,newSuccessReceiptPublished);},
   release(){
    if(closed||!checked)fail('due_inventory_not_committed');closed=true;
    for(const p of created){f.safe(p);unlinkSync(p);}f.safe(scratch,true);rmdirSync(scratch);
   },
   get checked(){return checked;}
  };
 }catch(e){failure(e.code);throw e;}
}
