import { readFileSync, lstatSync, mkdirSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { verifyRelease, plainPath, sha256, PINNED_NODE_SHA256 } from './package.mjs';
import { createRuntimeBackup, verifyRuntimeBackup, backupFilePrimitives as files } from './backup_bundle.mjs';
import { restoreRuntimeBackupForInspection } from './restore_inspection.mjs';
import { wrapBackupKey, portableEnvelopeSha256, restorePortableBackupForInspection } from './portable_key_custody.mjs';
import { runDueAutomaticBackup } from './automatic_backup.mjs';
const reject = () => { throw new Error('backup_child_rejected'); };
const here = path.dirname(fileURLToPath(import.meta.url));
export async function runBackupChild(args, input) {
  const [release,manifestHash]=args;
  if(args.length!==2 || path.resolve(release,'tools/i_core/release_schema6')!==here || sha256(readFileSync(process.execPath))!==PINNED_NODE_SHA256) reject();
  verifyRelease(release,manifestHash);
  if(!Buffer.isBuffer(input) || input.length<34 || input.length>1024*1024) reject();
  const key=Buffer.from(input.subarray(0,32)); let report,password,payloadOffset=32;
  try {
    if(input.subarray(32,36).toString()==='IPW1'){if(input.length<40)reject();const n=input.readUInt32BE(36);if(n<16||n>1024||input.length<40+n+2)reject();password=Buffer.from(input.subarray(40,40+n));payloadOffset=40+n;}
    const operation=JSON.parse(input.subarray(payloadOffset).toString('utf8'));
    const readAnchored=(p,anchor)=>{if(!/^[a-f0-9]{64}$/.test(anchor??''))reject();const bytes=files.small(p,1024*1024);if(sha256(bytes)!==anchor)reject();return JSON.parse(bytes.toString('utf8').replace(/^\uFEFF/,''));};
    if(operation.operation==='setup_portable' && Object.keys(operation).sort().join()===['operation','outputDirectory','backupSetId'].sort().join()) {
      if(!password)reject();const envelope=wrapBackupKey({key,password,backupSetId:operation.backupSetId});files.safe(path.dirname(operation.outputDirectory),true);
      mkdirSync(operation.outputDirectory,{mode:0o700});files.protect(operation.outputDirectory);files.safe(operation.outputDirectory,true);
      writeFileSync(path.join(operation.outputDirectory,'portable-key.json'),JSON.stringify(envelope),{flag:'wx',mode:0o600});
      verifyRelease(release,manifestHash);return {verified:true,status:'portable_key_created',envelopeSha256:portableEnvelopeSha256(envelope),scope:'inventory_only',production_completeness_not_attested:true,activation_supported:false};
    } else if(operation.operation==='restore_portable' && Object.keys(operation).sort().join()===['operation','envelopePath','envelopeSha256','bindingPath','bindingSha256','artifactPath','outputDirectory'].sort().join()) {
      if(!password)reject();const envelope=readAnchored(operation.envelopePath,operation.envelopeSha256),binding=readAnchored(operation.bindingPath,operation.bindingSha256);
      report=await restorePortableBackupForInspection({envelope,password,binding,artifactPath:operation.artifactPath,outputDirectory:operation.outputDirectory,beforePublish:()=>verifyRelease(release,manifestHash)});
    } else if(operation.operation==='automatic' && Object.keys(operation).sort().join()===['operation','configPath','configSha256'].sort().join()) {
      if(password)reject();const config=readAnchored(operation.configPath,operation.configSha256);
      if(Object.keys(config).sort().join()!==['policy','specTemplate','sqliteEntryNames','envelopePath','envelopeSha256'].sort().join())reject();
      const envelope=readAnchored(config.envelopePath,config.envelopeSha256);
      report=await runDueAutomaticBackup({...config,key,envelope});verifyRelease(release,manifestHash);return {...report,scope:'inventory_only',production_completeness_not_attested:true,activation_supported:false};
    } else if(operation.operation==='create' && Object.keys(operation).sort().join()===['operation','specPath','specSha256','outputDirectory'].sort().join()) {
      plainPath(operation.specPath); if(lstatSync(operation.specPath).size>1024*1024) reject(); const bytes=readFileSync(operation.specPath);
      if(bytes.length>1024*1024 || !/^[a-f0-9]{64}$/.test(operation.specSha256 ?? '') || sha256(bytes)!==operation.specSha256) reject();
      const spec=JSON.parse(bytes.toString('utf8').replace(/^\uFEFF/,''));
      report=createRuntimeBackup({spec,outputDirectory:operation.outputDirectory,key});
      if(sha256(readFileSync(plainPath(operation.specPath)))!==operation.specSha256) reject();
    } else if(operation.operation==='verify' && Object.keys(operation).sort().join()===['operation','artifactPath','artifactSha256'].sort().join()) {
      report=verifyRuntimeBackup({artifactPath:operation.artifactPath,artifactSha256:operation.artifactSha256,key});
    } else if(operation.operation==='restore_inspection' && Object.keys(operation).sort().join()===['operation','artifactPath','artifactSha256','outputDirectory','expectedDatabaseFingerprintSha256'].sort().join()) {
      report=await restoreRuntimeBackupForInspection({...operation,key,beforePublish:()=>verifyRelease(release,manifestHash)});
    } else reject();
    if(password && !['restore_portable','setup_portable'].includes(operation.operation))reject();
    if(!report.inspectionOnly) verifyRelease(release,manifestHash);
    return {verified:report.verified,artifactSha256:report.artifactSha256,inventorySha256:report.inventorySha256,files:report.files,
      scope:'inventory_only',production_completeness_not_attested:true,activation_supported:false,
      ...(report.databaseInspection?{databaseInspection:report.databaseInspection}:{}),
      ...(report.passwordOnly?{passwordOnly:true,dpapiUsed:false}:{}),
      ...(report.inspectionOnly?{restored:true,inspectionOnly:true,coreHealth:report.coreHealth,deniedRoutes:report.deniedRoutes,databaseBytesUnchanged:report.databaseBytesUnchanged,sidecarsAbsent:report.sidecarsAbsent}: {})};
  } finally { key.fill(0); password?.fill(0); input.fill(0); }
}
if(process.argv[1] && path.resolve(process.argv[1])===fileURLToPath(import.meta.url)) {
 let input;
 try {
   const chunks=[];let size=0;
   for await (const chunk of process.stdin) { size+=chunk.length;if(size>1024*1024) reject();chunks.push(chunk); }
   input=Buffer.concat(chunks);for(const chunk of chunks) chunk.fill(0);
   process.stdout.write(JSON.stringify(await runBackupChild(process.argv.slice(2),input))+'\n');
 } catch { process.stderr.write('{"rejected":true,"code":"backup_operation_rejected"}\n');process.exitCode=2; }
 finally { input?.fill(0); }
}
