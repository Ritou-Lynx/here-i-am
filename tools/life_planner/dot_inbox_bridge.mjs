// Strict, inert boundary for a caller-supplied dot planning receipt. This file
// never reads/watches inbox/, chooses a principal, signs an action, or starts a
// service. The source receipt is a proposal until a trusted UI fixes and signs
// the complete Core capture intent.
import { createHash } from 'node:crypto';
import { canonicalJSON, DOMAIN_POLICY } from '../i_core/domain_store.mjs';
import { FileTrustedTransferLedger, TrustedStatusBridgeError } from './trusted_status_bridge.mjs';

const object=value=>value!==null&&typeof value==='object'&&!Array.isArray(value);
const exact=(value,fields)=>object(value)&&Object.keys(value).length===fields.length&&fields.every(k=>Object.hasOwn(value,k));
const idPattern=/^[a-zA-Z0-9][a-zA-Z0-9_.:-]{0,199}$/;
const uuidPattern=/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const timestampPattern=/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/;
const filePattern=/^(\d{4}-\d{2}-\d{2})-(\d{2})(\d{2})\.md$/;
const headerPattern=/^【规划回执】(\d{4}-\d{2}-\d{2}) (\d{2}):(\d{2}) (过单|收工|记事)$/;
const sections=['容量','决定','完成','卡住','改动','捕获'];
const proposalFields=['schema_version','proposal_id','receipt_name','receipt_digest','receipt_kind','capture','status'];
const captureFields=['text','source','recorded_at'];
const bindingFields=['core_instance_id','principal_id','credential_generation','installation_id'];
const transferFields=['schema_version','transfer_id','proposal','binding','intent'];
const intentFields=['domain_protocol_version','core_instance_id','schema_version','op_id','id','kind','base_revision',
  'created_at','expires_at','actor','authorization_ref','data','provenance'];
const receiptFields=['receipt_id','core_instance_id','authority_mode','epoch','domain','accepted_op_id','principal_id',
  'accepted_at','policy_version','targets','change_sequences','receipt_auth'];
const transportBrand=Symbol('trusted-dot-core-transport');

const fail=(code,options)=>{throw new TrustedStatusBridgeError(code,options);};
const digest=value=>createHash('sha256').update(value).digest('hex');
const canonicalDigest=value=>digest(Buffer.from(canonicalJSON(value),'utf8'));
const id=value=>typeof value==='string'&&idPattern.test(value);
const timestamp=value=>typeof value==='string'&&timestampPattern.test(value)&&Number.isFinite(Date.parse(value));

function localRecordedAt(date,hour,minute) {
  const raw=`${date}T${hour}:${minute}:00+08:00`, parsed=new Date(raw);
  if (!Number.isFinite(parsed.getTime())) fail('invalid_dot_receipt_time');
  const local=new Date(parsed.getTime()+8*3600000);
  if (local.toISOString().slice(0,16)!==`${date}T${hour}:${minute}`) fail('invalid_dot_receipt_time');
  return parsed.toISOString();
}

function parseReceipt(receiptName,text) {
  const file=filePattern.exec(receiptName??'');
  if (!file||typeof text!=='string'||text.length<1||text.length>16000||text.includes('\0')||text.startsWith('\uFEFF')
    || /\r(?!\n)/.test(text)||/\n\n$/.test(text)) fail('invalid_dot_receipt');
  const lines=text.split(/\r?\n/);if(lines.at(-1)==='')lines.pop();
  const header=headerPattern.exec(lines.shift()??'');
  if(!header||header[1]!==file[1]||header[2]!==file[2]||header[3]!==file[3])fail('dot_receipt_identity_mismatch');
  const parsed={};
  for(const section of sections){
    if(lines.shift()!==`${section}：`)fail('invalid_dot_receipt_shape');
    const rows=[];
    while(lines.length&& !sections.some(next=>lines[0]===`${next}：`))rows.push(lines.shift());
    if(rows.length===0||rows.some(row=>row===''||row.trim()!==row))fail('invalid_dot_receipt_shape');
    if(rows.length===1&&rows[0]==='无')parsed[section]=[];
    else {
      if(rows.some(row=>!row.startsWith('- ')||row.length===2||row==='- 无'))fail('invalid_dot_receipt_shape');
      parsed[section]=rows.map(row=>row.slice(2));
    }
  }
  if(lines.length)fail('invalid_dot_receipt_shape');
  return {kind:header[4],recordedAt:localRecordedAt(header[1],header[2],header[3]),sections:parsed};
}

