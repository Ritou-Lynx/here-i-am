import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile, writeFile, mkdtemp, mkdir, rm, readdir } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawn } from 'node:child_process';

const runner = fileURLToPath(new URL('../run-daily.ps1', import.meta.url));
const quotePS = value => `'${value.replaceAll("'", "''")}'`;
const fakeDaily = `import fs from 'node:fs';
const role=process.argv[2], args=process.argv.slice(3);
const step=role==='node'?args[1]:'codex';
fs.appendFileSync(process.env.TEST_DAILY_LOG,JSON.stringify({step,args})+'\\n');
process.stderr.write('synthetic stderr');
process.exit(Number(process.env['TEST_DAILY_'+step.toUpperCase()+'_EXIT']||0));
`;

for (const [failedStep, expectedSteps, exit] of [
  ['none',['pull','codex','push'],0],['pull',['pull'],7],['codex',['pull','codex'],8],['push',['pull','codex','push'],9],
]) test(`PS 5.1 daily runner synthetic stages: ${failedStep}`,{skip:process.platform!=='win32'},async t=>{
  const root=await mkdtemp(path.join(tmpdir(),'feishu-daily-'));
  t.after(async()=>{assert.equal(path.dirname(root),path.resolve(tmpdir()));await rm(root,{recursive:true,force:true});});
  const study=path.join(root,'study'),tool=path.join(root,'tool'),config=path.join(tool,'config.json');
  await mkdir(study);await mkdir(tool);await writeFile(config,JSON.stringify({model:'TEST_MODEL'}));
  const script=path.join(root,'fake.mjs'),fakeNode=path.join(root,'fake-node.cmd'),fakeCodex=path.join(root,'fake-codex.cmd');
  await writeFile(script,fakeDaily);
  for(const [file,role] of [[fakeNode,'node'],[fakeCodex,'codex']]) {
    await writeFile(file,`@echo off\r\n"${process.execPath}" "${script}" ${role} %*\r\nexit /b %errorlevel%\r\n`);
  }
  const log=path.join(root,'calls.jsonl');await writeFile(log,'');
  const code=`& ${quotePS(runner)} -StudyDirectory ${quotePS(study)} -ConfigPath ${quotePS(config)} -NodeExecutable ${quotePS(fakeNode)} -CodexExecutable ${quotePS(fakeCodex)}\nexit $LASTEXITCODE`;
  const env={...process.env,TEST_DAILY_LOG:log,TEST_DAILY_PULL_EXIT:'0',TEST_DAILY_CODEX_EXIT:'0',TEST_DAILY_PUSH_EXIT:'0'};
  if(failedStep!=='none')env['TEST_DAILY_'+failedStep.toUpperCase()+'_EXIT']=String(exit);
  const actual=await new Promise((resolve,reject)=>{
    const child=spawn('powershell.exe',['-NoProfile','-NonInteractive','-EncodedCommand',Buffer.from(code,'utf16le').toString('base64')],{env,shell:false});
    let stderr='';child.stdout.resume();child.stderr.setEncoding('utf8');child.stderr.on('data',s=>stderr+=s);
    child.once('error',reject);child.once('close',exit=>resolve({exit,stderr}));
  });
  assert.equal(actual.exit,exit,actual.stderr);
  const calls=(await readFile(log,'utf8')).trim().split('\n').filter(Boolean).map(v=>JSON.parse(v));
  assert.deepEqual(calls.map(c=>c.step),expectedSteps);
  for(const call of calls.filter(c=>c.step!=='codex')) {
    assert.equal(call.args[0],path.join(path.dirname(runner),'sync','feishu_sync.mjs'));
    assert.equal(call.args[call.args.indexOf('--config')+1],config);
    assert.equal(call.args[call.args.indexOf('--state')+1],path.join(study,'state'));
  }
  const codex=calls.find(c=>c.step==='codex');
  if(codex) {
    assert.equal(codex.args[codex.args.indexOf('-s')+1],'workspace-write');
    assert.equal(codex.args[codex.args.indexOf('-C')+1],study);
    assert.equal(codex.args[codex.args.indexOf('-m')+1],'TEST_MODEL');
    assert.ok(codex.args.includes('sandbox_workspace_write.network_access=false'));
    assert.equal(codex.args.at(-1),'出今天的学习单');
  }
  const files=(await readdir(path.join(study,'logs'))).filter(n=>n.endsWith('.log'));
  assert.equal(files.length,1);
  const status=await readFile(path.join(study,'logs',files[0]),'utf8');
  assert.ok(!status.includes('synthetic stderr'));
  assert.ok(status.includes(failedStep==='none'?'daily_done':failedStep+'_failed:'+exit));
});

