// Raw SQLite state preservation: deliberately never opens SQLite.
import { createCipheriv, createDecipheriv, createHash, createHmac, randomBytes, randomUUID, timingSafeEqual } from 'node:crypto';
import { closeSync, existsSync, fsyncSync, lstatSync, mkdirSync, openSync, readFileSync, readSync, writeFileSync, writeSync, renameSync, rmSync, readdirSync } from 'node:fs';
import path from 'node:path';
import { plainPath, fail, sha256 } from './package.mjs';
import { assertOfflineLease } from './lifecycle/offline_lease.mjs';
import { protectedPath } from './lifecycle/configuration.mjs';
import { INSPECTION_MARKER } from '../inspection_read_only.mjs';

export const RAW_SUFFIXES = Object.freeze(['','-wal','-shm','-journal']);
const MAGIC=Buffer.from('ICORERAW1');
const CHUNK=1024*1024;
function authorize(o,phase){assertOfflineLease(o.supervisorLease,{databasePath:o.databasePath,phase});}
function identity(file){const s=lstatSync(plainPath(file));if(!s.isFile()||s.nlink!==1)fail('raw_state_file_invalid');return [s.dev,s.ino,s.size,s.mtimeMs,s.ctimeMs];}
function walk(file,consume){const fd=openSync(plainPath(file),'r'),buffer=Buffer.alloc(CHUNK);try{let n;while((n=readSync(fd,buffer,0,buffer.length,null))>0)consume(buffer.subarray(0,n));}finally{buffer.fill(0);closeSync(fd);}}
export function rawFileHash(file){const h=createHash('sha256');walk(file,b=>h.update(b));return h.digest('hex');}
function auth(body,key){return createHmac('sha256',key).update('i-core-raw-state-v1\0').update(JSON.stringify(body)).digest('hex');}
export function preserveRawState(o){
 authorize(o,'raw_before_capture');
 if(!(o.backupKey instanceof Uint8Array)||o.backupKey.length!==32)fail('backup_key_required');
 plainPath(o.backupDirectory);const relative=path.relative(path.dirname(o.databasePath),o.backupDirectory);
 if(!relative||(!relative.startsWith('..'+path.sep)&&relative!=='..'&&!path.isAbsolute(relative)))fail('raw_backup_must_be_external');
 const directory=path.join(o.backupDirectory,'raw-'+randomUUID());mkdirSync(directory,{mode:0o700});plainPath(directory);
 const files=[];
 for(const suffix of RAW_SUFFIXES){
  const file=o.databasePath+suffix;
  if(!existsSync(file)){files.push({suffix,present:false});continue;}
  authorize(o,'raw_before_file');const before=identity(file),nonce=randomBytes(12),key=Buffer.from(o.backupKey);
  const encryptedPath=path.join(directory,'database'+suffix+'.aes256gcm');const out=openSync(encryptedPath,'wx',0o600);
  const hash=createHash('sha256');let bytes=0;
  try{const cipher=createCipheriv('aes-256-gcm',key,nonce);cipher.setAAD(MAGIC);writeSync(out,MAGIC);writeSync(out,nonce);
   walk(file,buffer=>{bytes+=buffer.length;hash.update(buffer);writeSync(out,cipher.update(buffer));});
   writeSync(out,cipher.final());writeSync(out,cipher.getAuthTag());fsyncSync(out);
  }finally{key.fill(0);closeSync(out);}
  if(JSON.stringify(before)!==JSON.stringify(identity(file)))fail('raw_source_changed');
  files.push({suffix,present:true,bytes,sha256:hash.digest('hex'),encrypted_file:path.basename(encryptedPath),encrypted_sha256:rawFileHash(encryptedPath)});
 }
 const body={format:'i-core-raw-state-v1',id:path.basename(directory),databasePath:o.databasePath,files};
 const manifestPath=path.join(directory,'manifest.json');writeFileSync(manifestPath,JSON.stringify({...body,authentication:auth(body,o.backupKey)})+'\n',{flag:'wx',mode:0o600,flush:true});
 const result={directory,manifestPath,manifestSha256:sha256(readFileSync(manifestPath))};
 verifyRawState({...o,...result});authorize(o,'raw_after_capture');return result;
}
function verifyAndReadRawState(o,outputDirectory=null){
 const raw=readFileSync(plainPath(o.manifestPath));if(sha256(raw)!==o.manifestSha256)fail('raw_manifest_changed');
 const {authentication,...body}=JSON.parse(raw);
 if(!/^[a-f0-9]{64}$/.test(authentication??'')||!timingSafeEqual(Buffer.from(authentication,'hex'),Buffer.from(auth(body,o.backupKey),'hex'))||body.format!=='i-core-raw-state-v1'||body.databasePath!==o.databasePath)fail('raw_manifest_invalid');
 if(body.files.length!==4||body.files.some((f,i)=>f.suffix!==RAW_SUFFIXES[i]))fail('raw_manifest_invalid');
 for(const f of body.files){if(!f.present)continue;
  if(f.encrypted_file!=='database'+f.suffix+'.aes256gcm')fail('raw_manifest_invalid');
  const file=plainPath(path.join(path.dirname(o.manifestPath),f.encrypted_file));if(rawFileHash(file)!==f.encrypted_sha256)fail('raw_ciphertext_changed');
  const fd=openSync(file,'r'),key=Buffer.from(o.backupKey),header=Buffer.alloc(21),tag=Buffer.alloc(16),buf=Buffer.alloc(CHUNK);let count=0,out;
  try{
   if(outputDirectory)out=openSync(plainPath(path.join(outputDirectory,'i-core.sqlite'+f.suffix),{missing:true}),'wx',0o600);
   const size=lstatSync(file).size;if(size<37||readSync(fd,header,0,21,0)!==21||!header.subarray(0,9).equals(MAGIC))fail('raw_ciphertext_invalid');
   readSync(fd,tag,0,16,size-16);const cipher=createDecipheriv('aes-256-gcm',key,header.subarray(9));cipher.setAAD(MAGIC);cipher.setAuthTag(tag);const hash=createHash('sha256');
   for(let offset=21;offset<size-16;){const n=readSync(fd,buf,0,Math.min(buf.length,size-16-offset),offset);if(!n)fail('raw_ciphertext_truncated');offset+=n;const clear=cipher.update(buf.subarray(0,n));count+=clear.length;hash.update(clear);if(out!==undefined)writeSync(out,clear);clear.fill(0);}
   const tail=cipher.final();count+=tail.length;hash.update(tail);if(out!==undefined)writeSync(out,tail);tail.fill(0);
   if(count!==f.bytes||hash.digest('hex')!==f.sha256)fail('raw_plaintext_mismatch');
   if(out!==undefined)fsyncSync(out);
  }finally{key.fill(0);buf.fill(0);closeSync(fd);if(out!==undefined)closeSync(out);}
 }
 return body;
}
export const verifyRawState=o=>verifyAndReadRawState(o);

