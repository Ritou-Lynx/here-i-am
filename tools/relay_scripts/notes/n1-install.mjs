// N1 home install: put the read-only Feishu notes mirror into the feishu tutor
// tool directory and run it once. The scheduled task is registered by the
// PowerShell launcher afterwards, only when this exits 0.
//   1  preflight: directories, config, home sync files are known versions
//   2  backup cli.mjs / notes_mirror.mjs / config.json, then copy the new files
//      and add config.notes.folders (rolled back if any later part of step 2 fails)
//   3  --help self-check of feishu_sync and notes_mirror with the new files
//   4  one real mirror run (12-minute budget), counts only
// Output: one JSON row per step; no tokens, paths, titles or document content.
// Exit: 0 installed and the run produced notes_ok; 3 installed but the run failed;
// 1 stopped (nothing changed, or rolled back).
//
// Usage: n1-install.ps1 (Windows PowerShell 5.1, -File) runs this with no arguments.
import {createHash} from 'node:crypto';
import {spawnSync} from 'node:child_process';
import {copyFileSync,existsSync,lstatSync,mkdirSync,readFileSync,renameSync,statSync,writeFileSync} from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';

const FOLDERS=['日记/日报','工作'];
const REPO=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..','..','..');
const SRC=path.join(REPO,'tools','feishu_tutor','sync');
// LF-normalised SHA256 of the files this round installs (this PR's versions).
const NEW={'cli.mjs':'4cdedae5acf773fa5e415d45f85ff3e8735096c5b7c0fbd0ad44c643610f0f19',
 'notes_mirror.mjs':'4514a1ee64e9a49bd1330a6551f0900fa1cd657171d998624705ac980f713f18'};
// Home copies that may be replaced: the pre-N1 cli.mjs (or an already installed one).
const REPLACEABLE={'cli.mjs':['b9bb385a718e1cb11bfb2a0fd6421b324bc10804d567a335f17d11dd729cd0c8',NEW['cli.mjs']]};
// Files notes_mirror imports or that share cli.mjs; they must already be current.
const CURRENT={'feishu_sync.mjs':'076652ad137c63c6653b1b48212bf8a77c6b4e974f02ef00eea3f280d8315d1d',
 'layout.mjs':'ede3cf9b4fd05e0b6e083536212ddb27ae3fb69b90b9efb1769cd7b915459249',
 'schema.mjs':'84c8c57596766ae4ad0cbedafb541fe67f090c40030d0f8865867aefea7fe16c'};

class Stop extends Error{constructor(step,detail,exit=1){super(detail);this.step=step;this.detail=detail;this.exit=exit;}}
const emit=(step,ok,detail)=>console.log(JSON.stringify({step,ok,detail}));
const need=(cond,step,detail)=>{if(!cond)throw new Stop(step,detail);};
const lf=b=>Buffer.from(b.toString('utf8').replace(/\r\n/g,'\n'),'utf8');
const sha=b=>createHash('sha256').update(b).digest('hex');
const code=t=>{const l=String(t).trim().split(/\r?\n/).filter(Boolean).pop()??'';if(!l)return 'none';return /^[a-z0-9_:=. -]{1,160}$/.test(l)?l:'unrecognised_output';};
const childEnv=()=>{const e={};for(const [k,v] of Object.entries(process.env))if(!/^(NODE_|FEISHU_TUTOR_|I_CORE_|I_REMOTE_MCP_|GIT_)/i.test(k))e[k]=v;return e;};
function node(args,timeout){
 const r=spawnSync(process.execPath,args,{env:childEnv(),encoding:'utf8',windowsHide:true,maxBuffer:16*1024*1024,timeout,killSignal:'SIGTERM'});
 return {exit:r.error?(r.error.code==='ETIMEDOUT'?'timeout':'spawn_failed'):r.status,stdout:r.stdout??'',stderr:r.stderr??''};
}
function realDir(p,step,detail){let s;try{s=lstatSync(p);}catch{throw new Stop(step,detail+'_missing');}need(s.isDirectory()&&!s.isSymbolicLink(),step,detail+'_not_plain_directory');}

