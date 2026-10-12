#!/usr/bin/env node
// Source-only candidate builder. Never loads runtime configuration or manages services.
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { existsSync, lstatSync, mkdirSync, readFileSync, realpathSync, writeFileSync } from 'node:fs';
import { dirname, isAbsolute, join, relative, resolve, sep } from 'node:path';
import { fileURLToPath } from 'node:url';

export const BASELINE_COMMIT = '3ce7aacc75615faf31aab7d4d902598070ffa898';
export const REPO_ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
const SOURCE_PREFIX = 'tools/i_core/test_fixtures/release_schema6/mcp_reader/legacy/';
export const SOURCE_INVENTORY = Object.freeze([
 ['i_remote_mcp/server.mjs','37f04a68147bd7a004fb97e7809c4a8171b081b9','adfc88126c6d7ee047fd7fed7eda6b3b536c9e1fe0baffafbedc290b6c5554d6',22374],
 ['i_remote_mcp/oauth.mjs','2597ddfe8a724812763595e2d4b43aadd65a5488','53dda48003b8b0b7da27c7a10895f31863398e1c42fe5e5ed017608f129755b5',19860],
 ['i_remote_mcp/diagnostics.mjs','0f78d2bbd75a250aec8ad6b53d6d8cbff90bd31d','b60230926d0fa8cbcf2cbfefa5667656190507d828fc953605837d8f04e5b4f7',5030],
 ['i_remote_mcp/mcp.mjs','6b1e0927ff81b9ae513259a6df0fb101e183586b','4bdd55dd3bd41e4ff0e16cdce08b2c58dce007d6fe6eaee51cc2110cdfc7d09b',20159],
 ['i_remote_mcp/writeback.mjs','3d4236b4b294f77b193e6c9030b96934e9e390f1','f2aac48db1cf61a44a0c9b5b28087b90894f03396cd52830a4428532944bc52a',29165],
 ['i_memory/i_memory_read.mjs','4181efc33dae883b56d1ec88ca3aad05a3a44cfa','cee185180b825a141b645a12ab1f1812a61b9eb7462c347465b7ac4449af4e28',21378],
].map(([path,blob,sha256,bytes])=>Object.freeze({path,blob,sha256,bytes})));
const MAIN_BLOBS = {server:'c598b7329f95517ba9bf30777882d8a1913eb7c0',oauth:'f95e05ced4a5cdc119062c4a1dc7f90cfb85fc40',mcp:'aa60d5ab40da538d8f77a4f19eec0bdf9fac094a'};
// Literal reviewed compatibility hunks. No patch is inferred from the caller's working tree.
const PATCHES = {
  "server": [
    [
      "import { OAuthServer, revokeAll, setPassphrase } from './oauth.mjs';\n",
      "import { OAuthServer, chatgptEnabledFromEnv, revokeAll, setPassphrase } from './oauth.mjs';\n"
    ],
    [
      "const DEFAULT_ALLOWED_ORIGINS = ['https://claude.ai', 'https://claude.com'];\n",
      "const DEFAULT_ALLOWED_ORIGINS = ['https://claude.ai', 'https://claude.com'];\nconst CHATGPT_ORIGIN = 'https://chatgpt.com';\nconst CHATGPT_CORS_HEADERS = ['accept', 'authorization', 'content-type', 'mcp-session-id', 'mcp-protocol-version'];\n"
    ],
    [
      "  allowedOrigins = DEFAULT_ALLOWED_ORIGINS,\n",
      "  allowedOrigins = DEFAULT_ALLOWED_ORIGINS,\n  chatgptEnabled = chatgptEnabledFromEnv(),\n"
    ],
    [
      "  const oauth = new OAuthServer({ stateDir, publicUrl, now, options: oauthOptions, writeEnabled });\n",
      "  const oauth = new OAuthServer({ stateDir, publicUrl, now, options: oauthOptions, writeEnabled, chatgptEnabled });\n"
    ],
    [
      "  const origins = new Set([...allowedOrigins, oauth.issuer]);\n",
      "  const origins = new Set([...allowedOrigins, oauth.issuer, ...(chatgptEnabled ? [CHATGPT_ORIGIN] : [])]);\n"
    ],
    [
      "    if (origin && !origins.has(origin)) return sendJson(res, 403, { error: 'forbidden_origin' });\n",
      "    if (origin && !origins.has(origin)) return sendJson(res, 403, { error: 'forbidden_origin' });\n    // Only the explicitly enabled exact ChatGPT origin gets browser CORS.\n    // OPTIONS discloses no data; every actual MCP request still needs OAuth.\n    if (chatgptEnabled && origin === CHATGPT_ORIGIN) {\n      res.setHeader('Access-Control-Allow-Origin', CHATGPT_ORIGIN);\n      res.setHeader('Vary', 'Origin');\n      res.setHeader('Access-Control-Expose-Headers', 'Mcp-Session-Id, WWW-Authenticate');\n      if (req.method === 'OPTIONS') {\n        const method = req.headers['access-control-request-method'];\n        const headers = String(req.headers['access-control-request-headers'] ?? '')\n          .split(',').map((value) => value.trim().toLowerCase()).filter(Boolean);\n        if (!['POST', 'DELETE'].includes(method) || headers.some((value) => !CHATGPT_CORS_HEADERS.includes(value))) {\n          return sendJson(res, 403, { error: 'forbidden_preflight' });\n        }\n        res.setHeader('Access-Control-Allow-Methods', 'POST, DELETE');\n        res.setHeader('Access-Control-Allow-Headers', CHATGPT_CORS_HEADERS.join(', '));\n        return sendEmpty(res, 204);\n      }\n    }\n"
    ],
    [
      "  const publicUrl = args['public-url'] ?? process.env.I_REMOTE_MCP_PUBLIC_URL ?? `http://${host}:${port}`;\n",
      "  const publicUrl = args['public-url'] ?? process.env.I_REMOTE_MCP_PUBLIC_URL ?? `http://${host}:${port}`;\n  const chatgptEnabled = chatgptEnabledFromEnv();\n"
    ],
    [
      "    publicUrl,\n",
      "    publicUrl,\n    chatgptEnabled,\n"
    ]
  ],
  "oauth": [
    [
      "// 单用户最小 OAuth 2.1 授权服务器（claude.ai 自定义 connector 用）。\n",
      "// 单用户最小 OAuth 2.1 授权服务器（Claude 默认，ChatGPT 显式启用）。\n"
    ],
    [
      "export const WRITE_SCOPE = 'i.write';\n",
      "export const WRITE_SCOPE = 'i.write';\nexport const CHATGPT_CALLBACK_URI = 'https://chatgpt.com/connector_platform_oauth_redirect';\n"
    ],
    [
      "// 以后接 ChatGPT 等其他客户端时，用 I_REMOTE_MCP_EXTRA_REDIRECT_URIS（逗号分隔、精确匹配的 https 地址）追加。\n",
      "// ChatGPT 使用独立开关和稳定精确回调；其他客户端仍可显式追加精确 HTTPS 地址。\n"
    ],
    [
      "export function isAllowedRedirectUri(value, extra = extraRedirectUris()) {\n",
      "export function chatgptEnabledFromEnv(env = process.env) {\n  const value = env.I_REMOTE_MCP_CHATGPT_ENABLED;\n  if (value === undefined || value === '0') return false;\n  if (value === '1') return true;\n  throw new Error('invalid_chatgpt_mode');\n}\n\nexport function isAllowedRedirectUri(value, extra = extraRedirectUris(), chatgptEnabled = chatgptEnabledFromEnv()) {\n"
    ],
    [
      "  if (CLAUDE_AI_CALLBACKS.includes(value)) return true;\n",
      "  if (CLAUDE_AI_CALLBACKS.includes(value)) return true;\n  if (chatgptEnabled === true && value === CHATGPT_CALLBACK_URI) return true;\n"
    ],
    [
      "  constructor({ stateDir, publicUrl, now = () => Date.now(), options = {}, writeEnabled = false }) {\n",
      "  constructor({ stateDir, publicUrl, now = () => Date.now(), options = {}, writeEnabled = false, chatgptEnabled = chatgptEnabledFromEnv() }) {\n    if (typeof chatgptEnabled !== 'boolean') throw new Error('invalid_chatgpt_mode');\n    this.chatgptEnabled = chatgptEnabled;\n"
    ],
    [
      "      issuer: this.issuer,\n",
      "      issuer: this.issuer,\n      authorization_response_iss_parameter_supported: true,\n"
    ],
    [
      "    if (!redirectUris.every((uri) => isAllowedRedirectUri(uri))) {\n",
      "    if (!redirectUris.every((uri) => isAllowedRedirectUri(uri, extraRedirectUris(), this.chatgptEnabled))) {\n"
    ],
    [
      "    if (!redirectUri || !client.redirect_uris.includes(redirectUri) || !isAllowedRedirectUri(redirectUri)) {\n",
      "    if (!redirectUri || !client.redirect_uris.includes(redirectUri) || !isAllowedRedirectUri(redirectUri, extraRedirectUris(), this.chatgptEnabled)) {\n"
    ]
  ]
};
PATCHES.mcp = [['在 claude.ai 的 connector 设置里','在当前客户端的连接器设置里']];
export const sha256 = bytes => createHash('sha256').update(bytes).digest('hex');
const git = args => execFileSync('git', args, {cwd:REPO_ROOT, windowsHide:true, maxBuffer:1024*1024});

