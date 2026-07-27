#!/usr/bin/env node
/**
 * Hermes Book Server — 共读读书服务（已合并进 comic_server）
 *
 * ⚠️ 此文件保留作历史参考，不再启动。comic_server.mjs 现在同时服务
 *    /v1/comic/* 和 /v1/book/*，共用一个 HTTP 进程和 Tailscale 端口。
 *    本文件的路由逻辑已迁入 tools/comic_server/comic_server.mjs。
 *
 * 与 comic_server 平行的 HTTP 服务，处理文字书籍的导入、拆章、存储和分发。
 * 手机端通过 Tailscale HTTPS 直连（同 comic_server 信任模型）。
 *
 * Run:
 *   node tools/book_server/book_server.mjs
 *
 * Env:
 *   BOOK_SERVER_HOST       default 127.0.0.1
 *   BOOK_SERVER_PORT       default 47841
 *   BOOK_SERVER_DATA_DIR   default <scriptDir>/data
 *
 * Tailscale expose:
 *   tailscale serve --https=8444 http://127.0.0.1:47841
 *
 * API:
 *   GET    /v1/book/health
 *   POST   /v1/book/import          (multipart or raw body: TXT file)
 *   GET    /v1/book/books
 *   GET    /v1/book/books/:id
 *   DELETE /v1/book/books/:id
 *   GET    /v1/book/books/:id/chapters
 *   GET    /v1/book/books/:id/chapters/:num
 *   GET    /v1/book/books/:id/notes       (AI pre-read notes)
 *   POST   /v1/book/books/:id/notes       (write AI note for a chapter)
 */
import http from 'node:http';
import {
  existsSync, mkdirSync, readFileSync, readdirSync,
  writeFileSync, unlinkSync, rmSync,
} from 'node:fs';
import { randomUUID } from 'node:crypto';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { processTxt } from './chapter_splitter.mjs';

const scriptDir = dirname(fileURLToPath(import.meta.url));
const host = process.env.BOOK_SERVER_HOST || '127.0.0.1';
const port = Number(process.env.BOOK_SERVER_PORT || 47841);
const dataDir = process.env.BOOK_SERVER_DATA_DIR || join(scriptDir, 'data');
const booksDir = join(dataDir, 'books');

for (const dir of [dataDir, booksDir]) {
  if (!existsSync(dir)) mkdirSync(dir, { recursive: true });
}

// ── Helpers ──────────────────────────────────────────────────────────────────

function nowSeconds() {
  return Math.floor(Date.now() / 1000);
}

function json(res, status, payload) {
  const body = JSON.stringify(payload);
  res.writeHead(status, {
    'content-type': 'application/json; charset=utf-8',
    'content-length': Buffer.byteLength(body),
  });
  res.end(body);
}

function readBody(req) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    req.on('data', c => chunks.push(c));
    req.on('end', () => resolve(Buffer.concat(chunks)));
    req.on('error', reject);
  });
}

function bookDir(id) {
  return join(booksDir, id);
}

function bookMetaPath(id) {
  return join(bookDir(id), 'meta.json');
}

function chaptersDir(id) {
  return join(bookDir(id), 'chapters');
}

function notesDir(id) {
  return join(bookDir(id), 'notes');
}

function loadMeta(id) {
  const p = bookMetaPath(id);
  if (!existsSync(p)) return null;
  return JSON.parse(readFileSync(p, 'utf8'));
}

function saveMeta(id, meta) {
  writeFileSync(bookMetaPath(id), JSON.stringify(meta, null, 2), 'utf8');
}

function listBooks() {
  if (!existsSync(booksDir)) return [];
  return readdirSync(booksDir, { withFileTypes: true })
    .filter(d => d.isDirectory())
    .map(d => loadMeta(d.name))
    .filter(Boolean)
    .sort((a, b) => (b.created_at || 0) - (a.created_at || 0));
}

// ── Import logic ─────────────────────────────────────────────────────────────

/**
 * Import a TXT buffer as a new book.
 * @param {Buffer} buf - raw file bytes
 * @param {string} filename - original filename (for title extraction)
 * @param {object} [opts] - { title, author }
 * @returns {object} - book metadata
 */
