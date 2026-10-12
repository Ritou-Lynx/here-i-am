#!/usr/bin/env node
// C1: anchored config/source reads only; no database, credential or service reads.
import path from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';
import {existsSync,lstatSync,mkdirSync,openSync,closeSync,writeFileSync,fsyncSync,readFileSync,readdirSync} from 'node:fs';
import {execFileSync} from 'node:child_process';
import {sha256,plainPath,cleanEnvironment} from '../release_schema6/package.mjs';
import {backupFilePrimitives as f} from '../release_schema6/backup_bundle.mjs';
import {backupMapping,buildMcpSwitchBackup,PRESERVED_PREFIX,same} from './mcp-config-switch-bindings.mjs';

const here=path.dirname(fileURLToPath(import.meta.url));
const need=(condition,code)=>{if(!condition)throw new Error(code);};
const object=v=>v!==null&&typeof v==='object'&&!Array.isArray(v);
const hex=v=>typeof v==='string'&&/^[a-f0-9]{64}$/.test(v);
function absolute(p){need(typeof p==='string'&&path.isAbsolute(p)&&path.normalize(p)===p&&!p.includes(':',2)&&!/[\0\r\n"]/.test(p),'canonical_plain_path_required');plainPath(p,{missing:true});return p;}
function separate(a,b){absolute(a);absolute(b);const key=p=>process.platform==='win32'?p.toLowerCase():p;const nested=(a,b)=>{const r=path.relative(key(a),key(b));return r===''||(!path.isAbsolute(r)&&r!=='..'&&!r.startsWith('..'+path.sep));};need(!nested(a,b)&&!nested(b,a),'directory_overlap');}
function read(p,hash,max=8*1024*1024){absolute(p);f.safe(p);const bytes=f.small(p,max);if(hash!==undefined)need(hex(hash)&&sha256(bytes)===hash,'configuration_hash_mismatch');return {path:p,sha256:sha256(bytes),text:bytes.toString('utf8'),bytes};}
function json(ref){return JSON.parse(ref.text.replace(/^\uFEFF/,''));}
function sourceName(n){need(typeof n==='string'&&/^[A-Za-z0-9_./-]+$/.test(n)&&n.split('/').every(s=>s&&s!=='.'&&s!=='..'),'candidate_source_name_invalid');return n;}
function inventory(root,relative=''){f.safe(path.join(root,relative),true);return readdirSync(path.join(root,relative),{withFileTypes:true}).flatMap(e=>{const name=relative?relative+'/'+e.name:e.name;sourceName(name);if(e.isDirectory())return inventory(root,name);f.safe(path.join(root,name));need(e.isFile(),'candidate_file_required');return [name];}).sort();}

// Replace just top-level JSON value spans. Every other byte (including key order,
// whitespace, escapes and numeric spelling) survives unchanged.
export function replaceJsonFields(text,changes){
 const bom=text.startsWith('\uFEFF')?'\uFEFF':'';if(bom)text=text.slice(1);
 JSON.parse(text);const spans=new Map();let i=0;
 const ws=()=>{while(/\s/.test(text[i]??'')&&i<text.length)i++;};
 const string=()=>{const start=i++;while(i<text.length){if(text[i]==='\\'){i+=2;continue;}if(text[i++]==='"')return text.slice(start,i);}throw new Error('json_string_unclosed');};
 ws();need(text[i++]==='{','json_object_required');ws();
 while(text[i]!=='}'){
  need(text[i]==='"','json_key_required');const key=JSON.parse(string());need(!spans.has(key),'duplicate_json_key');ws();need(text[i++]===':','json_colon_required');ws();const start=i;let depth=0;
  while(i<text.length){const c=text[i];if(c==='"'){string();continue;}if(c==='['||c==='{'){depth++;i++;continue;}if(c===']'||c==='}'){if(depth===0)break;depth--;i++;continue;}if(c===','&&depth===0)break;i++;}
  let end=i;while(end>start&&/\s/.test(text[end-1]))end--;spans.set(key,{start,end});ws();if(text[i]===','){i++;ws();}else break;
 }
 need(text[i]==='}','json_object_end_required');
 for(const key of Object.keys(changes))need(spans.has(key),'json_field_missing:'+key);
 for(const [key,{start,end}] of [...spans].sort((a,b)=>b[1].start-a[1].start)){if(Object.hasOwn(changes,key))text=text.slice(0,start)+JSON.stringify(changes[key]).replace(/[\u007f-\uffff]/g,c=>'\\u'+c.charCodeAt(0).toString(16).padStart(4,'0'))+text.slice(end);}
 return bom+text;
}
export function fieldDiff(before,after,prefix=''){
 if(same(before,after))return [];
 if(object(before)&&object(after))return [...new Set([...Object.keys(before),...Object.keys(after)])].sort().flatMap(k=>fieldDiff(before[k],after[k],prefix?prefix+'.'+k:k));
 return [prefix];
}
function assertDiff(before,after,allowed){const diff=fieldDiff(before,after);need(diff.every(p=>allowed.includes(p)),'unexpected_field_delta');return diff;}
function event(step,body,emit){try{const result=body();emit({step,ok:true,detail:'completed'});return result;}catch(e){emit({step,ok:false,detail:e.message});throw e;}}
export function windowsTaskBridge(request){
 need(process.platform==='win32','windows_task_bridge_required');
 const ps=path.join(process.env.SystemRoot,'System32/WindowsPowerShell/v1.0/powershell.exe');
 let raw;
 try{raw=execFileSync(ps,['-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',path.join(here,'update-mcp-source-task.ps1')],{input:JSON.stringify(request),encoding:'utf8',env:cleanEnvironment(),windowsHide:true,maxBuffer:8*1024*1024,timeout:120000});}
 catch(e){raw=e.stdout?.toString()??'';if(raw)process.stdout.write(raw);throw new Error(raw.trim().split(/\r?\n/).filter(Boolean).map(line=>{try{return JSON.parse(line);}catch{return null;}}).findLast(r=>r?.ok===false)?.detail??e.message);}
 const rows=raw.trim().split(/\r?\n/).filter(Boolean).map(line=>JSON.parse(line));
 for(const row of rows)if(row.step!=='update.task.result')process.stdout.write(JSON.stringify(row)+'\n');
 const result=rows.findLast(r=>r.step==='update.task.result');need(result?.ok===true,'task_bridge_result_missing');return result.result;
}
function posixWriteBundle({out,files}){
 f.safe(path.dirname(out),true);absolute(out);need(!existsSync(out),'output_directory_exists');mkdirSync(out,{mode:0o700});f.protect(out);
 for(const file of files){const p=path.join(out,file.name);absolute(p);const fd=openSync(p,'wx',0o600);try{writeFileSync(fd,file.text);fsyncSync(fd);}finally{closeSync(fd);}f.safe(p);}
}
function mappingFor(old,from,to,manifest,candidate){
 // Reuse role/preservation mapping, adapting its historical tools/ source prefix
 // to the exact inventory of the running MCP (C1 preserves entrypoint).
 const map=backupMapping(old,from,to,{...manifest,files:[]},candidate);
 for(const e of manifest.files){const one=backupMapping(old,from,to,{files:[e]},candidate);const item=one.get(path.join(old.working_directory,'tools/'+e.path));item.oldSha256=old.source_files.find(s=>s.path===e.path).sha256;item.preserved='runtime/'+e.path;map.set(path.join(old.working_directory,e.path),item);}
 for(const role of ['backup','login','task'])map.get(from[role].path).sha256=undefined;
 return map;
}
function backupUpdate(original,map,tag){
 f.validate(original.specTemplate);
 // Existing preservation history remains at its original positions. The imported
 // helper owns the actual replacement and source preservation semantics.
 const history=original.specTemplate.entries.filter(e=>e.name.startsWith('preserved/'));
 const active=original.specTemplate.entries.filter(e=>!e.name.startsWith('preserved/'));
 const view={...original,specTemplate:{...original.specTemplate,entries:active}};
 const next=buildMcpSwitchBackup(view,map);
 const replacements=new Map(next.specTemplate.entries.slice(0,active.length).map(e=>[e.name,e]));
 const added=next.specTemplate.entries.slice(active.length).map(e=>({...e,name:'preserved/mcp-source-update/'+tag+'/'+e.name.slice(PRESERVED_PREFIX.length)}));
 next.specTemplate.entries=original.specTemplate.entries.map(e=>replacements.get(e.name)??e).concat(added);
 need(history.every(e=>same(next.specTemplate.entries.find(n=>n.name===e.name),e)),'backup_history_changed');f.validate(next.specTemplate);return next;
}

export function updateMcpSource({fromTask,candidateDirectory,outputDirectory,newTask,dryRun=false},{taskBridge=windowsTaskBridge,writeBundle,emit=()=>{}}={}){
 need(typeof dryRun==='boolean','dry_run_boolean_required');
 for(const name of [fromTask,newTask])need(typeof name==='string'&&/^[A-Za-z0-9][A-Za-z0-9_.-]{0,180}$/.test(name),'task_name_invalid');
 need(fromTask.toLowerCase()!==newTask.toLowerCase(),'two_distinct_tasks_required');
 const source=event('update.read_task',()=>taskBridge({operation:'read',fromTask,newTask}),emit);
 const plan=event('update.validate',()=>{
  absolute(candidateDirectory);absolute(outputDirectory);f.safe(path.dirname(outputDirectory),true);need(!existsSync(outputDirectory),'output_directory_exists');
  const loginRef=read(source.loginPath,source.loginSha256),login=json(loginRef);
  need(login.format==='schema6-login-v1','login_format_invalid');
  const mcpRef=read(login.mcp_configuration_path,login.mcp_configuration_sha256),backupRef=read(login.backup_configuration_path,login.backup_configuration_sha256);
  const old=json(mcpRef),backup=json(backupRef);need(old.format==='schema6-mcp-v1'&&old.owner_sid===login.owner_sid,'mcp_binding_invalid');
  need(old.database_path===path.join(login.state_directory,'i-core.sqlite'),'mcp_database_binding_invalid');
  const manifestRef=read(path.join(candidateDirectory,'manifest.json')),manifest=json(manifestRef),runtimeDirectory=path.join(candidateDirectory,'runtime');
  need(Array.isArray(old.source_files)&&old.source_files.length===6&&Array.isArray(manifest.files)&&manifest.files.length===6,'six_source_files_required');
  const names=old.source_files.map(e=>sourceName(e.path));need(new Set(names).size===6,'source_inventory_duplicate');
  need(same([...names].sort(),manifest.files.map(e=>sourceName(e.path)).sort())&&same([...names].sort(),inventory(runtimeDirectory)),'candidate_inventory_mismatch');
  need(manifest.entry===old.entrypoint&&names.includes(old.entrypoint),'candidate_entrypoint_mismatch');
  for(const p of [old.working_directory,login.state_directory,login.control_root]){separate(candidateDirectory,p);separate(outputDirectory,p);}
  separate(outputDirectory,candidateDirectory);
  for(const p of [login.backup_key_directory,old.environment?.I_REMOTE_MCP_STATE_DIR,old.environment?.I_HOME,backup.policy?.outputRoot,backup.policy?.mirrorRoot])if(p){separate(outputDirectory,p);separate(candidateDirectory,p);}
  for(const p of [source.loginPath,mcpRef.path,backupRef.path,login.core_configuration_path,old.environment?.I_MEMORY_DB,old.environment?.I_MEMORY_POLICY,backup.envelopePath])if(p){separate(outputDirectory,p);separate(candidateDirectory,p);}
  for(const e of manifest.files){need(hex(e.result_sha256),'candidate_hash_invalid');read(path.join(runtimeDirectory,e.path),e.result_sha256,16*1024*1024);}
  for(const e of old.source_files)read(path.join(old.working_directory,e.path),e.sha256,16*1024*1024);
  f.validate(backup.specTemplate);
  const tasks=backup.specTemplate.entries.filter(e=>e.role==='task'&&!e.name.startsWith('preserved/'));need(tasks.length===1,'backup_task_attachment_required');
  const from={mcp:mcpRef,backup:backupRef,login:loginRef,task:{path:tasks[0].source_path,sha256:tasks[0].sha256}};
  const to=Object.fromEntries(Object.entries({mcp:'mcp.json',backup:'daily-backup-config.json',login:'login.json',task:'login-task.xml'}).map(([role,name])=>[role,{path:path.join(outputDirectory,name)}]));
  const nextMcpText=replaceJsonFields(mcpRef.text,{working_directory:runtimeDirectory,source_files:manifest.files.map(e=>({path:e.path,sha256:e.result_sha256}))});
  const nextMcp=JSON.parse(nextMcpText.replace(/^\uFEFF/,''));to.mcp.sha256=sha256(Buffer.from(nextMcpText));
  const candidate={runtimeDirectory},map=mappingFor(old,from,to,manifest,candidate);
  const nextBackup=backupUpdate(backup,map,sha256(Buffer.from(loginRef.sha256+manifestRef.sha256)).slice(0,20));
  const nextBackupText=replaceJsonFields(backupRef.text,{specTemplate:nextBackup.specTemplate});to.backup.sha256=sha256(Buffer.from(nextBackupText));
  const nextLoginText=replaceJsonFields(loginRef.text,{mcp_configuration_path:to.mcp.path,mcp_configuration_sha256:to.mcp.sha256,backup_configuration_path:to.backup.path,backup_configuration_sha256:to.backup.sha256});
  const nextLogin=JSON.parse(nextLoginText.replace(/^\uFEFF/,''));to.login.sha256=sha256(Buffer.from(nextLoginText));
  const diff={mcp:assertDiff(old,nextMcp,['working_directory','source_files']),backup:assertDiff(backup,nextBackup,['specTemplate.entries']),login:assertDiff(login,nextLogin,['mcp_configuration_path','mcp_configuration_sha256','backup_configuration_path','backup_configuration_sha256'])};
  // All unchanged backup entries keep their exact values, including keys/custody.
  for(const e of backup.specTemplate.entries)if(!map.has(e.source_path))need(same(e,nextBackup.specTemplate.entries.find(n=>n.name===e.name)),'unrelated_backup_attachment_changed');
  const checked=taskBridge({operation:'check',fromTask,newTask,source,loginPath:to.login.path,loginSha256:to.login.sha256});need(typeof checked.taskXml==='string'&&checked.taskXml.length>0,'new_task_xml_required');
  const files=[{name:'mcp.json',text:nextMcpText},{name:'daily-backup-config.json',text:nextBackupText},{name:'login.json',text:nextLoginText},{name:'login-task.xml',text:checked.taskXml},{name:'field-diff.json',text:JSON.stringify(diff,null,2)+'\n'}];
  return {source,files,diff,to,refs:[loginRef,mcpRef,backupRef,manifestRef],manifest,runtimeDirectory,old};
 },emit);
 const result={generated:false,dryRun,registered:false,loginPath:plan.to.login.path,loginSha256:plan.to.login.sha256,diff:plan.diff,files:plan.files};
 if(dryRun){emit({step:'update.result',ok:true,detail:'dry_run_passed',result:{...result,files:undefined}});return result;}
 const revalidate=()=>{for(const ref of plan.refs)read(ref.path,ref.sha256);for(const e of plan.manifest.files)read(path.join(plan.runtimeDirectory,e.path),e.result_sha256,16*1024*1024);for(const e of plan.old.source_files)read(path.join(plan.old.working_directory,e.path),e.sha256,16*1024*1024);need(same(inventory(plan.runtimeDirectory),plan.manifest.files.map(e=>e.path).sort()),'candidate_inventory_changed');};
 event('update.revalidate',()=>{revalidate();taskBridge({operation:'check',fromTask,newTask,source});},emit);
 event('update.write',()=>{const request={out:outputDirectory,files:plan.files};if(writeBundle)writeBundle(request);else if(process.platform==='win32')taskBridge({operation:'write',...request});else posixWriteBundle(request);},emit);
 result.generated=true;
 event('update.register',()=>{revalidate();for(const file of plan.files)need(read(path.join(outputDirectory,file.name)).text===file.text,'output_bytes_changed');const registered=taskBridge({operation:'register',fromTask,newTask,source,loginPath:result.loginPath,loginSha256:result.loginSha256});need(registered.registered===true,'task_registration_unconfirmed');},emit);
 result.registered=true;emit({step:'update.result',ok:true,detail:'registered_disabled',result:{...result,files:undefined}});return result;
}
export function parseArguments(args){const values={};for(let i=0;i<args.length;i++){const key=args[i];need(['--from-task','--candidate','--out','--new-task','--dry-run'].includes(key)&&!Object.hasOwn(values,key),'usage');if(key==='--dry-run')values[key]=true;else {need(i+1<args.length&&!args[i+1].startsWith('--'),'usage');values[key]=args[++i];}}need(['--from-task','--candidate','--out','--new-task'].every(k=>values[k]),'usage');return {fromTask:values['--from-task'],candidateDirectory:path.resolve(values['--candidate']),outputDirectory:path.resolve(values['--out']),newTask:values['--new-task'],dryRun:values['--dry-run']??false};}
if(process.argv[1]&&import.meta.url===pathToFileURL(path.resolve(process.argv[1])).href){try{updateMcpSource(parseArguments(process.argv.slice(2)),{emit:row=>console.log(JSON.stringify(row))});}catch(e){console.log(JSON.stringify({step:'update.failed',ok:false,detail:e.message}));process.exitCode=2;}}
