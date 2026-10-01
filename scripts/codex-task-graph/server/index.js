// HTTP server: static UI + read-only /api/* endpoints.
// Zero external deps so `node server/index.js` works straight after clone.

import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { scanSessions, buildForest } from './codex.js';
import { readOverlay, upsertNode, upsertEdge, deleteEdge } from './store.js';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const PUBLIC_DIR = path.join(__dirname, '..', 'public');
const PORT = Number(process.env.PORT ?? 47837);

const MIME = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.mjs': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.svg': 'image/svg+xml',
  '.png': 'image/png',
  '.ico': 'image/x-icon',
};

function json(res, code, data) {
  res.writeHead(code, { 'content-type': 'application/json; charset=utf-8' });
  res.end(JSON.stringify(data));
}

async function readBody(req) {
  const chunks = [];
  for await (const c of req) chunks.push(c);
  // Always decode as UTF-8 regardless of client Content-Type; browsers
  // and curl already send UTF-8, and PowerShell's Invoke-RestMethod defaults
  // to ISO-8859-1 unless told otherwise.
  const raw = Buffer.concat(chunks).toString('utf8');
  try {
    return raw ? JSON.parse(raw) : {};
  } catch {
    return null;
  }
}

// Cache between refresh requests; invalidated when user hits rescan.
let cache = { at: 0, threads: null };

async function getThreads({ force = false, limit = 3000 } = {}) {
  if (!force && cache.threads && Date.now() - cache.at < 10_000) return cache.threads;
  const threads = await scanSessions({ limit });
  cache = { at: Date.now(), threads };
  return threads;
}

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, `http://127.0.0.1:${PORT}`);
  const p = url.pathname;

  try {
    if (p === '/api/threads') {
      const force = url.searchParams.get('force') === '1';
      const limit = Number(url.searchParams.get('limit') ?? 3000);
      const threads = await getThreads({ force, limit });
      json(res, 200, { threads, scannedAt: new Date(cache.at).toISOString() });
      return;
    }

    if (p === '/api/graph') {
      const force = url.searchParams.get('force') === '1';
      const limit = Number(url.searchParams.get('limit') ?? 3000);
      const threads = await getThreads({ force, limit });
      const overlay = await readOverlay();
      const forest = buildForest(threads);

      json(res, 200, {
        scannedAt: new Date(cache.at).toISOString(),
        overlayUpdatedAt: overlay.version,
        threads,
        forest,
        overlay,
      });
      return;
    }

    if (p === '/api/node' && req.method === 'POST') {
      const body = await readBody(req);
      if (!body || !body.threadId) return json(res, 400, { error: 'threadId required' });
      const node = await upsertNode(body.threadId, body.patch ?? {});
      json(res, 200, { node });
      return;
    }

    if (p === '/api/edge' && req.method === 'POST') {
      const body = await readBody(req);
      if (!body || !body.from || !body.to || !body.type) {
        return json(res, 400, { error: 'from, to, type required' });
      }
      const edge = await upsertEdge(body.from, body.to, body.type, body.note);
      json(res, 200, { edge });
      return;
    }

    if (p === '/api/edge/remove' && req.method === 'POST') {
      const body = await readBody(req);
      if (!body || !body.from || !body.to || !body.type) {
        return json(res, 400, { error: 'from, to, type required' });
      }
      await deleteEdge(body.from, body.to, body.type);
      json(res, 200, { removed: true });
      return;
    }

    if (p === '/' || p === '/index.html') {
      res.writeHead(200, { 'content-type': 'text/html; charset=utf-8' });
      fs.createReadStream(path.join(PUBLIC_DIR, 'index.html')).pipe(res);
      return;
    }

    // Static assets; resolve against PUBLIC_DIR and forbid escapes.
    const rel = decodeURIComponent(p.replace(/^\//, ''));
    const abs = path.resolve(PUBLIC_DIR, rel);
    if (!abs.startsWith(PUBLIC_DIR)) {
      res.writeHead(403);
      res.end('forbidden');
      return;
    }
    fs.stat(abs, (err, st) => {
      if (err || !st.isFile()) {
        res.writeHead(404);
        res.end('not found');
        return;
      }
      res.writeHead(200, { 'content-type': MIME[path.extname(abs).toLowerCase()] ?? 'application/octet-stream' });
      fs.createReadStream(abs).pipe(res);
    });
  } catch (err) {
    json(res, 500, { error: err.message, stack: process.env.NODE_ENV === 'production' ? undefined : err.stack });
  }
});

server.listen(PORT, '127.0.0.1', () => {
  const page = `http://127.0.0.1:${PORT}/`;
  console.log(`\n  Codex Task Graph running at ${page}`);
  console.log(`  Serving read-only data from ${process.env.CODEX_HOME ?? '~/.codex'}`);
  console.log(`  Press Ctrl+C to stop.\n`);

  // Auto-open only when explicitly requested (keeps terminal logs readable).
  if (process.argv.includes('--open')) {
    import('node:child_process').then(({ exec }) => {
      exec(`start "" "${page}"`, (err) => {
        if (err) console.error('could not open browser:', err.message);
      });
    });
  }
});