function importBook(buf, filename, opts = {}) {
  const id = randomUUID();
  const dir = bookDir(id);
  const chDir = chaptersDir(id);
  const nDir = notesDir(id);
  mkdirSync(chDir, { recursive: true });
  mkdirSync(nDir, { recursive: true });

  // Process
  const result = processTxt(buf, opts);

  // Derive title from filename if not provided
  const title = opts.title || filename.replace(/\.[^.]+$/, '').replace(/[_\-]/g, ' ').trim() || '未命名';
  const author = opts.author || '';

  // Write chapter files
  const chapterIndex = [];
  for (let i = 0; i < result.chapters.length; i++) {
    const ch = result.chapters[i];
    const num = String(i + 1).padStart(4, '0');
    const chPath = join(chDir, `${num}.txt`);
    writeFileSync(chPath, ch.content, 'utf8');
    chapterIndex.push({
      number: i + 1,
      title: ch.title,
      chars: ch.content.length,
      file: `${num}.txt`,
    });
  }

  // Write metadata
  const meta = {
    id,
    title,
    author,
    filename,
    encoding: result.encoding,
    total_chars: result.totalChars,
    chapter_count: result.chapters.length,
    split_method: result.method,
    split_pattern: result.patternName,
    chapters: chapterIndex,
    status: 'ready',
    created_at: nowSeconds(),
    updated_at: nowSeconds(),
  };
  saveMeta(id, meta);

  return meta;
}

// ── Multipart parser (minimal, no deps) ──────────────────────────────────────

function parseMultipart(buf, contentType) {
  const boundaryMatch = contentType.match(/boundary=(?:"([^"]+)"|([^\s;]+))/);
  if (!boundaryMatch) return null;
  const boundary = '--' + (boundaryMatch[1] || boundaryMatch[2]);
  const parts = [];
  const bufStr = buf.toString('latin1'); // preserve bytes
  const segments = bufStr.split(boundary);

  for (let i = 1; i < segments.length; i++) {
    const seg = segments[i];
    if (seg.startsWith('--')) break; // end marker
    const headerEnd = seg.indexOf('\r\n\r\n');
    if (headerEnd < 0) continue;
    const headers = seg.slice(0, headerEnd);
    const body = seg.slice(headerEnd + 4, seg.length - 2); // trim trailing \r\n
    const nameMatch = headers.match(/name="([^"]+)"/);
    const fileMatch = headers.match(/filename="([^"]+)"/);
    parts.push({
      name: nameMatch?.[1] || '',
      filename: fileMatch?.[1] || null,
      data: Buffer.from(body, 'latin1'),
    });
  }
  return parts;
}

