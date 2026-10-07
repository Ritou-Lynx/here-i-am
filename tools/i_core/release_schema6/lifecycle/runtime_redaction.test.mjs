import assert from 'node:assert/strict';
import { randomBytes } from 'node:crypto';
import { rmSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import test from 'node:test';
import { syntheticRoot } from '../../test_fixtures/release_schema6/synthetic_paths.mjs';
import { readConfigurationDeclaration, publicLifecycleErrorCode } from './common.mjs';

test('malformed configuration secrets cannot enter lifecycle error codes',t=>{
 const root=syntheticRoot('schema6-redaction-');t.after(()=>rmSync(root,{recursive:true,force:true}));
 const secret=randomBytes(32).toString('hex'),file=path.join(root,'invalid.json');
 writeFileSync(file,'{"pairing_secret":"'+secret+'",BROKEN');
 let failure;try{readConfigurationDeclaration(file);}catch(error){failure=error;}
 assert.equal(failure.code,'config_json_rejected');
 assert.equal(String(failure).includes(secret),false);
 assert.equal(publicLifecycleErrorCode(new SyntaxError('Unexpected JSON near '+secret)),'runtime_operation_failed');
 assert.equal(publicLifecycleErrorCode(Object.assign(new Error(secret),{code:secret})),'runtime_operation_failed');
 assert.equal(publicLifecycleErrorCode(new Error('config_json_rejected')),'config_json_rejected');
});
