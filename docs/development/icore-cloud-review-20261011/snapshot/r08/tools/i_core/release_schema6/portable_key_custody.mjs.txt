import { createCipheriv, createDecipheriv, createHash, createHmac, randomBytes, scryptSync, timingSafeEqual } from 'node:crypto';
import { verifyRuntimeBackup } from './backup_bundle.mjs';
import { restoreRuntimeBackupForInspection } from './restore_inspection.mjs';
const fail=c=>{throw Object.assign(new Error(c),{code:c});};
const hash=b=>createHash('sha256').update(b).digest('hex');
const exact=(v,keys)=>v && typeof v==='object' && !Array.isArray(v) && Object.keys(v).sort().join() === [...keys].sort().join();
const hex=/^[a-f0-9]{64}$/;
export const PORTABLE_KDF=Object.freeze({name:'scrypt',N:131072,r:8,p:1,length:32});
const canonical=v=>Buffer.from(JSON.stringify(v));
function passwordBytes(p){if(!(p instanceof Uint8Array)||p.length<16||p.length>1024)fail('portable_password_length');return Buffer.from(p);}
function keyBytes(k){if(!(k instanceof Uint8Array)||k.length!==32)fail('portable_key_length');return Buffer.from(k);}
function b64(s,n){if(typeof s!=='string'||s.length>2048)fail('portable_encoding');const b=Buffer.from(s,'base64url');if(b.length!==n||b.toString('base64url')!==s)fail('portable_encoding');return b;}
function context(envelope){
 if(!exact(envelope,['format','purpose','backupSetId','keyId','kdf','salt','nonce','ciphertext','tag'])||envelope.format!=='i-core-portable-key-v1'||envelope.purpose!=='backup'||!hex.test(envelope.keyId)||!hex.test(envelope.backupSetId)||!exact(envelope.kdf,Object.keys(PORTABLE_KDF))||Object.keys(PORTABLE_KDF).some(k=>envelope.kdf[k]!==PORTABLE_KDF[k]))fail('portable_contract');
 return {format:envelope.format,purpose:envelope.purpose,backupSetId:envelope.backupSetId,keyId:envelope.keyId,kdf:PORTABLE_KDF,salt:envelope.salt,nonce:envelope.nonce};
}
export function portableEnvelopeSha256(envelope){context(envelope);b64(envelope.salt,32);b64(envelope.nonce,12);b64(envelope.ciphertext,32);b64(envelope.tag,16);return hash(canonical(envelope));}
export function wrapBackupKey({key,password,backupSetId}){
 const secret=keyBytes(key),pw=passwordBytes(password);let derived;
 try{if(!hex.test(backupSetId))fail('portable_set_required');const salt=randomBytes(32),nonce=randomBytes(12);
 const e={format:'i-core-portable-key-v1',purpose:'backup',backupSetId,keyId:hash(secret),kdf:{...PORTABLE_KDF},salt:salt.toString('base64url'),nonce:nonce.toString('base64url'),ciphertext:'',tag:''};
 derived=scryptSync(pw,salt,32,{N:PORTABLE_KDF.N,r:8,p:1,maxmem:192*1024*1024});const cipher=createCipheriv('aes-256-gcm',derived,nonce);cipher.setAAD(canonical(context(e)));
 e.ciphertext=Buffer.concat([cipher.update(secret),cipher.final()]).toString('base64url');e.tag=cipher.getAuthTag().toString('base64url');return e;
 }finally{secret.fill(0);pw.fill(0);derived?.fill(0);}
}
export function unwrapBackupKey({envelope,password,backupSetId}){
 const aad=context(envelope);if(envelope.backupSetId!==backupSetId)fail('portable_set_mismatch');const salt=b64(envelope.salt,32),nonce=b64(envelope.nonce,12),ct=b64(envelope.ciphertext,32),tag=b64(envelope.tag,16),pw=passwordBytes(password);let derived,result,decoded;
 try{derived=scryptSync(pw,salt,32,{N:PORTABLE_KDF.N,r:8,p:1,maxmem:192*1024*1024});const decipher=createDecipheriv('aes-256-gcm',derived,nonce);decipher.setAAD(canonical(aad));decipher.setAuthTag(tag);decoded=decipher.update(ct);result=Buffer.concat([decoded,decipher.final()]);if(hash(result)!==envelope.keyId)fail('portable_key_identity');return result;}catch{result?.fill(0);fail('portable_authentication_failed');}finally{decoded?.fill(0);pw.fill(0);derived?.fill(0);}
}
function bindingBody(b){if(!exact(b,['format','backupSetId','keyId','envelopeSha256','artifactSha256','inventorySha256','databaseFingerprintSha256','mac'])||b.format!=='i-core-portable-artifact-v1'||Object.entries(b).some(([k,v])=>k!=='format'&&!hex.test(v)))fail('portable_binding_invalid');const {mac,...body}=b;return body;}
export function bindPortableArtifact({key,envelope,report}){
 const secret=keyBytes(key);try{if(hash(secret)!==envelope.keyId)fail('portable_key_identity');const body={format:'i-core-portable-artifact-v1',backupSetId:envelope.backupSetId,keyId:envelope.keyId,envelopeSha256:portableEnvelopeSha256(envelope),artifactSha256:report.artifactSha256,inventorySha256:report.inventorySha256,databaseFingerprintSha256:report.databaseInspection.dataSha256};const result={...body,mac:createHmac('sha256',secret).update(canonical(body)).digest('hex')};bindingBody(result);return result;}finally{secret.fill(0);}
}
export function verifyPortableBinding({key,envelope,binding}){
 const secret=keyBytes(key);try{const body=bindingBody(binding);if(hash(secret)!==envelope.keyId||binding.keyId!==envelope.keyId||binding.backupSetId!==envelope.backupSetId||binding.envelopeSha256!==portableEnvelopeSha256(envelope)||!timingSafeEqual(Buffer.from(binding.mac,'hex'),createHmac('sha256',secret).update(canonical(body)).digest()))fail('portable_binding_rejected');return body;}finally{secret.fill(0);}
}
export async function restorePortableBackupForInspection({envelope,password,binding,artifactPath,outputDirectory,beforePublish}){
 const key=unwrapBackupKey({envelope,password,backupSetId:binding.backupSetId});try{verifyPortableBinding({key,envelope,binding});if(verifyRuntimeBackup({key,artifactPath,artifactSha256:binding.artifactSha256}).inventorySha256!==binding.inventorySha256)fail('portable_inventory_mismatch');const r=await restoreRuntimeBackupForInspection({key,artifactPath,artifactSha256:binding.artifactSha256,outputDirectory,expectedDatabaseFingerprintSha256:binding.databaseFingerprintSha256,beforePublish});if(r.inventorySha256!==binding.inventorySha256)fail('portable_inventory_mismatch');return {...r,passwordOnly:true,dpapiUsed:false};}finally{key.fill(0);}
}