// ── HTTP Server ──────────────────────────────────────────────────────────────

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, `http://${host}:${port}`);
  const path = url.pathname;
  const method = req.method;

  // CORS (for potential web reader UI)
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET,POST,DELETE,OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
  if (method === 'OPTIONS') { res.writeHead(204); res.end(); return; }

  try {
    // ── Health ──
    if (path === '/v1/book/health' && method === 'GET') {
      return json(res, 200, { status: 'ok', books: listBooks().length, ts: nowSeconds() });
    }

    // ── Import ──
    if (path === '/v1/book/import' && method === 'POST') {
      const body = await readBody(req);
      const ct = req.headers['content-type'] || '';

      let fileBuf, filename, title, author;

      if (ct.includes('multipart/form-data')) {
        const parts = parseMultipart(body, ct);
        if (!parts || parts.length === 0) return json(res, 400, { error: 'empty multipart' });
        const filePart = parts.find(p => p.filename) || parts[0];
        fileBuf = filePart.data;
        filename = filePart.filename || 'book.txt';
        const titlePart = parts.find(p => p.name === 'title');
        const authorPart = parts.find(p => p.name === 'author');
        title = titlePart?.data.toString('utf8') || '';
        author = authorPart?.data.toString('utf8') || '';
      } else {
        // Raw body — treat entire body as TXT content
        fileBuf = body;
        filename = url.searchParams.get('filename') || 'book.txt';
        title = url.searchParams.get('title') || '';
        author = url.searchParams.get('author') || '';
      }

      if (!fileBuf || fileBuf.length === 0) {
        return json(res, 400, { error: 'empty file' });
      }

      const meta = importBook(fileBuf, filename, { title, author });
      return json(res, 201, {
        ok: true,
        book: {
          id: meta.id,
          title: meta.title,
          author: meta.author,
          chapter_count: meta.chapter_count,
          total_chars: meta.total_chars,
          split_method: meta.split_method,
          split_pattern: meta.split_pattern,
          encoding: meta.encoding,
        },
      });
    }

    // ── List books ──
    if (path === '/v1/book/books' && method === 'GET') {
      const books = listBooks().map(b => ({
        id: b.id,
        title: b.title,
        author: b.author,
        chapter_count: b.chapter_count,
        total_chars: b.total_chars,
        status: b.status,
        created_at: b.created_at,
      }));
      return json(res, 200, { books });
    }

    // ── Book detail / delete ──
    const bookMatch = path.match(/^\/v1\/book\/books\/([a-f0-9-]+)$/);
    if (bookMatch) {
      const id = bookMatch[1];
      const meta = loadMeta(id);
      if (!meta) return json(res, 404, { error: 'book not found' });

      if (method === 'GET') {
        return json(res, 200, { book: meta });
      }
      if (method === 'DELETE') {
        rmSync(bookDir(id), { recursive: true, force: true });
        return json(res, 200, { ok: true });
      }
    }

    // ── Chapter list ──
    const chapListMatch = path.match(/^\/v1\/book\/books\/([a-f0-9-]+)\/chapters$/);
    if (chapListMatch && method === 'GET') {
      const id = chapListMatch[1];
      const meta = loadMeta(id);
      if (!meta) return json(res, 404, { error: 'book not found' });
      return json(res, 200, { chapters: meta.chapters });
    }

    // ── Single chapter content ──
    const chapMatch = path.match(/^\/v1\/book\/books\/([a-f0-9-]+)\/chapters\/(\d+)$/);
    if (chapMatch && method === 'GET') {
      const id = chapMatch[1];
      const num = parseInt(chapMatch[2], 10);
      const meta = loadMeta(id);
      if (!meta) return json(res, 404, { error: 'book not found' });

      const chInfo = meta.chapters.find(c => c.number === num);
      if (!chInfo) return json(res, 404, { error: 'chapter not found' });

      const content = readFileSync(join(chaptersDir(id), chInfo.file), 'utf8');
      return json(res, 200, {
        chapter: {
          number: chInfo.number,
          title: chInfo.title,
          chars: chInfo.chars,
          content,
        },
      });
    }

    // ── Notes (AI pre-read) ──
    const notesMatch = path.match(/^\/v1\/book\/books\/([a-f0-9-]+)\/notes$/);
    if (notesMatch) {
      const id = notesMatch[1];
      const meta = loadMeta(id);
      if (!meta) return json(res, 404, { error: 'book not found' });
      const nDir = notesDir(id);

      if (method === 'GET') {
        // Return all notes
        const files = existsSync(nDir) ? readdirSync(nDir).filter(f => f.endsWith('.json')) : [];
        const notes = files.map(f => JSON.parse(readFileSync(join(nDir, f), 'utf8')));
        notes.sort((a, b) => (a.chapter || 0) - (b.chapter || 0));
        return json(res, 200, { notes });
      }

      if (method === 'POST') {
        // Write a note for a chapter
        const body = JSON.parse((await readBody(req)).toString('utf8'));
        const chNum = body.chapter;
        const note = body.note;
        if (!chNum || !note) return json(res, 400, { error: 'need chapter + note' });
        if (!existsSync(nDir)) mkdirSync(nDir, { recursive: true });
        const notePath = join(nDir, `${String(chNum).padStart(4, '0')}.json`);
        writeFileSync(notePath, JSON.stringify({
          chapter: chNum,
          note,
          created_at: nowSeconds(),
        }, null, 2), 'utf8');
        return json(res, 201, { ok: true });
      }
    }

    // ── 404 ──
    json(res, 404, { error: 'not found' });
  } catch (err) {
    console.error('[book_server]', err);
    json(res, 500, { error: err.message });
  }
});

server.listen(port, host, () => {
  console.log(`[book_server] listening on http://${host}:${port}`);
  console.log(`[book_server] data dir: ${dataDir}`);
});
