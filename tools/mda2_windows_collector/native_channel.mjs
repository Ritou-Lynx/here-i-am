import path from 'node:path';
import { spawn } from 'node:child_process';
import { randomBytes } from 'node:crypto';
import { parseNativeFrame, initialNativeSignalState, reduceNativePacket, reject } from './signals.mjs';

export const channelNonce = () => randomBytes(32).toString('base64url');

export class NativeCollectorChannel {
  static async open({ broker, bindings, sessionId, nonce = channelNonce(), maxPendingFrames = 64,
    maxPendingAllocationsPerSource = 8 }) {
    if (!broker || !Array.isArray(bindings) || !Number.isSafeInteger(maxPendingFrames) || maxPendingFrames < 1) {
      reject('invalid_native_channel');
    }
    const opened = await broker.openNativeChannel(bindings,{nonce,sessionId});
    const channel = new NativeCollectorChannel();
    channel.broker=broker; channel.token=opened.token; channel.nonce=nonce; channel.epoch=opened.epoch;
    channel.sessionId=sessionId; channel.maxPendingFrames=maxPendingFrames; channel.pendingFrames=0;
    channel.maxPendingAllocationsPerSource=maxPendingAllocationsPerSource;
    channel.sourceChains=new Map();channel.sourcePending=new Map();
    channel.state=initialNativeSignalState({nonce,epoch:opened.epoch,sessionId}); channel.chain=Promise.resolve();
    return channel;
  }
  submit(line, prepare) {
    if (this.closed) return Promise.reject(new Error('native_channel_closed'));
    if (this.pendingFrames >= this.maxPendingFrames) {
      this.closed=true; this.broker.closeNativeChannel(this.token);
      return Promise.reject(new Error('native_pending_overflow'));
    }
    this.pendingFrames++;
    const operation=this.chain.then(async()=>{
      try {
        const packet=parseNativeFrame(line);
        const reduced=reduceNativePacket(this.state,packet);
        const prepared=reduced.fact?prepare(reduced.fact,packet):null;
        if(prepared&&(!prepared.observation||typeof prepared.allocate!=='function'))reject('invalid_native_consumer');
        const source=reduced.fact?.source;
        if(source&&(this.sourcePending.get(source)??0)>=this.maxPendingAllocationsPerSource)reject('native_allocation_overflow');
        const proof=await this.broker.captureNativePacket(this.token,packet,prepared?.observation??null);
        this.state=reduced.state;
        let allocation=Promise.resolve(null);
        if(prepared){
          this.sourcePending.set(source,(this.sourcePending.get(source)??0)+1);
          const prior=this.sourceChains.get(source)??Promise.resolve();
          allocation=prior.then(()=>prepared.allocate(proof)).finally(()=>this.sourcePending.set(source,this.sourcePending.get(source)-1));
          this.sourceChains.set(source,allocation.catch(()=>{}));
        }
        return {packet,fact:reduced.fact,allocation};
      } catch(error) {
        this.closed=true;this.broker.closeNativeChannel(this.token);throw error;
      }
    }).finally(()=>{this.pendingFrames--;});
    this.chain=operation.catch(()=>{});
    return operation;
  }
  async close() {
    if(this.closed)return;
    this.closed=true; await this.chain; await Promise.allSettled([...this.sourceChains.values()]); this.broker.closeNativeChannel(this.token);
  }
}

