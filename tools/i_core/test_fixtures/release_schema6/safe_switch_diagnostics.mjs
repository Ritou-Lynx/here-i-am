// Redacted CI diagnostics for safe switch fixtures: step names, reviewed error
// codes, and readiness ordering only. No path, PID, tick value or free text.
export function stepCodes(lines){
 const code=detail=>String(detail??'').split(';').map(part=>part.replace(/:.*$/s,'')).filter(part=>/^[a-z0-9_]{1,64}(=[a-z0-9_]{1,64})?$/.test(part)).join(';')||'unreadable';
 return lines.filter(row=>typeof row.step==='string'&&/^[a-z0-9_.]{1,64}$/.test(row.step))
  .map(row=>row.step+':'+(row.ok===true?'ok':code(row.detail))).join(' ');
}
export function readySnapshot(lines){
 const snapshot=lines.findLast(row=>row.format==='schema6-ready-post-failure-snapshot-v1');
 if(!snapshot)return 'none';
 if(snapshot.probe_error!==false||!Array.isArray(snapshot.identities))return 'unreadable';
 return snapshot.identities.filter(row=>row.role==='core'||row.role==='mcp').map(row=>{
  const ticks=[row.creation_ticks,row.receipt_ticks];
  const delta=ticks.every(v=>typeof v==='string'&&/^[0-9]{1,20}$/.test(v))?(Number(BigInt(ticks[0])-BigInt(ticks[1]))/10000).toFixed(2):'none';
  return row.role+':exited='+row.has_exited+',after_receipt='+row.started_after_receipt+',start_minus_receipt_ms='+delta+',ticks_match='+row.started_ticks_match;
 }).join(' ')||'none';
}
