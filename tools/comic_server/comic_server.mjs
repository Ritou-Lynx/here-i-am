#!/usr/bin/env node
/**
 * Hermes Comic + Book HTTP Server
 *
 * Serves both the comic co-reading pipeline (watch list CRUD + chapter
 * storage + image proxy) and the book co-reading pipeline (TXT import +
 * chapter splitting + notes), under separate /v1/comic/* and /v1/book/*
 * path prefixes. Both share one HTTP listener, one Tailscale serve port,
 * and one trust boundary (Tailscale network layer, same as Dev Agent
 * Bridge).
 *
 * See docs/companion-first/COMIC_CO_READING_PLAN.md §2.1 for the comic
 * design; tools/book_server/README.md (kept for the splitter module
 * docs) and docs/development/I_PROJECT_STATE.md for the book pipeline.
 *
 * Run:
 *   node tools/comic_server/comic_server.mjs
 *
 * Env:
 *   COMIC_SERVER_HOST       default 127.0.0.1
 *   COMIC_SERVER_PORT       default 47840
 *   COMIC_SERVER_DATA_DIR   default <scriptDir>/data (shared with crawler + book)
 *
 * Tailscale expose:
 *   tailscale serve --https=8443 http://127.0.0.1:47840
 */
import http from 'node:http';
import { existsSync, mkdirSync, readFileSync, readdirSync, writeFileSync, rmSync } from 'node:fs';
import { randomUUID } from 'node:crypto';
import { spawn } from 'node:child_process';
import { dirname, join, extname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { processTxt } from '../book_server/chapter_splitter.mjs';

// Lazy-loaded sharp for PNG→WebP conversion at serve time
let _sharp = null;
async function getSharp() {
  if (!_sharp) {
    const mod = await import('sharp');
    _sharp = mod.default;
  }
  return _sharp;
}

const scriptDir = dirname(fileURLToPath(import.meta.url));
const host = process.env.COMIC_SERVER_HOST || '127.0.0.1';
const port = Number(process.env.COMIC_SERVER_PORT || 47840);
const dataDir = process.env.COMIC_SERVER_DATA_DIR || join(scriptDir, 'data');

// ── Storage paths ────────────────────────────────────────────────────────────
const watchesPath = join(dataDir, 'watches.json');
const chaptersDir = join(dataDir, 'chapters');
const imagesDir = join(dataDir, 'images');
const coversDir = join(dataDir, 'covers');
const booksDir = join(dataDir, 'books');

for (const dir of [dataDir, chaptersDir, imagesDir, coversDir, booksDir]) {
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

function readJson(req) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    req.on('data', (c) => chunks.push(c));
    req.on('end', () => {
      if (chunks.length === 0) return resolve({});
      try {
        resolve(JSON.parse(Buffer.concat(chunks).toString('utf8')));
      } catch (e) {
        reject(e);
      }
    });
    req.on('error', reject);
  });
}

function loadWatches() {
  if (!existsSync(watchesPath)) return [];
  try {
    const raw = JSON.parse(readFileSync(watchesPath, 'utf8'));
    return Array.isArray(raw.watches) ? raw.watches : [];
  } catch {
    return [];
  }
}

function saveWatches(watches) {
  writeFileSync(watchesPath, JSON.stringify({ watches }, null, 2));
}

function loadChapter(chapterId) {
  const p = join(chaptersDir, `${chapterId}.json`);
  if (!existsSync(p)) return null;
  return JSON.parse(readFileSync(p, 'utf8'));
}

function saveChapter(chapter) {
  writeFileSync(join(chaptersDir, `${chapter.id}.json`), JSON.stringify(chapter, null, 2));
}

function loadAllChapters() {
  const files = readdirSync(chaptersDir).filter((f) => f.endsWith('.json'));
  return files.map((f) => JSON.parse(readFileSync(join(chaptersDir, f), 'utf8')));
}

// ── Book helpers (merged from tools/book_server/book_server.mjs) ──────────────
function bookDir(id) { return join(booksDir, id); }
function bookMetaPath(id) { return join(bookDir(id), 'meta.json'); }
function chaptersDirForBook(id) { return join(bookDir(id), 'chapters'); }
function notesDirForBook(id) { return join(bookDir(id), 'notes'); }

