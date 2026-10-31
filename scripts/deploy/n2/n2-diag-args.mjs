// Read-only diagnosis #2 for step 2 preflight switch_bindings_task_xml_changed.
// For both task XML artifacts: decodes entities, compares every leaf with the
// binding template, and diffs the Exec arguments token by token. Prints only
// parameter names, element paths and equal/differs flags (no paths, SIDs, hashes).
// Also runs the binding validator from tools-fb401d45 if that copy exists.
import {createHash} from 'node:crypto';
import {spawnSync} from 'node:child_process';
import {existsSync,readFileSync} from 'node:fs';
import path from 'node:path';
import {pathToFileURL} from 'node:url';

const ACTIVE='HereIAm-iCoreSchema6-d2b-mcp-20261025-129ec194';
const sha=b=>createHash('sha256').update(b).digest('hex');
const out=o=>console.log(JSON.stringify(o));
const env={...process.env};for(const k of Object.keys(env))if(/^(NODE_|I_CORE_)/i.test(k))delete env[k];
env.PSModulePath=path.join(process.env.SystemRoot,'System32','WindowsPowerShell','v1.0','Modules');
const ps=path.join(process.env.SystemRoot,'System32','WindowsPowerShell','v1.0','powershell.exe');
const body="$ErrorActionPreference='Stop'\n$t=Get-ScheduledTask -TaskName '"+ACTIVE+"'\n[pscustomobject]@{arguments=[string]$t.Actions[0].Arguments}|ConvertTo-Json -Compress";
const r=spawnSync(ps,['-NoLogo','-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-EncodedCommand',Buffer.from(body,'utf16le').toString('base64')],{env,encoding:'utf8',windowsHide:true});
const split=s=>[...s.matchAll(/"([^"]*)"|(\S+)/g)].map(m=>m[1]??m[2]);
const liveArgs=JSON.parse(r.stdout.trim()).arguments,tok=split(liveArgs);
const at=re=>tok[tok.findIndex(t=>re.test(t))+1];
const loginPath=at(/^-(Login)?ConfigurationPath$/i),loginRaw=readFileSync(loginPath),login=JSON.parse(loginRaw.toString('utf8').replace(/^﻿/,''));
const backup=JSON.parse(readFileSync(login.backup_configuration_path,'utf8').replace(/^﻿/,''));
const mcp=JSON.parse(readFileSync(login.mcp_configuration_path,'utf8').replace(/^﻿/,''));
const OUT=path.dirname(path.dirname(mcp.working_directory));
const info=JSON.parse(readFileSync(path.join(OUT,'n2-pkg-configs','static-inputs.json'),'utf8'));
const OLDT=path.join(OUT,'tools-42ecf688'),NEWT=path.join(OUT,'tools-fb401d45');
const bindings=t=>path.join(t,'tools','i_core','maintenance','package-switch-bindings.mjs');
const src=readFileSync(bindings(OLDT),'utf8');
const template=eval(src.match(/const taskTemplate=('[^']*');/)[1]);
const xmlText=s=>s.replace(/&(lt|gt|quot|apos|amp);/g,(_,e)=>({lt:'<',gt:'>',quot:'"',apos:"'",amp:'&'})[e]);
const escapeXml=s=>s.replaceAll('&','&amp;').replaceAll('<','&lt;').replaceAll('>','&gt;');
const psPath=path.join(process.env.SystemRoot,'System32','WindowsPowerShell','v1.0','powershell.exe');
const argList=(release,manifest,lp,lh)=>['-NoProfile','-NonInteractive','-WindowStyle','Hidden','-ExecutionPolicy','Bypass','-File',path.join(release,'tools/i_core/release_schema6/lifecycle/login_schema6.ps1'),'-ReleaseDirectory',release,'-ManifestSha256',manifest,'-LoginConfigurationPath',lp,'-LoginConfigurationSha256',lh];
const expected=a=>template.replaceAll('<UserId />','<UserId>'+escapeXml(login.owner_sid)+'</UserId>').replace('<Command />','<Command>'+escapeXml(psPath)+'</Command>').replace('<Arguments />','<Arguments>'+escapeXml(a.map(s=>'"'+s+'"').join(' '))+'</Arguments>');
function decode(buf){if(buf[0]===0xff&&buf[1]===0xfe)return buf.subarray(2).toString('utf16le');return buf.toString('utf8').replace(/^﻿/,'');}
const norm=x=>x.trim().replace(/^<\?xml[^>]*\?>\s*/i,'').replace(/>\s+</g,'><');
function leaves(x){const res=[],stack=[];const re=/<(\/?)([A-Za-z]+)([^>]*?)(\/?)>|([^<]+)/g;let m;while((m=re.exec(x))){if(m[5]!==undefined){res.push([stack.join('/'),xmlText(m[5])]);continue;}if(m[1])stack.pop();else if(m[4])res.push([[...stack,m[2]].join('/'),'']);else stack.push(m[2]);}return res;}
const safe=v=>/^(true|false|\d+|PT\d+[SMH]|[A-Za-z]+)$/.test(v)?v:'<'+(v?'value':'empty')+'>';
function argDiff(fileArgs,want){
 const f=split(fileArgs),w=want;
 const names=a=>a.filter(t=>/^-[A-Za-z]/.test(t));
 const value=(a,n)=>{const i=a.indexOf(n);return i>=0&&i+1<a.length?a[i+1]:undefined;};
 const fn=names(f),wn=names(w);
 return {rawQuotedLikeExpected:fileArgs===w.map(s=>'"'+s+'"').join(' '),tokens:f.length+'/'+w.length,namesFile:fn,namesSame:JSON.stringify(fn)===JSON.stringify(wn),
  values:Object.fromEntries(wn.map(n=>[n,value(f,n)===undefined?'missing':value(f,n)===value(w,n)?'equal':(value(f,n)??'').toLowerCase()===(value(w,n)??'').toLowerCase()?'case_differs':'differs'])),
  hashTrue:{login:value(f,'-LoginConfigurationSha256')===undefined?null:sha(readFileSync(value(f,'-LoginConfigurationPath')??loginPath))===value(f,'-LoginConfigurationSha256')}};
}
function compare(side,file,a){
 const raw=readFileSync(file),text=decode(raw),exp=expected(a);
 const fl=leaves(norm(text)),el=leaves(norm(exp));
 const key=([k,v])=>k+'='+(k.endsWith('/UserId')?'<user>':safe(v));
 const fk=fl.map(key),ek=el.map(key);
 const fArgs=fl.find(([k])=>k.endsWith('Exec/Arguments'))?.[1]??'';
 const fCmd=fl.find(([k])=>k.endsWith('Exec/Command'))?.[1]??'';
 const fUsers=fl.filter(([k])=>k.endsWith('/UserId')).map(([k,v])=>[k,v===login.owner_sid?'owner_sid':/^S-1-/.test(v)?'other_sid':v?'account_name':'empty']);
 out({side,bytes:raw.length,bom:raw[0]===0xff?'utf16le':raw[0]===0xef?'utf8bom':'none',onlyInFile:fk.filter(x=>!ek.includes(x)),onlyInExpected:ek.filter(x=>!fk.includes(x)),
  commandSame:fCmd===psPath,commandCaseInsensitive:fCmd.toLowerCase()===psPath.toLowerCase(),users:fUsers,args:argDiff(fArgs,a)});
}
const taskEntry=backup.specTemplate.entries.find(e=>e.role==='task'&&!e.name.startsWith('preserved/')&&e.name==='tasks/HereIAm-CoreSchema6-Session.xml');
const fromArgs=argList(login.release_directory,login.manifest_sha256,loginPath,sha(loginRaw));
out({live:{loginShaMatchesTask:sha(loginRaw)===at(/^-(Login)?ConfigurationSha256$/i)?.toLowerCase(),liveTaskArgs:argDiff(liveArgs,fromArgs)}});
compare('from',taskEntry.source_path,fromArgs);
compare('to',info.preparedXml,argList(info.releaseDirectory,info.manifestSha256,info.loginPath,info.loginSha256));
// Validator from the new tools copy (if step 2 built it) on the same inputs as step 2.
const nt={exists:existsSync(bindings(NEWT))};
if(nt.exists){
 nt.hasSchedulerExport=readFileSync(bindings(NEWT),'utf8').includes('schedulerExportMatches');
 const ref=(role,p)=>({role,path:p,sha256:sha(readFileSync(p))});
 const plan={from:{releaseDirectory:login.release_directory,manifestSha256:login.manifest_sha256,configurationPath:login.core_configuration_path,configurationSha256:login.core_configuration_sha256},
  to:{releaseDirectory:info.releaseDirectory,manifestSha256:info.manifestSha256,configurationPath:info.corePath,configurationSha256:sha(readFileSync(info.corePath))},
  artifacts:[ref('login',info.loginPath),ref('backup',info.backupPath),ref('mcp',info.mcpPath),ref('task',info.preparedXml)]};
 const fromArtifacts=[ref('login',loginPath),ref('backup',login.backup_configuration_path),ref('mcp',login.mcp_configuration_path),ref('task',taskEntry.source_path)];
 try{const m=await import(pathToFileURL(bindings(NEWT)).href);nt.validated=m.validatePackageSwitchBindings(plan,{fromArtifacts}).validated===true;}catch(e){nt.validated=false;nt.code=e.code??'unknown';nt.stackLine=String(e.stack).split('\n').find(l=>l.includes('package-switch-bindings'))?.replace(/\(.*[\\/]/,'(')?.trim();}
}
out({newTools:nt});
