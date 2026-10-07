import { createHash } from 'node:crypto';
import { closeSync, fsyncSync, lstatSync, openSync, readSync, writeFileSync, unlinkSync } from 'node:fs';
import http from 'node:http';
import path from 'node:path';
import { createICoreServer } from '../i_core_server.mjs';
import { assertInspectionDatabasePath } from '../inspection_read_only.mjs';
import { extractRuntimeBackupForInspection, verifyRuntimeBackup } from './backup_bundle.mjs';

const fail = code => { throw Object.assign(new Error(code), { code }); };
function snapshot(databasePath) {
  assertInspectionDatabasePath(databasePath);
  const hash=createHash('sha256'), buffer=Buffer.alloc(65536), fd=openSync(databasePath,'r');
  try { for(;;) { const n=readSync(fd,buffer,0,buffer.length,null); if(!n) break;hash.update(buffer.subarray(0,n)); } }
  finally { buffer.fill(0);closeSync(fd); }
  const stat=lstatSync(databasePath,{bigint:true});
  return {sha256:hash.digest('hex'),identity:[stat.dev,stat.ino,stat.size,stat.mtimeNs,stat.ctimeNs].map(String).join(':')};
}
function request(port, method, route) {
  return new Promise((resolve,reject)=> {
    const req=http.request({host:'127.0.0.1',port,method,path:route,agent:false,timeout:5000},response=> {
      const chunks=[];let length=0;
      response.on('data',chunk=>{length+=chunk.length;if(length>65536){response.destroy();reject(new Error('inspection_response_oversized'));}else chunks.push(chunk);});
      response.on('error',reject);
      response.on('end',()=> {try {resolve({status:response.statusCode,body:JSON.parse(Buffer.concat(chunks))});}catch(error){reject(error);}});
    });
    req.on('error',reject);req.on('timeout',()=>req.destroy(new Error('inspection_probe_timeout')));req.end();
  });
}

// Not a production restore: fresh private output only, followed by a real Core
// HTTP listener in its explicit immutable inspection mode. No restored launcher
// or configuration is executed, and source_path is never a write destination.
export async function restoreRuntimeBackupForInspection({artifactPath,artifactSha256,key,outputDirectory,expectedDatabaseFingerprintSha256,beforePublish}) {
  if(!/^[a-f0-9]{64}$/.test(expectedDatabaseFingerprintSha256 ?? '')) fail('inspection_baseline_required');
  let restored,core,receiptCreated=false;
  try {
    restored=extractRuntimeBackupForInspection({artifactPath,artifactSha256,key,outputDirectory});
    const before=snapshot(restored.databasePath);
    if(before.sha256!==restored.databaseSha256) fail('inspection_database_hash_mismatch');
    core=createICoreServer({databasePath:restored.databasePath,mode:'inspection_read_only'});
    const baseline=core.inspection();
    if(baseline.dataSha256!==expectedDatabaseFingerprintSha256 || baseline.schemaVersion!==restored.sourceSchema
        || baseline.nodeIdSha256!==createHash('sha256').update(restored.nodeId).digest('hex')) fail('inspection_baseline_mismatch');
    const address=await core.listen({host:'127.0.0.1',port:0});
    const health=await request(address.port,'GET','/v1/core/health');
    if(health.status!==200 || health.body.mode!=='inspection_read_only' || health.body.read_only!==true || health.body.immutable!==true
        || health.body.database_fingerprint_sha256!==expectedDatabaseFingerprintSha256) fail('inspection_health_failed');
    const denied=[];
    for(const [method,route] of [['POST','/v1/core/pair'],['POST','/v1/core/domains'],['POST','/v1/core/events'],['GET','/v1/core/devices'],['DELETE','/v1/core/domains/test']]) {
      const response=await request(address.port,method,route);
      if(response.status!==403 || response.body.error?.code!=='inspection_read_only') fail('inspection_business_route_exposed');
      denied.push({method,route,status:response.status});
    }
    if(core.inspection().dataSha256!==expectedDatabaseFingerprintSha256) fail('inspection_data_changed');
    await core.close();core=null;
    if(JSON.stringify(snapshot(restored.databasePath))!==JSON.stringify(before)) fail('inspection_database_changed');
    if(verifyRuntimeBackup({artifactPath,artifactSha256,key}).inventorySha256!==restored.inventorySha256) fail('artifact_changed');
    beforePublish?.();
    const report={verified:true,restored:true,inspectionOnly:true,scope:'inventory_only',production_completeness_not_attested:true,activation_supported:false,
      artifactSha256,inventorySha256:restored.inventorySha256,files:restored.files,databaseSha256:restored.databaseSha256,
      databaseInspection:baseline,coreHealth:health.body,deniedRoutes:denied,databaseBytesUnchanged:true,sidecarsAbsent:true};
    if(Buffer.byteLength(JSON.stringify(report))>60*1024) fail('inspection_report_limit_exceeded');
    const receipt=path.join(outputDirectory,'.inspection-ready.json'),fd=openSync(receipt,'wx',0o600);
    receiptCreated=true;
    try {writeFileSync(fd,JSON.stringify(report)+'\n');fsyncSync(fd);}finally{closeSync(fd);}
    return report;
  } catch(error) {
    if(core) {try{await core.close();}catch{error.closeIncomplete=true;}}
    if(receiptCreated) {try{unlinkSync(path.join(outputDirectory,'.inspection-ready.json'));}catch{error.cleanupIncomplete=true;}}
    if(restored) {try{restored.cleanup();}catch{error.cleanupIncomplete=true;}}
    throw error;
  }
}
