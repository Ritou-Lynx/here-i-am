// Read-only diagnosis for step 2 preflight switch_bindings_task_xml_changed.
// Compares both task XML artifacts with the package-switch binding template and
// prints only element paths and redacted values (no paths, SIDs or hashes).
import {createHash} from 'node:crypto';
import {spawnSync} from 'node:child_process';
import {readFileSync} from 'node:fs';
import path from 'node:path';

const ACTIVE='HereIAm-iCoreSchema6-d2b-mcp-20261025-129ec194';
const sha=b=>createHash('sha256').update(b).digest('hex');
const out=(o)=>console.log(JSON.stringify(o));
const env={...process.env};for(const k of Object.keys(env))if(/^(NODE_|I_CORE_)/i.test(k))delete env[k];
env.PSModulePath=path.join(process.env.SystemRoot,'System32','WindowsPowerShell','v1.0','Modules');
const ps=path.join(process.env.SystemRoot,'System32','WindowsPowerShell','v1.0','powershell.exe');
const body="$ErrorActionPreference='Stop'\n$t=Get-ScheduledTask -TaskName '"+ACTIVE+"'\n[pscustomobject]@{arguments=[string]$t.Actions[0].Arguments}|ConvertTo-Json -Compress";
const r=spawnSync(ps,['-NoLogo','-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-EncodedCommand',Buffer.from(body,'utf16le').toString('base64')],{env,encoding:'utf8',windowsHide:true});
const tok=[...JSON.parse(r.stdout.trim()).arguments.matchAll(/"([^"]*)"|(\S+)/g)].map(m=>m[1]??m[2]);
const at=re=>tok[tok.findIndex(t=>re.test(t))+1];
const loginPath=at(/^-(Login)?ConfigurationPath$/i),login=JSON.parse(readFileSync(loginPath,'utf8').replace(/^﻿/,''));
const backup=JSON.parse(readFileSync(login.backup_configuration_path,'utf8').replace(/^﻿/,''));
const OUT=path.dirname(path.dirname(JSON.parse(readFileSync(login.mcp_configuration_path,'utf8').replace(/^﻿/,'')).working_directory));
const info=JSON.parse(readFileSync(path.join(OUT,'n2-pkg-configs','static-inputs.json'),'utf8'));
const src=readFileSync(path.join(OUT,'tools-42ecf688','tools','i_core','maintenance','package-switch-bindings.mjs'),'utf8');
const template=eval(src.match(/const taskTemplate=('[^']*');/)[1]);
const esc=s=>s.replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;').replace(/'/g,'&apos;');
function expected(release,manifest,lp,lh){
 const p=path.join(process.env.SystemRoot,'System32','WindowsPowerShell','v1.0','powershell.exe');
 const args=['-NoProfile','-NonInteractive','-WindowStyle','Hidden','-ExecutionPolicy','Bypass','-File',path.join(release,'tools/i_core/release_schema6/lifecycle/login_schema6.ps1'),'-ReleaseDirectory',release,'-ManifestSha256',manifest,'-LoginConfigurationPath',lp,'-LoginConfigurationSha256',lh];
 return template.replaceAll('<UserId />','<UserId>'+esc(login.owner_sid)+'</UserId>').replace('<Command />','<Command>'+esc(p)+'</Command>').replace('<Arguments />','<Arguments>'+esc(args.map(s=>'"'+s+'"').join(' '))+'</Arguments>');
}
function decode(buf){if(buf[0]===0xff&&buf[1]===0xfe)return buf.subarray(2).toString('utf16le');return buf.toString('utf8').replace(/^﻿/,'');}
function norm(x){return x.trim().replace(/^<\?xml[^>]*\?>\s*/i,'').replace(/>\s+</g,'><');}
function leaves(x){const res=[];const stack=[];const re=/<(\/?)([A-Za-z]+)([^>]*?)(\/?)>|([^<]+)/g;let m;while((m=re.exec(x))){if(m[5]!==undefined){res.push([stack.join('/'),m[5]]);continue;}if(m[1])stack.pop();else{const attrs=m[3].trim();if(m[4]){res.push([[...stack,m[2]].join('/')+(attrs?'['+attrs.replace(/"[^"]*"/g,v=>v.length>30?'"<redacted>"':v)+']':''),'']);}else{stack.push(m[2]+(attrs&&!attrs.startsWith('xmlns')?'['+attrs.replace(/"[^"]*"/g,v=>v.length>30?'"<redacted>"':v)+']':''));}}}return res;}
const red=v=>(/\\|S-1-|[a-f0-9]{32}/i.test(v)||v.length>40)?'<redacted:'+sha(v).slice(0,8)+'>':v;
function compare(side,file,exp){
 const raw=readFileSync(file),text=decode(raw),declared=(text.match(/^\s*<\?xml[^>]*\?>/)||[''])[0].replace(/\s+/g,' ');
 const a=leaves(norm(text)),b=leaves(norm(exp));
 const ka=a.map(([k,v])=>k+'='+red(v)),kb=b.map(([k,v])=>k+'='+red(v));
 out({side,bom:raw[0]===0xff?'utf16le':raw[0]===0xef?'utf8bom':'none',declaration:declared,equal:norm(text)===norm(exp),onlyInFile:ka.filter(x=>!kb.includes(x)),onlyInExpected:kb.filter(x=>!ka.includes(x)),orderSame:JSON.stringify(ka)===JSON.stringify(kb)});
}
const taskEntry=backup.specTemplate.entries.find(e=>e.role==='task'&&!e.name.startsWith('preserved/')&&e.name==='tasks/HereIAm-CoreSchema6-Session.xml');
compare('from',taskEntry.source_path,expected(login.release_directory,login.manifest_sha256,loginPath,sha(readFileSync(loginPath))));
compare('to',info.preparedXml,expected(info.releaseDirectory,info.manifestSha256,info.loginPath,info.loginSha256));