export function createDotInboxProposal({receiptName,text}) {
  const parsed=parseReceipt(receiptName,text),receiptDigest=digest(Buffer.from(text,'utf8'));
  const proposalId=`dot:${canonicalDigest({receipt_name:receiptName,receipt_digest:receiptDigest})}`;
  return {schema_version:1,proposal_id:proposalId,receipt_name:receiptName,receipt_digest:receiptDigest,
    receipt_kind:parsed.kind,capture:{text,source:'dot',recorded_at:parsed.recordedAt},status:'approval_required'};
}

function validateBinding(binding) {
  if(!exact(binding,bindingFields)||!id(binding.core_instance_id)||!id(binding.principal_id)||!id(binding.installation_id)
    ||!Number.isSafeInteger(binding.credential_generation)||binding.credential_generation<1)fail('invalid_transfer_binding');
}

function validateProposal(proposal) {
  if(!exact(proposal,proposalFields)||proposal.schema_version!==1||!id(proposal.proposal_id)
    ||typeof proposal.receipt_digest!=='string'||!/^[a-f0-9]{64}$/.test(proposal.receipt_digest)
    ||!['过单','收工','记事'].includes(proposal.receipt_kind)||proposal.status!=='approval_required'
    ||!exact(proposal.capture,captureFields)||proposal.capture.source!=='dot'||!timestamp(proposal.capture.recorded_at)) {
    fail('invalid_dot_proposal');
  }
  const rebuilt=createDotInboxProposal({receiptName:proposal.receipt_name,text:proposal.capture.text});
  if(canonicalJSON(rebuilt)!==canonicalJSON(proposal))fail('dot_proposal_changed');
}

function validateIntent(intent,proposal) {
  if(!exact(intent,intentFields)||intent.domain_protocol_version!==1||intent.schema_version!==1
    ||!uuidPattern.test(intent.op_id??'')||!uuidPattern.test(intent.id??'')||intent.op_id===intent.id
    ||intent.kind!=='create'||intent.base_revision!==0||intent.actor!=='user_direct'
    ||!timestamp(intent.created_at)||!timestamp(intent.expires_at)||typeof intent.authorization_ref!=='string'
    ||intent.authorization_ref.length<1||intent.authorization_ref.length>4096
    ||!exact(intent.data,captureFields)||canonicalJSON(intent.data)!==canonicalJSON(proposal.capture)
    ||!exact(intent.provenance,['source','source_refs','import_batch_id'])||intent.provenance.source!=='dot'
    ||canonicalJSON(intent.provenance.source_refs)!==canonicalJSON([proposal.proposal_id])
    ||intent.provenance.import_batch_id!==null)fail('invalid_dot_capture_intent');
  const created=Date.parse(intent.created_at),expires=Date.parse(intent.expires_at);
  if(expires<=created||expires-created>DOMAIN_POLICY.intentTtl)fail('invalid_intent_window');
}

function validateTransfer(raw,expectedBinding) {
  if(!exact(raw,transferFields)||raw.schema_version!==1||!object(raw.intent)||raw.transfer_id!==raw.intent.op_id)
    fail('invalid_dot_transfer');
  validateProposal(raw.proposal);validateBinding(raw.binding);validateBinding(expectedBinding);validateIntent(raw.intent,raw.proposal);
  if(canonicalJSON(raw.binding)!==canonicalJSON(expectedBinding)||raw.intent.core_instance_id!==expectedBinding.core_instance_id)
    fail('transfer_binding_changed');
  return structuredClone(raw);
}

function deepFreeze(value){if(!object(value)&&!Array.isArray(value))return value;for(const child of Object.values(value))deepFreeze(child);return Object.freeze(value);}