function loadBookMeta(id) {
  const p = bookMetaPath(id);
  if (!existsSync(p)) return null;
  return JSON.parse(readFileSync(p, 'utf8'));
}
function saveBookMeta(id, meta) {
  writeFileSync(bookMetaPath(id), JSON.stringify(meta, null, 2), 'utf8');
}
function listBooks() {
  if (!existsSync(booksDir)) return [];
  return readdirSync(booksDir, { withFileTypes: true })
    .filter((d) => d.isDirectory())
    .map((d) => loadBookMeta(d.name))
    .filter(Boolean)
    .sort((a, b) => (b.created_at || 0) - (a.created_at || 0));
}

function readBody(req) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    req.on('data', (c) => chunks.push(c));
    req.on('end', () => resolve(Buffer.concat(chunks)));
    req.on('error', reject);
  });
}

function parseMultipart(buf, contentType) {
  const boundaryMatch = contentType.match(/boundary=(?:"([^"]+)"|([^\s;]+))/);
  if (!boundaryMatch) return null;
  const boundary = '--' + (boundaryMatch[1] || boundaryMatch[2]);
  const parts = [];
  const bufStr = buf.toString('latin1');
  const segments = bufStr.split(boundary);
  for (let i = 1; i < segments.length; i++) {
    const seg = segments[i];
    if (seg.startsWith('--')) break;
    const headerEnd = seg.indexOf('\r\n\r\n');
    if (headerEnd < 0) continue;
    const headers = seg.slice(0, headerEnd);
    const body = seg.slice(headerEnd + 4, seg.length - 2);
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

function importBook(buf, filename, opts = {}) {
  const id = randomUUID();
  const chDir = chaptersDirForBook(id);
  const nDir = notesDirForBook(id);
  mkdirSync(chDir, { recursive: true });
  mkdirSync(nDir, { recursive: true });

  const result = processTxt(buf, opts);
  const title = opts.title || filename.replace(/\.[^.]+$/, '').replace(/[_\-]/g, ' ').trim() || '未命名';
  const author = opts.author || '';

  const chapterIndex = [];
  for (let i = 0; i < result.chapters.length; i++) {
    const ch = result.chapters[i];
    const num = String(i + 1).padStart(4, '0');
    writeFileSync(join(chDir, `${num}.txt`), ch.content, 'utf8');
    chapterIndex.push({
      number: i + 1,
      title: ch.title,
      chars: ch.content.length,
      file: `${num}.txt`,
    });
  }

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
  saveBookMeta(id, meta);
  return meta;
}

function spawnSummaryGeneration(bookId) {
  const script = join(scriptDir, 'generate_book_summary.mjs');
  if (!existsSync(script)) return;
  const model = process.env.BOOK_SUMMARY_MODEL || 'qwen3:8b';
  const child = spawn(process.execPath, [script, bookId, '--model', model], {
    cwd: scriptDir,
    stdio: 'ignore',
    detached: true,
    env: { ...process.env, COMIC_SERVER_DATA_DIR: dataDir },
  });
  child.unref();
  console.log(`[book] Summary generation spawned for ${bookId} (pid=${child.pid}, model=${model})`);
}

const MIME = {
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.png': 'image/png',
  '.webp': 'image/webp',
  '.gif': 'image/gif',
};

// ── Router ───────────────────────────────────────────────────────────────────
async function handle(req, res) {
  const url = new URL(req.url, `http://${req.headers.host || 'localhost'}`);
  const path = url.pathname;
  const q = url.searchParams;

  try {
    // Health
    if (req.method === 'GET' && path === '/v1/comic/health') {
      return json(res, 200, {
        ok: true,
        service: 'comic-server',
        version: '0.1.0',
        watches: loadWatches().length,
      });
    }

    // ── Watches ─────────────────────────────────────────────────────────────
    if (req.method === 'GET' && path === '/v1/comic/watches') {
      const status = q.get('status');
      let watches = loadWatches();
      if (status) watches = watches.filter((w) => w.status === status);
      return json(res, 200, { watches });
    }

    if (req.method === 'POST' && path === '/v1/comic/watches') {
      const body = await readJson(req);
      const watches = loadWatches();
      const existingIdx = watches.findIndex((w) => w.id === body.id);
      const watch = {
        id: body.id || randomUUID(),
        character_id: body.character_id || '',
        source_site: body.source_site || '',
        comic_url: body.comic_url || '',
        comic_title: body.comic_title || '',
        cover_url: body.cover_url || null,
        last_chapter_url: body.last_chapter_url || null,
        status: body.status || 'active',
        created_at: existingIdx >= 0 ? watches[existingIdx].created_at : nowSeconds(),
        updated_at: nowSeconds(),
      };
      if (existingIdx >= 0) watches[existingIdx] = watch;
      else watches.push(watch);
      saveWatches(watches);
      return json(res, existingIdx >= 0 ? 200 : 201, watch);
    }

    // /v1/comic/watches/:id
    const watchMatch = path.match(/^\/v1\/comic\/watches\/(.+)$/);
    if (watchMatch) {
      const id = watchMatch[1];
      const watches = loadWatches();
      const idx = watches.findIndex((w) => w.id === id);
      if (idx < 0) return json(res, 404, { error: 'watch_not_found' });

      if (req.method === 'PATCH') {
        const body = await readJson(req);
        Object.assign(watches[idx], body, { updated_at: nowSeconds() });
        saveWatches(watches);
        return json(res, 200, watches[idx]);
      }
      if (req.method === 'DELETE') {
        watches[idx].status = 'removed';
        watches[idx].updated_at = nowSeconds();
        saveWatches(watches);
        return json(res, 200, { ok: true });
      }
    }

    // ── Chapters ────────────────────────────────────────────────────────────
    if (req.method === 'GET' && path === '/v1/comic/chapters') {
      const mangaId = q.get('manga_id');
      const status = q.get('status');
      const since = q.get('since'); // seconds-since-epoch
      let chapters = loadAllChapters();
      if (mangaId) chapters = chapters.filter((c) => c.watch_id === mangaId);
      if (status) chapters = chapters.filter((c) => c.status === status);
      if (since) {
        const sinceNum = Number(since);
        // Return chapters that were created OR updated after the cursor.
        // This ensures reextracted screenplays (updated_at changed, created_at
        // unchanged) are picked up by the phone on next sync.
        chapters = chapters.filter((c) => (c.created_at || 0) > sinceNum || (c.updated_at || 0) > sinceNum);
      }
      chapters.sort((a, b) => (a.created_at || 0) - (b.created_at || 0));
      return json(res, 200, { chapters });
    }

    if (req.method === 'POST' && path === '/v1/comic/chapters') {
      const body = await readJson(req);
      const chapter = {
        id: body.id || randomUUID(),
        watch_id: body.watch_id || '',
        comic_title: body.comic_title || '',
        chapter_number: body.chapter_number || 0,
        chapter_title: body.chapter_title || null,
        chapter_url: body.chapter_url || '',
        page_count: 0,
        pages: [],
        screenplay: [],
        status: body.status || 'queued',
        error: null,
        fetched_at: null,
        ocr_completed_at: null,
        created_at: nowSeconds(),
        updated_at: nowSeconds(),
      };
      saveChapter(chapter);
      return json(res, 201, chapter);
    }

    // /v1/comic/chapters/:id
    const chapterMatch = path.match(/^\/v1\/comic\/chapters\/(.+)$/);
    if (chapterMatch && req.method === 'GET') {
      const id = chapterMatch[1];
      const chapter = loadChapter(id);
      if (!chapter) return json(res, 404, { error: 'chapter_not_found' });
      return json(res, 200, chapter);
    }
    if (chapterMatch && (req.method === 'PATCH' || req.method === 'PUT')) {
      const id = chapterMatch[1];
      const existing = loadChapter(id);
      if (!existing) return json(res, 404, { error: 'chapter_not_found' });
      const body = await readJson(req);
      // Stringify pages/screenplay for the phone client convenience
      const updated = {
        ...existing,
        ...body,
        updated_at: nowSeconds(),
      };
      if (body.pages && !body.pages_json) {
        updated.pages_json = JSON.stringify(body.pages);
      }
      if (body.screenplay && !body.screenplay_json) {
        updated.screenplay_json = JSON.stringify(body.screenplay);
      }
      saveChapter(updated);
      return json(res, 200, updated);
    }

    // Debug: test sharp
    if (req.method === 'GET' && path === '/v1/comic/debug-sharp') {
      try {
        const sharp = await getSharp();
        const testBuf = await sharp(join(imagesDir, '31212279', '001.png')).webp({quality:85}).toBuffer();
        return json(res, 200, { ok: true, webpSize: testBuf.length, pngSize: readFileSync(join(imagesDir, '31212279', '001.png')).length });
      } catch(e) {
        return json(res, 200, { ok: false, error: e.message });
      }
    }

    // ── Image proxy ────────────────────────────────────────────────────────
    const imageMatch = path.match(/^\/v1\/comic\/images\/([^/]+)\/(\d+)$/);
    if (imageMatch && req.method === 'GET') {
      const chapterId = imageMatch[1];
      const pageNum = imageMatch[2];
      const padded = pageNum.padStart(3, '0');
      let srcPath = null, srcExt = null;
      for (const ext of ['.png', '.jpg', '.jpeg', '.webp']) {
        const p1 = join(imagesDir, chapterId, `${padded}${ext}`);
        const p2 = join(imagesDir, chapterId, `${pageNum}${ext}`);
        if (existsSync(p1)) { srcPath = p1; srcExt = ext; break; }
        if (existsSync(p2)) { srcPath = p2; srcExt = ext; break; }
      }
      if (!srcPath) return json(res, 404, { error: 'image_not_found', chapter_id: chapterId, page: pageNum });
      if (srcExt === '.webp') {
        const data = readFileSync(srcPath);
        res.writeHead(200, { 'content-type': 'image/webp', 'content-length': data.length, 'cache-control': 'public, max-age=86400' });
        return res.end(data);
      }
      const webpPath = join(imagesDir, chapterId, `${padded}.webp`);
      if (existsSync(webpPath)) {
        const data = readFileSync(webpPath);
        res.writeHead(200, { 'content-type': 'image/webp', 'content-length': data.length, 'cache-control': 'public, max-age=86400' });
        return res.end(data);
      }
      try {
        const sharp = await getSharp();
        const webpBuf = await sharp(srcPath).webp({ quality: 85 }).toBuffer();
        try { writeFileSync(webpPath, webpBuf); } catch {}
        res.writeHead(200, { 'content-type': 'image/webp', 'content-length': webpBuf.length, 'cache-control': 'public, max-age=86400' });
        return res.end(webpBuf);
      } catch (e) {
        const data = readFileSync(srcPath);
        res.writeHead(200, { 'content-type': MIME[srcExt] || 'image/png', 'content-length': data.length, 'cache-control': 'public, max-age=86400' });
        return res.end(data);
      }
    }

    // ── Book routes (merged from tools/book_server/book_server.mjs) ─────────
    // Health
    if (req.method === 'GET' && path === '/v1/book/health') {
      return json(res, 200, { status: 'ok', books: listBooks().length, ts: nowSeconds() });
    }

    // Import
    if (path === '/v1/book/import' && req.method === 'POST') {
      const body = await readBody(req);
      const ct = req.headers['content-type'] || '';
      let fileBuf, filename, title, author;
      if (ct.includes('multipart/form-data')) {
        const parts = parseMultipart(body, ct);
        if (!parts || parts.length === 0) return json(res, 400, { error: 'empty multipart' });
        const filePart = parts.find((p) => p.filename) || parts[0];
        fileBuf = filePart.data;
        filename = filePart.filename || 'book.txt';
        title = parts.find((p) => p.name === 'title')?.data.toString('utf8') || '';
        author = parts.find((p) => p.name === 'author')?.data.toString('utf8') || '';
      } else {
        fileBuf = body;
        filename = q.get('filename') || 'book.txt';
        title = q.get('title') || '';
        author = q.get('author') || '';
      }
      if (!fileBuf || fileBuf.length === 0) return json(res, 400, { error: 'empty file' });
      const meta = importBook(fileBuf, filename, { title, author });
      spawnSummaryGeneration(meta.id);
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

    // List books
    if (path === '/v1/book/books' && req.method === 'GET') {
      const books = listBooks().map((b) => ({
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

    // Book detail / delete
    const bookMatch = path.match(/^\/v1\/book\/books\/([a-f0-9-]+)$/);
    if (bookMatch) {
      const id = bookMatch[1];
      const meta = loadBookMeta(id);
      if (!meta) return json(res, 404, { error: 'book not found' });
      if (req.method === 'GET') return json(res, 200, { book: meta });
      if (req.method === 'DELETE') {
        rmSync(bookDir(id), { recursive: true, force: true });
        return json(res, 200, { ok: true });
      }
    }

    // Chapter list
    const chapListMatch = path.match(/^\/v1\/book\/books\/([a-f0-9-]+)\/chapters$/);
    if (chapListMatch && req.method === 'GET') {
      const id = chapListMatch[1];
      const meta = loadBookMeta(id);
      if (!meta) return json(res, 404, { error: 'book not found' });
      return json(res, 200, { chapters: meta.chapters });
    }

    // Single chapter content
    const chapMatch = path.match(/^\/v1\/book\/books\/([a-f0-9-]+)\/chapters\/(\d+)$/);
    if (chapMatch && req.method === 'GET') {
      const id = chapMatch[1];
      const num = parseInt(chapMatch[2], 10);
      const meta = loadBookMeta(id);
      if (!meta) return json(res, 404, { error: 'book not found' });
      const chInfo = meta.chapters.find((c) => c.number === num);
      if (!chInfo) return json(res, 404, { error: 'chapter not found' });
      const content = readFileSync(join(chaptersDirForBook(id), chInfo.file), 'utf8');
      return json(res, 200, {
        chapter: { number: chInfo.number, title: chInfo.title, chars: chInfo.chars, content },
      });
    }

    // AI summaries (generated by generate_book_summary.mjs)
    const summariesMatch = path.match(/^\/v1\/book\/books\/([a-f0-9-]+)\/summaries$/);
    if (summariesMatch && req.method === 'GET') {
      const id = summariesMatch[1];
      const sp = join(bookDir(id), 'summaries.json');
      if (!existsSync(sp)) return json(res, 404, { error: 'summaries not found. Run generate_book_summary.mjs first.' });
      const summaries = JSON.parse(readFileSync(sp, 'utf8'));
      return json(res, 200, summaries);
    }

    // Characters only (extracted from summaries.json)
    const charsMatch = path.match(/^\/v1\/book\/books\/([a-f0-9-]+)\/characters$/);
    if (charsMatch && req.method === 'GET') {
      const id = charsMatch[1];
      const sp = join(bookDir(id), 'summaries.json');
      if (!existsSync(sp)) return json(res, 404, { error: 'summaries not found' });
      const summaries = JSON.parse(readFileSync(sp, 'utf8'));
      return json(res, 200, { characters: summaries.characters || [] });
    }

    // Notes
    const notesMatch = path.match(/^\/v1\/book\/books\/([a-f0-9-]+)\/notes$/);
    if (notesMatch) {
      const id = notesMatch[1];
      const meta = loadBookMeta(id);
      if (!meta) return json(res, 404, { error: 'book not found' });
      const nDir = notesDirForBook(id);
      if (req.method === 'GET') {
        const files = existsSync(nDir) ? readdirSync(nDir).filter((f) => f.endsWith('.json')) : [];
        const notes = files.map((f) => JSON.parse(readFileSync(join(nDir, f), 'utf8')));
        notes.sort((a, b) => (a.chapter || 0) - (b.chapter || 0));
        return json(res, 200, { notes });
      }
      if (req.method === 'POST') {
        const body = JSON.parse((await readBody(req)).toString('utf8'));
        const chNum = body.chapter;
        const note = body.note;
        if (!chNum || !note) return json(res, 400, { error: 'need chapter + note' });
        if (!existsSync(nDir)) mkdirSync(nDir, { recursive: true });
        writeFileSync(
          join(nDir, `${String(chNum).padStart(4, '0')}.json`),
          JSON.stringify({ chapter: chNum, note, created_at: nowSeconds() }, null, 2),
          'utf8',
        );
        return json(res, 201, { ok: true });
      }
    }

    return json(res, 404, { error: 'not_found', path });
  } catch (err) {
    console.error('Handler error:', err);
    return json(res, 500, { error: 'internal', message: err.message });
  }
}

const server = http.createServer(handle);
server.listen(port, host, () => {
  console.log(`Comic + Book server listening on http://${host}:${port}`);
  console.log(`Data dir: ${dataDir}`);
  console.log(`  comic: /v1/comic/*  (watches, chapters, images)`);
  console.log(`  book:  /v1/book/*   (import, books, chapters, notes)`);
  console.log(`Tailscale: tailscale serve --https=8443 http://127.0.0.1:${port}`);
});