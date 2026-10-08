// Policy A: authority is the exact user message already accepted by this Core.
// This does not search recent chat, infer consent from text, or use Ed25519 prompts.
export function createWebUserMessageAuthorizationVerifier({coreInstanceId,getDatabase,principals}={}) {
  const id=v=>typeof v==='string'&&/^[A-Za-z0-9][A-Za-z0-9_.:-]{0,199}$/.test(v);
  if(!id(coreInstanceId)||typeof getDatabase!=='function'||!Array.isArray(principals)
    ||principals.some(p=>!p||Object.keys(p).sort().join(',')!=='character_id,installation_id,origin_device_id,principal_id'
      ||Object.values(p).some(v=>!id(v)))
    ||new Set(principals.map(p=>p.principal_id)).size!==principals.length)throw new Error('invalid_web_message_configuration');
  const configured=new Map(principals.map(p=>[p.principal_id,Object.freeze({...p})]));
  return ({principal,request,domain,authorizationRef}={})=>{
    const binding=configured.get(principal?.principal_id);
    if(!binding||domain!=='captures'||request?.actor!=='user_via_agent'
      ||request.core_instance_id!==coreInstanceId||principal.installation_id!==binding.installation_id
      ||principal.device_id!==binding.origin_device_id||!id(authorizationRef))return false;
    const anchor=/^claude_web:(t_[A-Za-z0-9_-]{8,48}):([1-9][0-9]*)$/.exec(authorizationRef);
    if(!anchor||!Number.isSafeInteger(Number(anchor[2]))||request.trigger_thread_id!==anchor[1]
      ||request.trigger_sync_id!==authorizationRef)return false;
    try {
      const db=getDatabase();
      if(db.prepare("SELECT value FROM core_metadata WHERE key='node_id'").get()?.value!==coreInstanceId)return false;
      const row=db.prepare('SELECT origin_device_id,character_id,sender,message_type FROM chat_messages WHERE sync_id=?').get(authorizationRef);
      if(!row||row.origin_device_id!==binding.origin_device_id||row.character_id!==binding.character_id
        ||row.sender!=='user'||row.message_type!=='chat')return false;
      // Validate this exact turn, never select a replacement from recent chat.
      // An end reply or newer turn closes the anchor only in its own thread.
      const prefix=`claude_web:${anchor[1]}:`;
      return !db.prepare('SELECT 1 FROM chat_messages WHERE origin_device_id=? AND character_id=? AND sync_id GLOB ? AND CAST(substr(sync_id,?) AS INTEGER)>? LIMIT 1')
        .get(binding.origin_device_id,binding.character_id,`${prefix}*`,prefix.length+1,Number(anchor[2]));
    }catch{return false;}
  };
}
