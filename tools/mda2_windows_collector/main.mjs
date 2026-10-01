import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const mode=process.argv[2]??'--status';
if(mode==='--status'){
  process.stdout.write(JSON.stringify({mode:'disabled',real_os_collection:false,transport_configured:false,
    startup_registered:false,production_pairing:false})+'\n');
}else if(mode==='--verify-synthetic'){
  const child=spawn(process.execPath,[fileURLToPath(new URL('./fixtures/run_tests.mjs',import.meta.url))],
    {windowsHide:true,stdio:'inherit'});
  child.once('error',()=>{process.exitCode=70;});
  child.once('exit',(code,signal)=>{process.exitCode=signal?70:(code??70);});
}else{
  process.stderr.write('collector_mode_rejected\n');process.exitCode=64;
}