function textFormat(bytes) {
 assert.ok(Buffer.isBuffer(bytes), 'source must be a Buffer');
 const text=bytes.toString('utf8');assert.ok(Buffer.from(text).equals(bytes),'source must be exact UTF-8');
 const eol=text.includes('\r\n')?'\r\n':'\n';
 assert.ok(!text.replaceAll('\r\n','').includes('\r'),'unsupported source CR');
 if(eol==='\r\n')assert.ok(!text.replaceAll('\r\n','').includes('\n'),'mixed source line endings');
 return {text:text.replaceAll('\r\n','\n'),eol};
}
function applyPatches(bytes, name, reverse=false) {
 const {text,eol}=textFormat(bytes);let result=text;
 const patches=reverse?[...PATCHES[name]].reverse().map(([a,b])=>[b,a]):PATCHES[name];
 for(const [before,after] of patches) {
  assert.equal(result.split(before).length,2,'compatibility patch must match exactly once: '+name);
  result=result.replace(before,after);
 }
 return Buffer.from(result.replaceAll('\n',eol));
}

export function readCandidateInputs() {
 const baselineFiles={};
 for(const item of SOURCE_INVENTORY) {
  const ref=BASELINE_COMMIT+':'+SOURCE_PREFIX+item.path;
  assert.equal(git(['rev-parse',ref]).toString().trim(),item.blob,'fixed source blob mismatch');
  baselineFiles[item.path]=git(['cat-file','blob',ref]);
 }
 const baselineMain={}, current={};
 for(const name of ['server','oauth','mcp']) {
  const path='tools/i_remote_mcp/'+name+'.mjs';
  assert.equal(git(['rev-parse',BASELINE_COMMIT+':'+path]).toString().trim(),MAIN_BLOBS[name]);
  baselineMain[name]=git(['cat-file','blob',BASELINE_COMMIT+':'+path]);
  current[name]=readFileSync(join(REPO_ROOT,path));
 }
 return {baselineCommit:BASELINE_COMMIT,baselineFiles,baselineMain,current,sourceCommit:git(['rev-parse','HEAD']).toString().trim()};
}

