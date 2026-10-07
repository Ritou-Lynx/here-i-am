// Pure validation. Caller obtains expected anchors from a reviewed, private window
// configuration and hashes receipt bytes before parsing. This is not a signature
// verifier and never treats a caller-provided `passed` field as authorization.
const fail = code => { throw Object.assign(new Error(code), { code }); };
const hash = value => typeof value === 'string' && /^[a-f0-9]{64}$/.test(value);
export function validateAclApplyReceipt(receipt, expected) {
  if (!receipt || !expected || !Array.isArray(expected.paths) || expected.paths.length < 1) fail('acl_receipt_expected_scope_required');
  const anchors = ['windowId', 'candidateSourceCommit', 'candidateManifestSha256', 'configSha256', 'freezeSha256', 'snapshot_sha256'];
  for (const key of anchors) {
    if (key === 'windowId' ? !/^[A-Za-z0-9][A-Za-z0-9_-]{7,79}$/.test(expected[key]) : key === 'candidateSourceCommit' ? !/^[a-f0-9]{40}$/.test(expected[key]) : !hash(expected[key])) fail('acl_receipt_expected_anchor_invalid');
    if (receipt[key] !== expected[key]) fail('acl_receipt_binding_mismatch');
  }
  const paths = new Set(expected.paths.map(p => typeof p === 'string' ? p.toLowerCase() : fail('acl_receipt_expected_path_invalid')));
  if (paths.size !== expected.paths.length) fail('acl_receipt_expected_paths_duplicate');
  if (!Number.isSafeInteger(expected.expectedForeignOwnerCount) || expected.expectedForeignOwnerCount < 0 || expected.expectedForeignOwnerCount > paths.size) fail('acl_receipt_expected_count_invalid');
  if (receipt.format !== 'schema6-acl-maintenance-v2' || receipt.mode !== 'Apply' || receipt.passed !== true || receipt.scope !== 'owner_and_dacl_only'
      || receipt.sacl_restored !== false || receipt.target_contents_read !== false || receipt.services_changed !== false || receipt.tasks_changed !== false
      || receipt.rollback_attempted !== false || receipt.rollback_deferred === true || receipt.privilege_restore_failed === true
      || receipt.inventory_verified !== true || receipt.metadata_unchanged !== true || receipt.freeze_verified !== true) fail('acl_receipt_operation_rejected');
  if (receipt.expected_count !== paths.size || receipt.verified_count !== paths.size || receipt.expected_foreign_owner_count !== expected.expectedForeignOwnerCount) fail('acl_receipt_count_mismatch');
  const start = Date.parse(receipt.started_utc), end = Date.parse(receipt.completed_utc), earliest = Date.parse(expected.notBeforeUtc), latest = Date.parse(expected.notAfterUtc);
  if (![start, end, earliest, latest].every(Number.isFinite) || earliest > latest || start < earliest || end < start || end > latest) fail('acl_receipt_time_mismatch');
  if (!Array.isArray(receipt.items) || receipt.items.length !== paths.size * 3) fail('acl_receipt_items_incomplete');
  for (const action of ['baseline_comparison', 'apply_owner_dacl', 'apply_readback']) {
    const found = new Set();
    for (const row of receipt.items.filter(row => row?.action === action)) {
      const p = typeof row.path === 'string' ? row.path.toLowerCase() : '';
      if (!paths.has(p) || found.has(p) || row.verified !== true || row.code !== '') fail('acl_receipt_item_rejected');
      const time = Date.parse(row.at_utc);
      if (!Number.isFinite(time) || time < start || time > end) fail('acl_receipt_item_time_mismatch');
      found.add(p);
    }
    if (found.size !== paths.size) fail('acl_receipt_items_incomplete');
  }
  return Object.freeze({ passed: true, verifiedCount: paths.size, windowId: receipt.windowId, scope: receipt.scope, humanAcceptance: false });
}
