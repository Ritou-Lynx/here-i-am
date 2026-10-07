import assert from 'node:assert/strict';
import {spawn,execFileSync} from 'node:child_process';
import {existsSync,readFileSync,readdirSync,writeFileSync,copyFileSync,mkdirSync} from 'node:fs';
import path from 'node:path';
import {cleanEnvironment,sha256} from '../package.mjs';
import {createRuntimeLab,until,api,health,cleanReceipt,ps,repository,protect} from './test-fixture.mjs';
import {LEGACY_SOURCE_ROOT,verifyLegacySourceInventory,createSyntheticReaderState,legacyReaderEnvironment,allocateSyntheticLoopbackPort,connectLegacyMcpReader,syntheticHttpRequest} from '../../test_fixtures/release_schema6/mcp_reader/helper.mjs';
export {createRuntimeLab,until,api,health,cleanReceipt,ps,repository};
export const json=file=>existsSync(file)?JSON.parse(readFileSync(file,'utf8')):null;
export function loginConfig(l,port=0){
 const controlRoot=l.dir('sessions');
 const configuration={format:'schema6-login-v1',owner_sid:l.configuration.owner_sid,release_directory:l.release,manifest_sha256:l.manifestHash,state_directory:l.state,control_root:controlRoot,core_configuration_path:l.configPath,core_configuration_sha256:sha256(readFileSync(l.configPath)),core_port:port,backup_configuration_path:null,backup_configuration_sha256:null,backup_key_directory:null,backup_interval_seconds:300};
 const file=path.join(path.dirname(l.configPath),'login.json');writeFileSync(file,JSON.stringify(configuration));
 return {file,controlRoot,configuration,hash:sha256(readFileSync(file))};
}
export function refreshLogin(c){writeFileSync(c.file,JSON.stringify(c.configuration));c.hash=sha256(readFileSync(c.file));}
export function loginArgs(l,c){return ['-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',path.join(l.lifecycle,'login_schema6.ps1'),'-ReleaseDirectory',l.release,'-ManifestSha256',l.manifestHash,'-LoginConfigurationPath',c.file,'-LoginConfigurationSha256',c.hash];}
export async function configureManagedMcp(l,c,{graceMs=100}={}){
 const inventory=verifyLegacySourceInventory(),source=l.dir('fixed-legacy-mcp-source');
 for(const item of inventory.files){const to=path.join(source,item.path);mkdirSync(path.dirname(to),{recursive:true});copyFileSync(path.join(LEGACY_SOURCE_ROOT,item.path),to);}
 const state=createSyntheticReaderState({syntheticRoot:l.root,coreDbPath:path.join(l.state,'i-core.sqlite'),protectDirectory:protect});
 const environment=legacyReaderEnvironment(state);delete environment.I_CORE_DB;
 const port=await allocateSyntheticLoopbackPort();
 environment.I_REMOTE_MCP_PUBLIC_URL='http://127.0.0.1:'+port;
 const configuration={format:'schema6-mcp-v1',owner_sid:l.configuration.owner_sid,executable_path:path.join(l.release,'runtime/node.exe'),executable_sha256:sha256(readFileSync(path.join(l.release,'runtime/node.exe'))),working_directory:source,entrypoint:inventory.entry,source_files:inventory.files.map(({path,sha256})=>({path,sha256})),arguments:['serve'],environment,database_path:state.coreDbPath,listen_host:'127.0.0.1',listen_port:port,grace_ms:graceMs};
 const file=path.join(path.dirname(c.file),'mcp.json');writeFileSync(file,JSON.stringify(configuration));
 c.configuration.mcp_configuration_path=file;c.configuration.mcp_configuration_sha256=sha256(readFileSync(file));refreshLogin(c);
 return {state,configuration,file,source,base:'http://127.0.0.1:'+port};
}
export async function host(l,c,{initial=true,register=true}={}){
 const prior=new Set(readdirSync(c.controlRoot));
 const child=spawn(ps,[...loginArgs(l,c),...(initial?['-InitializeEmpty']:[])],{windowsHide:true,env:cleanEnvironment(),stdio:['ignore','pipe','pipe']});
 const run={child,closed:false,exit:null,stdout:'',stderr:'',control:null};
 child.stdout.on('data',b=>run.stdout+=b);child.stderr.on('data',b=>run.stderr+=b);child.on('close',code=>{run.closed=true;run.exit=code;});
 const session=()=>readdirSync(c.controlRoot).filter(n=>!prior.has(n)).map(n=>path.join(c.controlRoot,n)).find(p=>existsSync(path.join(p,'session-window.json')));
 await until(()=>session()||run.closed,180000);assert.equal(run.closed,false,run.stderr);run.session=session();run.window=json(path.join(run.session,'session-window.json'));
 assert.equal(run.window.pid,child.pid);assert.equal(run.window.hook_ready,true);
 run.controls=()=>readdirSync(run.session).filter(n=>n.startsWith('control-')).map(n=>path.join(run.session,n));
 run.read=name=>run.control?json(path.join(run.control,name)):null;
 run.send=(message,wparam=0)=>JSON.parse(execFileSync(ps,['-NoProfile','-NonInteractive','-File',path.join(repository,'tools/i_core/test_fixtures/release_schema6/send_session_message.ps1'),'-Window',String(run.window.hwnd),'-ExpectedPid',String(child.pid),'-Message',String(message),'-WParam',String(wparam)],{windowsHide:true,env:cleanEnvironment(),encoding:'utf8',timeout:50000}));
 run.wait=async()=>{await until(()=>run.closed,60000);return run;};run.stop=()=>run.send(16);
 run.ready=async(except=null)=>{await until(()=>run.controls().find(p=>p!==except&&existsSync(path.join(p,'ready.json')))||run.closed,240000);assert.equal(run.closed,false,run.stderr+JSON.stringify(run.read('child.json')));run.control=run.controls().find(p=>p!==except&&existsSync(path.join(p,'ready.json')));return run.read('ready.json');};
 if(register)l.registerRun(run);return run;
}
export async function seedSyntheticChat(l,ready,suffix='reader'){
 const device='synthetic-mcp-'+suffix,paired=await api(ready,'/devices/pair',null,{device_id:device,display_name:'Synthetic MCP reader',platform:'test',client_version:'1',capabilities:['chat'],pairing_code:l.configuration.pairing_secret});
 const syncId='synthetic-mcp-message-'+suffix;
 await api(ready,'/chat/messages',paired.device_token,{device_id:device,messages:[{sync_id:syncId,origin_device_id:device,origin_sequence:1,character_id:'lin-ai',sender:'user',content:'synthetic external reader message',created_at_ms:1700000000000,message_type:'chat',asset_refs:[],addenda:[]}]});
 return {device,paired,syncId};
}
export async function connectManaged(run,mcp,{requireMessage=true}={}){
 await until(()=>run.read('mcp-start.json')||run.closed,60000);assert.equal(run.closed,false,run.stderr);
 let available=false;const deadline=Date.now()+60000;
 while(Date.now()<deadline&&!available){try{available=(await syntheticHttpRequest(mcp.base,'/.well-known/oauth-authorization-server')).status===200;}catch{}if(!available)await new Promise(resolve=>setTimeout(resolve,50));}
 assert.equal(available,true,'managed MCP HTTP ready');
 return connectLegacyMcpReader({state:mcp.state,base:mcp.base,requireMessage});
}
export function processGone(pid){try{process.kill(pid,0);return false;}catch(error){if(error.code==='ESRCH')return true;throw error;}}
export async function shutdownAndMeasure(run){
 const begin=performance.now();assert.equal(run.send(17).result,1);run.send(22,1);await run.wait();
 return Number((performance.now()-begin).toFixed(3));
}
export function mcpStopped(run){
 const stop=run.read('mcp-stop.json');assert.ok(stop);
 for(const key of ['job_empty_confirmed','process_exit_confirmed','owned_tree_handles_released_confirmed'])assert.equal(stop[key],true,key);
 assert.equal(stop.scope,'owned_mcp_job_only');assert.equal(processGone(stop.pid),true);
 return stop;
}