export function constructCandidateSources({baselineCommit,baselineFiles,baselineMain,current,sourceCommit}) {
 assert.equal(baselineCommit,BASELINE_COMMIT,'wrong baseline commit');
 assert.deepEqual(Object.keys(baselineFiles).sort(),SOURCE_INVENTORY.map(x=>x.path).sort(),'exact six-file closure required');
 const files={};
 for(const item of SOURCE_INVENTORY) {
  const bytes=baselineFiles[item.path];
  assert.ok(Buffer.isBuffer(bytes)&&bytes.length===item.bytes&&sha256(bytes)===item.sha256,'baseline byte mismatch: '+item.path);
  files[item.path]=Buffer.from(bytes);
 }
 for(const name of ['server','oauth','mcp']) {
  const base=baselineMain[name];
  const blob=createHash('sha1').update(Buffer.from('blob '+base.length+'\0')).update(base).digest('hex');
  assert.equal(blob,MAIN_BLOBS[name],'wrong mainline baseline blob');
  // Git stores LF while Windows checkouts may use CRLF. Preserve and explicitly
  // account for that representation, then require byte-exact current-source match.
  const format=textFormat(current[name]);
  const represented=Buffer.from(textFormat(base).text.replaceAll('\n',format.eol));
  assert.ok(applyPatches(represented,name).equals(current[name]),'unexpected current '+name+' source delta');
  const path='i_remote_mcp/'+name+'.mjs';
  if(name==='oauth')assert.equal(textFormat(base).text,textFormat(files[path]).text,'OAuth baseline semantic mismatch');
  files[path]=applyPatches(files[path],name);
  assert.ok(applyPatches(files[path],name,true).equals(baselineFiles[path]),'reverse patch must restore exact source bytes');
 }
 for(const bytes of Object.values(files))assert.ok(!/domain_tools|personal_data_domains|coreRemember|domain-config/.test(bytes.toString()),'W3 domain source forbidden');
 const manifest={schema_version:1,status:'not_deployed',baseline_commit:BASELINE_COMMIT,source_commit:sourceCommit,
  source_prefix:SOURCE_PREFIX,chatgpt_flag:{name:'I_REMOTE_MCP_CHATGPT_ENABLED',default:'0'},
  entry:'i_remote_mcp/server.mjs',changed_files:3,unchanged_files:3,
  source_sha256:Object.fromEntries(Object.entries(current).map(([name,bytes])=>[name,sha256(bytes)])),
  files:SOURCE_INVENTORY.map(item=>({path:item.path,source_blob:item.blob,base_sha256:item.sha256,
   result_sha256:sha256(files[item.path]),bytes:files[item.path].length,changed:sha256(files[item.path])!==item.sha256}))};
 assert.equal(manifest.files.filter(x=>x.changed).length,3);
 return {files,manifest};
}