function validateCoreResult(raw,transfer) {
  const result=raw?.body?.found===true?raw.body.result:raw?.body;
  if(!object(result)||result.domain_protocol_version!==1||result.domain!=='captures'||result.op_id!==transfer.intent.op_id
    ||!['accepted','duplicate'].includes(result.outcome)||!exact(result.receipt,receiptFields))fail('invalid_core_capture_result');
  const receipt=result.receipt,target=receipt.targets?.[0];
  if(!id(receipt.receipt_id)||receipt.core_instance_id!==transfer.binding.core_instance_id||receipt.authority_mode!=='single_host'
    ||receipt.epoch!==null||receipt.domain!=='captures'||receipt.accepted_op_id!==transfer.intent.op_id
    ||receipt.principal_id!==transfer.binding.principal_id||!timestamp(receipt.accepted_at)||!id(receipt.policy_version)
    ||!/^[a-f0-9]{64}$/.test(receipt.receipt_auth??'')||!Array.isArray(receipt.change_sequences)
    ||receipt.change_sequences.some(value=>!Number.isSafeInteger(value)||value<1)||receipt.targets?.length!==1
    ||!exact(target,['id','revision'])||target.id!==transfer.intent.id||target.revision!==1)fail('invalid_core_capture_receipt');
  return {outcome:result.outcome,receipt:structuredClone(receipt)};
}

export function createTrustedDotCoreTransport({getOperation,submitOperation}) {
  if(typeof getOperation!=='function'||typeof submitOperation!=='function')throw new Error('invalid_trusted_core_transport');
  return Object.freeze({[transportBrand]:true,getOperation,submitOperation});
}

export class DotInboxCaptureBridge {
  constructor({binding,transport,ledger,clock=Date.now}) {
    validateBinding(binding);
    if(transport?.[transportBrand]!==true)throw new Error('untrusted_core_transport');
    if(!(ledger instanceof FileTrustedTransferLedger))throw new Error('invalid_transfer_ledger');
    if(typeof clock!=='function')throw new Error('invalid_bridge_clock');
    this.binding=structuredClone(binding);this.transport=transport;this.ledger=ledger;this.clock=clock;
  }
  async apply(raw) {
    const transfer=validateTransfer(raw,this.binding),envelopeDigest=canonicalDigest(transfer);
    const created=Date.parse(transfer.intent.created_at),expires=Date.parse(transfer.intent.expires_at),now=this.clock();
    if(!Number.isFinite(now)||now<created)fail('bridge_clock_invalid');
    const ledgerEnvelope={intent:transfer.intent,source:{capture_id:transfer.proposal.proposal_id,capture_revision:1}};
    const completed=await this.ledger.prepare(ledgerEnvelope,envelopeDigest);
    let lookup;
    try{lookup=await this.transport.getOperation(transfer.intent.op_id);}catch{fail('core_lookup_unknown',{retryable:true});}
    if(lookup?.state==='found'){
      const result=validateCoreResult(lookup.response,transfer);
      if(completed&&(completed.outcome!=='accepted'||canonicalJSON(completed.receipt)!==canonicalJSON(result.receipt)))
        fail('transfer_receipt_conflict');
      await this.ledger.complete(ledgerEnvelope,envelopeDigest,result);
      return {status:'complete',recovered:true,...result};
    }
    if(lookup?.state!=='not_found')fail('invalid_core_lookup');
    if(completed)fail('core_receipt_missing',{retryable:true});
    const submitNow=this.clock();
    if(!Number.isFinite(submitNow)||submitNow<created)fail('bridge_clock_invalid');
    if(submitNow>=expires)fail('intent_expired');
    let submitted;
    try{submitted=await this.transport.submitOperation(deepFreeze(structuredClone(transfer.intent)));}
    catch{fail('core_submit_unknown',{retryable:true});}
    const result=validateCoreResult(submitted,transfer);
    await this.ledger.complete(ledgerEnvelope,envelopeDigest,result);
    return {status:'complete',recovered:false,...result};
  }
}
