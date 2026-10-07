// Pure scope validation before any CreateNew output, including failure receipts.
import assert from 'node:assert/strict';
import path from 'node:path';
const canonical = p => {
  assert.equal(typeof p,'string');
  assert.ok(path.isAbsolute(p) && path.normalize(p)===p && !p.includes(':',2));
  assert.ok(!/[\r\n]/.test(p));
  return process.platform==='win32'?p.toLowerCase():p;
};
const within = (a,b) => a===b || a.startsWith(b+path.sep);
export function validateMaintenanceOutputs(c,f) {
  assert.match(c.windowId,/^[A-Za-z0-9][A-Za-z0-9_-]{7,79}$/);
  const root=canonical(c.maintenanceRoot);
  const directory=canonical(f.windowDirectory);
  assert.equal(directory,canonical(path.join(c.maintenanceRoot,'windows',c.windowId)));
  const outputNames=['outputXmlPath','preparedReceiptPath','registrationReceiptPath'];
  const outputs=outputNames.map(k=>canonical(c[k]));
  assert.equal(new Set(outputs).size,outputs.length);
  for(const p of outputs)assert.equal(path.dirname(p),directory);
  assert.equal(c.rawPaths.length,4);
  const external=Object.values(c.externalFiles).flat();
  assert.ok(external.length>0);
  const inputPaths=[
    ...c.rawPaths,...external,...c.aclExpected.paths,
    ...['ownerApprovalPath','frozenReceiptPath','aclReceiptPath','approvedXmlPath','loginConfigurationPath'].map(k=>c[k]),
    ...(c.maintenanceFiles??[]).map(e=>e.path),
  ].map(canonical);
  for(const p of outputs)for(const input of inputPaths)assert.ok(!within(p,input)&&!within(input,p),'maintenance_output_scope_rejected');
  for(const target of [...c.rawPaths,...c.aclExpected.paths].map(canonical))assert.ok(!within(root,target),'maintenance_root_inside_target_rejected');
  return Object.freeze({windowDirectory:f.windowDirectory,outputs:Object.freeze(Object.fromEntries(outputNames.map(k=>[k,c[k]])))});
}