test('PS 5.1 resolves a bare name to the .cmd when npm also installs an extensionless script',{skip:process.platform!=='win32'},async t=>{
  const root=await mkdtemp(path.join(tmpdir(),'feishu-daily-'));
  t.after(async()=>{assert.equal(path.dirname(root),path.resolve(tmpdir()));await rm(root,{recursive:true,force:true});});
  const study=path.join(root,'study'),tool=path.join(root,'tool'),bin=path.join(root,'bin'),config=path.join(tool,'config.json');
  await mkdir(study);await mkdir(tool);await mkdir(bin);await writeFile(config,JSON.stringify({model:'TEST_MODEL'}));
  const script=path.join(root,'fake.mjs');await writeFile(script,fakeDaily);
  for(const role of ['node','codex']) {
    await writeFile(path.join(bin,`fake-${role}.cmd`),`@echo off\r\n"${process.execPath}" "${script}" ${role} %*\r\nexit /b %errorlevel%\r\n`);
    await writeFile(path.join(bin,`fake-${role}`),'#!/bin/sh\nexit 99\n');
  }
  const log=path.join(root,'calls.jsonl');await writeFile(log,'');
  const code=`& ${quotePS(runner)} -StudyDirectory ${quotePS(study)} -ConfigPath ${quotePS(config)} -NodeExecutable 'fake-node' -CodexExecutable 'fake-codex'\nexit $LASTEXITCODE`;
  const env={...process.env,PATH:bin+path.delimiter+process.env.PATH,TEST_DAILY_LOG:log,TEST_DAILY_PULL_EXIT:'0',TEST_DAILY_CODEX_EXIT:'0',TEST_DAILY_PUSH_EXIT:'0'};
  const actual=await new Promise((resolve,reject)=>{
    const child=spawn('powershell.exe',['-NoProfile','-NonInteractive','-EncodedCommand',Buffer.from(code,'utf16le').toString('base64')],{env,shell:false});
    let stderr='';child.stdout.resume();child.stderr.setEncoding('utf8');child.stderr.on('data',s=>stderr+=s);
    child.once('error',reject);child.once('close',exit=>resolve({exit,stderr}));
  });
  assert.equal(actual.exit,0,actual.stderr);
  const calls=(await readFile(log,'utf8')).trim().split('\n').filter(Boolean).map(v=>JSON.parse(v));
  assert.deepEqual(calls.map(c=>c.step),['pull','codex','push']);
});

for(const layout of ['same','tool_inside_study','study_inside_tool']) test(`PS 5.1 rejects overlapping directories: ${layout}`,{skip:process.platform!=='win32'},async t=>{
  const root=await mkdtemp(path.join(tmpdir(),'feishu-daily-'));
  t.after(async()=>{assert.equal(path.dirname(root),path.resolve(tmpdir()));await rm(root,{recursive:true,force:true});});
  const tool=path.join(root,'tool');await mkdir(tool);
  const config=path.join(tool,'config.json');await writeFile(config,JSON.stringify({model:'TEST_MODEL'}));
  const study=layout==='same'?tool:layout==='tool_inside_study'?root:path.join(tool,'study');
  await mkdir(study,{recursive:true});
  const code=`& ${quotePS(runner)} -StudyDirectory ${quotePS(study)} -ConfigPath ${quotePS(config)} -NodeExecutable 'must-not-run' -CodexExecutable 'must-not-run'\nexit $LASTEXITCODE`;
  const actual=await new Promise((resolve,reject)=>{
    const child=spawn('powershell.exe',['-NoProfile','-NonInteractive','-EncodedCommand',Buffer.from(code,'utf16le').toString('base64')],{shell:false});
    let stderr='';child.stdout.resume();child.stderr.setEncoding('utf8');child.stderr.on('data',s=>stderr+=s);
    child.once('error',reject);child.once('close',exit=>resolve({exit,stderr}));
  });
  assert.equal(actual.exit,1);assert.match(actual.stderr,/daily_layout_invalid/u);
  assert.ok(!(await readdir(study)).includes('logs'));
});

test('subject template is byte-identical and voice rules change only the contracted passages',async()=>{
  const origin=new URL('../../siyuan_tutor/',import.meta.url);
  assert.deepEqual(await readFile(new URL('../subjects.md',import.meta.url)),await readFile(new URL('subjects.md',origin)));
  const expected=(await readFile(new URL('TUTOR_RULES.md',origin),'utf8'))
    .replaceAll('~/siyuan-study/today.md','~/feishu-study/today.md')
    .replaceAll('%USERPROFILE%\\siyuan-study\\today.md','%USERPROFILE%\\feishu-study\\today.md')
    .replaceAll('~/siyuan-study/inbox/','%USERPROFILE%\\feishu-study\\inbox\\')
    .replace('先打开思源《动词て形》。','先打开学习单里的 [《动词て形》](<飞书文档链接>)。');
  assert.equal((await readFile(new URL('../TUTOR_RULES.md',import.meta.url),'utf8')).replaceAll('\r\n','\n'),expected.replaceAll('\r\n','\n'));
});
