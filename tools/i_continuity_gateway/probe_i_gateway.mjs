import { spawn } from 'node:child_process';
import { fileURLToPath, pathToFileURL } from 'node:url';

const serverPath = fileURLToPath(new URL('./i_mcp_server.mjs', import.meta.url));
const child = spawn(process.execPath, [serverPath], {
  cwd: process.cwd(),
  env: { ...process.env, I_WORKSPACE_ROOT: process.env.I_WORKSPACE_ROOT || process.cwd() },
  stdio: ['pipe', 'pipe', 'inherit'],
  windowsHide: true,
});

let nextId = 1;
let buffer = '';
const pending = new Map();

child.stdout.setEncoding('utf8');
child.stdout.on('data', (chunk) => {
  buffer += chunk;
  while (buffer.includes('\n')) {
    const index = buffer.indexOf('\n');
    const line = buffer.slice(0, index).trim();
    buffer = buffer.slice(index + 1);
    if (!line) continue;
    const message = JSON.parse(line);
    if (message.method === 'roots/list') {
      child.stdin.write(`${JSON.stringify({
        jsonrpc: '2.0',
        id: message.id,
        result: { roots: [{ uri: pathToFileURL(process.cwd()).href, name: 'active-project' }] },
      })}\n`);
      continue;
    }
    if (message.method === 'elicitation/create') {
      child.stdin.write(`${JSON.stringify({
        jsonrpc: '2.0',
        id: message.id,
        result: { action: 'accept', content: { confirmed: true } },
      })}\n`);
      continue;
    }
    const waiter = pending.get(message.id);
    if (!waiter) continue;
    pending.delete(message.id);
    if (message.error) waiter.reject(new Error(message.error.message));
    else waiter.resolve(message.result);
  }
});

function request(method, params = {}) {
  const id = nextId++;
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => {
      pending.delete(id);
      reject(new Error(`${method} timed out`));
    }, 10000);
    pending.set(id, {
      resolve: (value) => { clearTimeout(timer); resolve(value); },
      reject: (error) => { clearTimeout(timer); reject(error); },
    });
    child.stdin.write(`${JSON.stringify({ jsonrpc: '2.0', id, method, params })}\n`);
  });
}

try {
  const initialized = await request('initialize', {
    protocolVersion: '2025-06-18',
    capabilities: { roots: { listChanged: true }, elicitation: {} },
    clientInfo: { name: 'i-probe', version: '0.1.0' },
  });
  child.stdin.write(`${JSON.stringify({ jsonrpc: '2.0', method: 'notifications/initialized' })}\n`);
  const listed = await request('tools/list');
  const bootstrap = await request('tools/call', {
    name: 'i_bootstrap',
    arguments: { token_budget: 1400 },
  });
  const recalled = await request('tools/call', {
    name: 'i_recall_project',
    arguments: { query: '下一步 Project Memory', limit: 4 },
  });
  const overview = await request('tools/call', {
    name: 'i_get_project_overview',
    arguments: {},
  });
  console.log(JSON.stringify({
    server: initialized.serverInfo,
    tools: listed.tools.map((tool) => tool.name),
    bootstrap: bootstrap.structuredContent,
    recall: recalled.structuredContent || { error: recalled.content?.[0]?.text || 'unknown' },
    overview: overview.structuredContent,
  }, null, 2));
} finally {
  child.stdin.end();
}