export function validateOutputDirectory(outputDirectory) {
 assert.ok(typeof outputDirectory==='string'&&outputDirectory.length>0,'output directory required');
 const raw=isAbsolute(outputDirectory)?relative(REPO_ROOT,outputDirectory):outputDirectory;
 const parts=raw.split(/[\\/]/);
 assert.ok(parts.length>=2&&parts[0]==='build','output must be a new directory under checkout/build');
 for(const part of parts)assert.ok(/^[A-Za-z0-9][A-Za-z0-9._-]*$/.test(part)&&!/[. ]$/.test(part)&&! /^(con|prn|aux|nul|com[1-9]|lpt[1-9])(?:\.|$)/i.test(part),'output path aliases forbidden');
 const root=resolve(REPO_ROOT,...parts);
 if(isAbsolute(outputDirectory))assert.equal(outputDirectory,root,'noncanonical absolute output path');
 assert.equal(realpathSync(REPO_ROOT),REPO_ROOT,'checkout alias forbidden');
 let path=REPO_ROOT;
 for(const part of parts) {
  path=join(path,part);
  if(existsSync(path)) {assert.ok(!lstatSync(path).isSymbolicLink(),'output links forbidden');assert.equal(realpathSync(path),path,'output aliases forbidden');assert.ok(lstatSync(path).isDirectory(),'output parent must be directory');}
  else {try{lstatSync(path);assert.fail('output links forbidden');}catch(error){if(error.code!=='ENOENT')throw error;}}
 }
 assert.ok(!existsSync(root),'output already exists');
 return {outputRoot:root,root:join(root,'runtime'),manifestPath:join(root,'manifest.json')};
}

export function buildChatgptCandidate({outputDirectory}={}) {
 let output=validateOutputDirectory(outputDirectory);
 const {files,manifest}=constructCandidateSources(readCandidateInputs());
 mkdirSync(dirname(output.outputRoot),{recursive:true});
 output=validateOutputDirectory(outputDirectory);
 mkdirSync(output.outputRoot); // Exclusive directory creation; never overwrite a candidate.
 mkdirSync(output.root);
 for(const folder of ['i_remote_mcp','i_memory'])mkdirSync(join(output.root,folder));
 for(const [path,bytes] of Object.entries(files))writeFileSync(join(output.root,path),bytes,{flag:'wx'});
 writeFileSync(output.manifestPath,JSON.stringify(manifest,null,2)+'\n',{flag:'wx'});
 for(const item of manifest.files)assert.equal(sha256(readFileSync(join(output.root,item.path))),item.result_sha256);
 return {...output,entryPath:join(output.root,manifest.entry),manifest};
}

if(process.argv[1]&&resolve(process.argv[1])===fileURLToPath(import.meta.url)) {
 try {
  const args=process.argv.slice(2);if(args[0]==='build')args.shift();
  if(args[0]==='--out')args.shift();
  assert.ok(args.length===1,'usage: node chatgpt_candidate.mjs [build] --out build/<new-name>');
  const result=buildChatgptCandidate({outputDirectory:args[0]});
  process.stdout.write(JSON.stringify({status:'not_deployed',root:result.root,manifest:result.manifestPath})+'\n');
 } catch(error) {process.stderr.write(error.message+'\n');process.exitCode=1;}
}
