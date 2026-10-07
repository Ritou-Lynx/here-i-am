import test from 'node:test';
import assert from 'node:assert/strict';
import path from 'node:path';
import {validateMaintenanceOutputs} from '../maintenance/maintenance_outputs.mjs';
const base=path.join(path.parse(process.cwd()).root,'synthetic-scope');
function fixture(){
 const maintenanceRoot=path.join(base,'maintenance'),windowId='synthetic-window-01';
 const windowDirectory=path.join(maintenanceRoot,'windows',windowId),state=path.join(base,'state');
 const c={maintenanceRoot,windowId,outputXmlPath:path.join(windowDirectory,'prepared.xml'),preparedReceiptPath:path.join(windowDirectory,'prepared.json'),registrationReceiptPath:path.join(windowDirectory,'registered.json'),rawPaths:['','-wal','-shm','-journal'].map(s=>path.join(state,'synthetic.sqlite')+s),externalFiles:{approvals:[path.join(state,'approvals.json')],grants:[path.join(state,'grants.json')]},aclExpected:{paths:[state]},maintenanceFiles:[]};
 for(const [k,n]of Object.entries({ownerApprovalPath:'owner.json',frozenReceiptPath:'frozen.json',aclReceiptPath:'acl.json',approvedXmlPath:'approved.xml',loginConfigurationPath:'login.json'}))c[k]=path.join(windowDirectory,n);
 return {c,f:{windowDirectory}};
}
test('outputs require an exact current window and disjoint input/target scope',()=>{
 const {c,f}=fixture();assert.equal(validateMaintenanceOutputs(c,f).windowDirectory,f.windowDirectory);
});
for(const key of ['outputXmlPath','preparedReceiptPath','registrationReceiptPath'])test('missing journal cannot become '+key+', including rejection receipts',()=>{
 const {c,f}=fixture();c[key]=c.rawPaths[3];assert.throws(()=>validateMaintenanceOutputs(c,f));
});
test('duplicate output, input collision, old window and target-contained root are rejected',()=>{
 for(const change of [
  c=>{c.preparedReceiptPath=c.outputXmlPath;},
  c=>{c.outputXmlPath=c.approvedXmlPath;},
  c=>{c.windowId='synthetic-window-old';},
  c=>{c.aclExpected.paths.push(base);},
  c=>{c.registrationReceiptPath=path.join(path.dirname(c.registrationReceiptPath),'nested','r.json');}
 ]){const {c,f}=fixture();change(c);assert.throws(()=>validateMaintenanceOutputs(c,f));}
});
