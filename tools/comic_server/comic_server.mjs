#!/usr/bin/env node
/**
 * Hermes Comic HTTP Server
 *
 * Serves the comic co-reading pipeline: watch list CRUD + chapter storage
 * + image proxy. The phone app connects over Tailscale HTTPS (same trust
 * boundary as the Dev Agent Bridge).
 *
 * See docs/companion-first/COMIC_CO_READING_PLAN.md §2.1 for the design.
 *
 * Run:
 *   node tools/comic_server/comic_server.mjs
 *
 * Env:
 *   COMIC_SERVER_HOST       default 127.0.0.1
 *   COMIC_SERVER_PORT       default 47840
 *   COMIC_SERVER_DATA_DIR   default <scriptDir>/data (shared with crawler)
 *
 * Tailscale expose:
 *   tailscale serve --https=8443 http://127.0.0.1:47840
 */
import http from 'node:http';
import { existsSync, mkdirSync, readFileSync, readdirSync, writeFileSync, statSync } from 'node:fs';
import { randomUUID } from 'node:crypto';
import { homedir } from 'node:os';
import { dirname, join, extname } from 'node:path';
import { fileURLToPath } from 'node:url';

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

for (const dir of [dataDir, chaptersDir, imagesDir, coversDir]) {
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

    return json(res, 404, { error: 'not_found', path });
  } catch (err) {
    console.error('Handler error:', err);
    return json(res, 500, { error: 'internal', message: err.message });
  }
}

const server = http.createServer(handle);
server.listen(port, host, () => {
  console.log(`Comic server listening on http://${host}:${port}`);
  console.log(`Data dir: ${dataDir}`);
  console.log(`Tailscale: tailscale serve --https=8443 http://127.0.0.1:${port}`);
});