export class NativeCollectorProcess {
  constructor({ executable, channel, onFrame, mode = 'disabled', maxBufferedBytes = 4096 }) {
    if (mode === 'disabled') reject('native_collection_disabled');
    if (!['synthetic','production-explicit'].includes(mode) || typeof onFrame !== 'function'
      ||!Number.isSafeInteger(maxBufferedBytes)||maxBufferedBytes<1024||maxBufferedBytes>1024*1024) reject('invalid_native_process');
    this.executable=path.resolve(executable);this.channel=channel;this.onFrame=onFrame;this.mode=mode;
    this.maxBufferedBytes=maxBufferedBytes;this.frameErrors=[];this.frames=0;
  }
  async start({ productionAuthorized = false, readyTimeoutMs = 5000 } = {}) {
    if(this.child)reject('native_process_started');
    if(this.mode==='production-explicit' && productionAuthorized!==true)reject('real_collection_not_authorized');
    const argument=this.mode==='synthetic'?'--synthetic':'--production-explicit';
    const child=spawn(this.executable,[argument],{windowsHide:true,stdio:['pipe','pipe','pipe'],
      env:{SystemRoot:process.env.SystemRoot,WINDIR:process.env.WINDIR,TEMP:process.env.TEMP,TMP:process.env.TMP,
        PATH:path.join(process.env.SystemRoot,'System32')}});
    this.child=child;this.stderr='';this.pending=new Set();this.buffer=Buffer.alloc(0);this.terminal=false;
    let resolveReady,rejectReady,ready=false,exitCode=null,exitSignal=null,spawnError=null,finished=false;
    const readiness=new Promise((resolve,reject)=>{resolveReady=resolve;rejectReady=reject;});
    const finish=()=>{if(finished)return;finished=true;if(!ready)rejectReady(new Error(spawnError??'native_process_exited_before_ready'));
      this.resolveExited({code:exitCode,signal:exitSignal,pid:child.pid??null,frames:this.frames,frameErrors:[...this.frameErrors],spawnError});};
    const terminate=(code)=>{if(this.terminal)return;this.terminal=true;this.frameErrors.push(code);child.stdout.pause();
      if(child.stdin.writable)child.stdin.end('CLOSE\n');setTimeout(()=>{if(!finished)child.kill();},2000).unref();};
    child.stderr.on('data',(chunk)=>{if(this.stderr.length<2048)this.stderr+=(chunk.toString().slice(0,2048-this.stderr.length));});
    child.stdout.on('data',(chunk)=>{
      if(this.terminal)return;
      this.buffer=Buffer.concat([this.buffer,chunk]);
      if(this.buffer.length>this.maxBufferedBytes){terminate('native_stdout_overflow');return;}
      let newline;
      while((newline=this.buffer.indexOf(10))>=0&&!this.terminal){
        let bytes=this.buffer.subarray(0,newline);this.buffer=this.buffer.subarray(newline+1);if(bytes.at(-1)===13)bytes=bytes.subarray(0,-1);
        if(bytes.length>1024){terminate('native_frame_too_large');break;}
        const line=bytes.toString('ascii');
        if(!ready){const expected=`READY|${this.channel.nonce}|${this.channel.epoch}|${this.channel.sessionId}`;
          if(line!==expected){terminate('native_ready_rejected');rejectReady(new Error('native_ready_rejected'));break;}
          ready=true;resolveReady({pid:child.pid,mode:this.mode});continue;}
        this.frames++;
        const pending=Promise.resolve(this.onFrame(line)).catch((error)=>{terminate(/^[a-z_0-9]+$/.test(error.message)?error.message:'native_frame_rejected');throw error;});
        this.pending.add(pending);pending.finally(()=>this.pending.delete(pending)).catch(()=>{});
      }
    });
    child.stdout.on('error',()=>terminate('native_stdout_failed'));
    child.stdin.on('error',()=>terminate('native_stdin_failed'));
    child.once('error',(error)=>{spawnError=error.code==='ENOENT'?'native_executable_missing':'native_spawn_failed';rejectReady(new Error(spawnError));});
    child.once('exit',(code,signal)=>{exitCode=code;exitSignal=signal;});
    this.exited=new Promise((resolve)=>{this.resolveExited=resolve;child.once('close',finish);});
    child.stdin.write(`HELLO|${this.channel.nonce}|${this.channel.epoch}|${this.channel.sessionId}\n`);
    let readyTimer;
    try{return await Promise.race([readiness,new Promise((_,reject)=>{readyTimer=setTimeout(()=>reject(new Error('native_ready_timeout')),readyTimeoutMs);})]);}
    finally{clearTimeout(readyTimer);}
  }
  emitSynthetic({source,kind,captureAge,captureWall,sessionId=this.channel.sessionId,qualityEpoch=0,value=''}) {
    if(this.mode!=='synthetic'||!this.child?.stdin.writable)reject('synthetic_native_unavailable');
    const fields=['EMIT',source,kind,captureAge,captureWall,sessionId,qualityEpoch,value];
    if(fields.some((value)=>String(value).includes('|')))reject('synthetic_command_rejected');
    this.child.stdin.write(fields.join('|')+'\n');
  }
  emitRawSynthetic(count) {
    if(this.mode!=='synthetic'||!Number.isSafeInteger(count)||count<1||count>65536||!this.child?.stdin.writable)reject('synthetic_native_unavailable');
    this.child.stdin.write(`RAW|${count}\n`);
  }
  async close({ timeoutMs = 5000 } = {}) {
    if(!this.child)return null;
    if(this.child.exitCode===null&&this.child.signalCode===null&&this.child.stdin.writable)this.child.stdin.end('CLOSE\n');
    let result=await Promise.race([this.exited,new Promise((resolve)=>setTimeout(()=>resolve(null),timeoutMs))]);
    if(!result){this.child.kill();result=await this.exited;}
    await Promise.allSettled([...this.pending]);
    return result;
  }
}