function main(){
 need(process.argv.length===2,'args','usage: no arguments');
 const home=process.env.USERPROFILE;need(home&&path.win32.isAbsolute(home),'preflight','userprofile_missing');
 const tool=path.join(home,'feishu-tutor-tool'),sync=path.join(tool,'sync'),study=path.join(home,'feishu-study');
 const state=path.join(study,'state'),notes=path.join(home,'feishu-notes'),configFile=path.join(tool,'config.json');

 // 1 preflight (read-only)
 realDir(tool,'preflight','tool_dir');realDir(sync,'preflight','sync_dir');realDir(study,'preflight','study_dir');realDir(state,'preflight','state_dir');
 if(existsSync(notes))realDir(notes,'preflight','notes_dir');
 need(existsSync(configFile)&&statSync(configFile).isFile(),'preflight','config_missing');
 const configBytes=readFileSync(configFile);
 need(!(configBytes[0]===0xef&&configBytes[1]===0xbb&&configBytes[2]===0xbf),'preflight','config_has_bom');
 let config;try{config=JSON.parse(configBytes.toString('utf8'));}catch{throw new Stop('preflight','config_not_json');}
 need(config&&typeof config==='object'&&!Array.isArray(config),'preflight','config_not_object');
 let addNotes=true;
 if(config.notes!==undefined){
  need(JSON.stringify(config.notes)===JSON.stringify({folders:FOLDERS}),'preflight','config_notes_differs');
  addNotes=false;
 }
 for(const [f,h] of Object.entries(CURRENT)){
  const p=path.join(sync,f);need(existsSync(p),'preflight','home_missing:'+f);
  need(sha(lf(readFileSync(p)))===h,'preflight','home_unknown_version:'+f);
 }
 const homeCli=sha(lf(readFileSync(path.join(sync,'cli.mjs'))));
 need(REPLACEABLE['cli.mjs'].includes(homeCli),'preflight','home_unknown_version:cli.mjs');
 const source={};
 for(const [f,h] of Object.entries(NEW)){const b=lf(readFileSync(path.join(SRC,f)));need(sha(b)===h,'preflight','source_hash_mismatch:'+f);source[f]=b;}
 const homeMirror=path.join(sync,'notes_mirror.mjs');
 const syncBusy=existsSync(path.join(state,'.sync.lock'));
 emit('preflight',true,`config_notes=${addNotes?'add':'present'} cli=${homeCli===NEW['cli.mjs']?'current':'pre_n1'} mirror=${existsSync(homeMirror)?'present':'new'} sync_lock=${syncBusy?'held':'free'}`);

 // 2 backup + copy (+ config)
 const stamp=new Date().toISOString().replace(/[-:]/g,'').replace('.','-').replace('Z','');
 const backup=path.join(tool,'backups','n1-notes-'+stamp);mkdirSync(backup,{recursive:true});
 const saved=[];
 for(const f of ['cli.mjs','notes_mirror.mjs']){const p=path.join(sync,f);if(existsSync(p)){copyFileSync(p,path.join(backup,f));saved.push(f);}}
 copyFileSync(configFile,path.join(backup,'config.json'));
 const restore=()=>{
  for(const f of ['cli.mjs','notes_mirror.mjs']){const p=path.join(sync,f);if(saved.includes(f))copyFileSync(path.join(backup,f),p);}
  if(!saved.includes('notes_mirror.mjs')&&existsSync(homeMirror)){try{renameSync(homeMirror,path.join(backup,'notes_mirror.mjs.installed'));}catch{}}
  copyFileSync(path.join(backup,'config.json'),configFile);
 };
 const atomic=(p,b)=>{const t=p+'.n1-pending';writeFileSync(t,b);renameSync(t,p);};
 try{
  atomic(path.join(sync,'cli.mjs'),source['cli.mjs']);
  atomic(homeMirror,source['notes_mirror.mjs']);
  if(addNotes){config.notes={folders:FOLDERS};atomic(configFile,Buffer.from(JSON.stringify(config,null,2)+'\n','utf8'));}
  for(const [f,h] of Object.entries(NEW))need(sha(readFileSync(path.join(sync,f)))===h,'install','installed_hash_mismatch:'+f);
  emit('install',true,`backup=n1-notes-${stamp} files=cli.mjs,notes_mirror.mjs config=${addNotes?'notes_added':'unchanged'}`);

  // 3 self-check: both entry points load with the new cli.mjs
  for(const f of ['feishu_sync.mjs','notes_mirror.mjs']){
   const r=node([path.join(sync,f),'--help'],60*1000);
   need(r.exit===0,'self_check',f+'_help_exit_'+r.exit+':'+code(r.stderr));
  }
  emit('self_check',true,'help_ok');
 }catch(e){
  try{restore();emit('rollback',true,'restored_from_backup');}catch{emit('rollback',false,'restore_failed_backup_kept');}
  throw e;
 }

 // 4 one real run. Failure here leaves the install in place (it is inert until scheduled).
 mkdirSync(notes,{recursive:true});
 const t0=Date.now();
 const r=node([homeMirror,'--config',configFile,'--state',state,'--notes',notes,'--max-minutes','12'],14*60*1000);
 const seconds=Math.round((Date.now()-t0)/1000);
 const out=code(r.stdout),err=r.stderr.trim()?code(r.stderr):'';
 let counts='';
 try{
  const index=JSON.parse(readFileSync(path.join(notes,'index.json'),'utf8'));
  const per=(index.folders??[]).map(f=>Object.values(index.docs).filter(d=>d.top===f.dir).length);
  const chars=Object.values(index.docs).reduce((n,d)=>n+(Number.isSafeInteger(d.chars)?d.chars:0),0);
  counts=` docs_per_folder=${per.join('/')} chars=${chars}`;
 }catch{counts=' index=none';}
 const ok=(r.exit===0||r.exit===2)&&out.startsWith('notes_');
 emit('test_run',ok,`exit=${r.exit} seconds=${seconds} out=${out}${err?' err='+err:''}${counts}`);
 if(!ok)throw new Stop('test_run','installed_but_run_failed',3);
 if(out==='notes_skipped_sync_busy')emit('test_run_note',true,'sync_was_running_retry_by_schedule');
}

try{main();process.exitCode=0;}
catch(e){
 if(e instanceof Stop){if(e.step!=='test_run')emit(e.step,false,e.detail);process.exitCode=e.exit;}
 else{emit('error',false,String(e?.code??e?.name??'error').slice(0,80));process.exitCode=1;}
}