// Inspection-only raw restore. The original canonical location is never a
// destination, no SQLite handle is opened, no role/binding/head is changed.
export function restoreRawStateForInspection(o){
 const output=plainPath(o.outputDirectory,{missing:true}),parent=plainPath(path.dirname(output));
 if(existsSync(output))fail('fresh_inspection_directory_required');
 const state=path.dirname(o.databasePath);
 for(const [a,b] of [[state,output],[output,state]]){const relative=path.relative(a,b);if(!relative||(!relative.startsWith('..'+path.sep)&&relative!=='..'&&!path.isAbsolute(relative)))fail('inspection_must_be_separate');}
 if(process.platform==='win32')protectedPath(parent,true);
 else {const stat=lstatSync(parent);if((stat.mode&0o077)!==0||stat.uid!==process.getuid())fail('private_inspection_parent_required');}
 // Authenticate every encrypted member before creating any plaintext output.
 const manifest=verifyAndReadRawState(o);
 const stage=path.join(parent,'.raw-inspection-'+randomUUID());mkdirSync(stage,{mode:0o700});
 try{
  verifyAndReadRawState(o,stage);
  for(const file of manifest.files)if(file.present&&rawFileHash(path.join(stage,'i-core.sqlite'+file.suffix))!==file.sha256)fail('raw_restore_mismatch');
  writeFileSync(path.join(stage,INSPECTION_MARKER),JSON.stringify({format:'i-core-raw-inspection-v1',manifestSha256:o.manifestSha256,inspectionOnly:true,activationSupported:false})+'\n',{flag:'wx',mode:0o600,flush:true});
  plainPath(output,{missing:true});if(existsSync(output))fail('fresh_inspection_directory_required');
  renameSync(stage,output);
  return {ok:true,outputDirectory:output,manifestSha256:o.manifestSha256,files:manifest.files.map(({suffix,present,bytes,sha256})=>({suffix,present,...(present?{bytes,sha256}:{})})),activationSupported:false};
 }catch(error){if(existsSync(stage)){plainPath(stage);for(const name of readdirSync(stage))plainPath(path.join(stage,name));rmSync(stage,{recursive:true});}throw error;}
}
export function assertRawUnchanged(o,manifest){
 authorize(o,'raw_verify_source');
 for(const f of manifest.files){const file=o.databasePath+f.suffix;if(existsSync(file)!==f.present||(f.present&&rawFileHash(file)!==f.sha256))fail('raw_source_changed');}
}
