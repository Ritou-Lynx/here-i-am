import { readFileSync, lstatSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { verifyRelease, plainPath, sha256, PINNED_NODE_SHA256 } from './package.mjs';
import { createRuntimeBackup, verifyRuntimeBackup } from './backup_bundle.mjs';
import { restoreRuntimeBackupForInspection } from './restore_inspection.mjs';
const reject = () => { throw new Error('backup_child_rejected'); };
const here = path.dirname(fileURLToPath(import.meta.url));
export async function runBackupChild(args, input) {
  const [release,manifestHash]=args;
  if(args.length!==2 || path.resolve(release,'tools/i_core/release_schema6')!==here || sha256(readFileSync(process.execPath))!==PINNED_NODE_SHA256) reject();
  verifyRelease(release,manifestHash);
  if(!Buffer.isBuffer(input) || input.length<34 || input.length>1024*1024) reject();
  const key=Buffer.from(input.subarray(0,32)); let report;
  try {
    const operation=JSON.parse(input.subarray(32).toString('utf8'));
    if(operation.operation==='create' && Object.keys(operation).sort().join()===['operation','specPath','specSha256','outputDirectory'].sort().join()) {
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
    if(!report.inspectionOnly) verifyRelease(release,manifestHash);
    return {verified:report.verified,artifactSha256:report.artifactSha256,inventorySha256:report.inventorySha256,files:report.files,
      scope:'inventory_only',production_completeness_not_attested:true,activation_supported:false,
      ...(report.databaseInspection?{databaseInspection:report.databaseInspection}:{}),
      ...(report.inspectionOnly?{restored:true,inspectionOnly:true,coreHealth:report.coreHealth,deniedRoutes:report.deniedRoutes,databaseBytesUnchanged:report.databaseBytesUnchanged,sidecarsAbsent:report.sidecarsAbsent}: {})};
  } finally { key.fill(0); input.fill(0); }
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
