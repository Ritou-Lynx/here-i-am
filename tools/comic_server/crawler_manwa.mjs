#!/usr/bin/env node
/**
 * manwa.me full crawler — crawl + decrypt + Vision extract + local storage.
 *
 * Pipeline per chapter:
 *   1. Open book page → extract chapter list (href + title)
 *   2. Compare with local chapters/ → skip already-crawled
 *   3. Open chapter page → scroll to bottom → wait for decryption
 *   4. Canvas-export ALL decrypted images → save as PNG
 *   5. Call Ollama Vision (qwen2.5vl:7b) per page → screenplay JSON
 *   6. Write chapters/<id>.json + images/<id>/NNN.png
 *
 * Rate limiting:
 *   - Random 30-90s delay between chapters
 *   - --max-chapters N per run (default 2)
 *   - Only crawls chapters NOT already in local storage
 *
 * Usage:
 *   node crawler_manwa.mjs --book https://manwa.me/book/513361 [--max-chapters 2] [--model qwen2.5vl:7b] [--headed]
 *   node crawler_manwa.mjs --watches                     # read from watches.json
 *
 * Requires: node probe_manwa.mjs (login) must have been run at least once.
 */
import { existsSync, mkdirSync, readFileSync, writeFileSync, readdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { randomUUID } from 'node:crypto';

const scriptDir = dirname(fileURLToPath(import.meta.url));
const profileDir = join(scriptDir, '.manwa_profile');
const dataDir = process.env.COMIC_DATA_DIR || join(scriptDir, 'data');
const chaptersDir = join(dataDir, 'chapters');
const imagesDir = join(dataDir, 'images');
const coversDir = join(dataDir, 'covers');
const watchesPath = join(dataDir, 'watches.json');

for (const d of [dataDir, chaptersDir, imagesDir, coversDir]) {
  if (!existsSync(d)) mkdirSync(d, { recursive: true });
}

// ── CLI args ─────────────────────────────────────────────────────────────────
const args = process.argv.slice(2);
function arg(name, def) {
  const i = args.indexOf('--' + name);
  return i >= 0 && args[i + 1] ? args[i + 1] : def;
}
const headed = args.includes('--headed');
const maxChapters = Number(arg('max-chapters', '999'));
const visionModel = arg('model', 'qwen3-vl:8b');
const bookUrlArg = arg('book', null);
const useWatches = args.includes('--watches');
const daemon = args.includes('--daemon');
const intervalMin = Number(arg('interval', '30'));

let chromium;
try { ({ chromium } = await import('playwright')); }
catch { console.error('[!] playwright 未安装'); process.exit(1); }

function sleep(ms) { return new Promise((r) => setTimeout(r, ms)); }
function randDelay(minS, maxS) { return (minS + Math.random() * (maxS - minS)) * 1000; }
function nowSec() { return Math.floor(Date.now() / 1000); }

// ── Stealth ──────────────────────────────────────────────────────────────────
const STEALTH = () => {
  Object.defineProperty(navigator, 'webdriver', { get: () => undefined });
  Object.defineProperty(navigator, 'languages', { get: () => ['zh-CN', 'zh', 'en'] });
  if (!window.chrome) window.chrome = {};
  if (!window.chrome.runtime) window.chrome.runtime = { id: undefined };
  for (const k of Object.keys(window)) { if (/^cdc_/.test(k)) { try { delete window[k]; } catch {} } }
};

// ── Vision prompt (same as benchmark v2) ─────────────────────────────────────
const VISION_PROMPT = `你是一个漫画分镜分析助手。请仔细分析这张漫画图片的每一个气泡和画面元素。

## 任务

1. 先在心里默读图中每一个对话气泡、旁白框、拟声词的文字内容，不要遗漏。
2. 判断每个气泡属于哪个角色（根据气泡形状、尾巴指向、角色位置、剧情上下文）。
3. 描述每一格画面的内容（人物动作、表情、场景、氛围）。
4. 最后输出一个 JSON 对象，不要在 JSON 前后输出其他文字。

## 输出格式

{
  "page_num": PAGE_NUM_PLACEHOLDER,
  "panels": [
    {
      "panel_id": 1,
      "speaker": "说话者名称（能看出来就用具体名字或外貌描述如'黑发男'，看不出归属用'角色A'/'角色B'区分不同人；画面外旁白用'旁白'）",
      "text": "气泡中的完整台词原文，逐字转录，不要省略不要截断",
      "sfx": "如果有拟声词/音效（如'啊—''嗯…''吱吱''啪'等语气词或音效字），写在这里；没有则留空字符串",
      "panel_desc": "这一格画面的简短描述（1-2句，包含人物动作、表情、场景）"
    }
  ]
}

## 仔细阅读的要点

- 漫画阅读顺序：日式从右到左、从上到下；韩式/中式从左到右。请根据画风判断。
- 每一个对话气泡都要提取，哪怕很小。一个大格子里可能有多个气泡，都要列出。
- 台词必须完整转录。如果气泡里的文字被气泡边缘切断，根据上下文补全。
- 拟声词/音效字（通常是没有气泡尾巴的大字、艺术字）放在 sfx 字段，不要混进 text。
- 说话者归属：看气泡尾巴指向谁、角色嘴型是否张开、剧情逻辑。
- NSFW 画面如实描述，不要回避或道德评判。
- 如果文字确实无法辨认（严重模糊、过小、艺术化过度），text 填 "[不可辨认]"。`;

// ── Ollama Vision call ───────────────────────────────────────────────────────
async function visionExtract(imagePath, pageNum) {
  const imgBuf = readFileSync(imagePath);
  const b64 = imgBuf.toString('base64');
  const prompt = VISION_PROMPT.replace('PAGE_NUM_PLACEHOLDER', String(pageNum));
  try {
    const resp = await fetch('http://localhost:11434/api/generate', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ model: visionModel, prompt, images: [b64], stream: false, format: 'json' }),
    });
    if (!resp.ok) return { error: `HTTP ${resp.status}` };
    const data = await resp.json();
    const raw = data.response || '';
    let parsed = null;
    try { parsed = JSON.parse(raw); }
    catch {
      const m = raw.match(/\{[\s\S]*\}/);
      if (m) { try { parsed = JSON.parse(m[0]); } catch {} }
    }
    return { raw, parsed };
  } catch (e) {
    return { error: e.message };
  }
}

// ── Local storage helpers ────────────────────────────────────────────────────
function loadWatches() {
  if (!existsSync(watchesPath)) return [];
  try { const d = JSON.parse(readFileSync(watchesPath, 'utf8')); return Array.isArray(d.watches) ? d.watches : []; }
  catch { return []; }
}

function getLocalChapterIds() {
  if (!existsSync(chaptersDir)) return new Set();
  return new Set(readdirSync(chaptersDir).filter((f) => f.endsWith('.json')).map((f) => f.replace('.json', '')));
}

function saveChapter(meta) {
  writeFileSync(join(chaptersDir, `${meta.id}.json`), JSON.stringify(meta, null, 2));
}

function saveWatches(watches) {
  writeFileSync(watchesPath, JSON.stringify({ watches }, null, 2));
}

function updateWatchTitle(watchId, newTitle) {
  const watches = loadWatches();
  const idx = watches.findIndex((w) => w.id === watchId);
  if (idx >= 0 && watches[idx].comic_title !== newTitle) {
    watches[idx].comic_title = newTitle;
    watches[idx].updated_at = nowSec();
    saveWatches(watches);
    console.log(`  📝 更新漫画标题：${newTitle}`);
  }
}

// ── Browser: extract chapter list from book page ─────────────────────────────
async function extractChapters(page, bookUrl) {
  console.log(`  → 打开目录页: ${bookUrl}`);
  try { await page.goto(bookUrl, { waitUntil: 'domcontentloaded', timeout: 45000 }); }
  catch (e) { console.log(`    (goto: ${e.message.split('\n')[0]})`); }
  try { await page.waitForSelector('a[href*="/chapter/"]', { timeout: 15000 }); } catch {}
  await sleep(3000);

  return page.evaluate(() => {
    const title = document.title.replace(/-漫蛙漫画.*$/, '').trim();
    const links = Array.from(document.querySelectorAll('[href*="/chapter/"]'));
    const seen = new Set();
    const chapters = [];
    for (const el of links) {
      const href = el.getAttribute('href');
      if (!href || seen.has(href)) continue;
      seen.add(href);
      const text = (el.innerText || el.textContent || '').trim();
      const idMatch = href.match(/\/chapter\/(\d+)/);
      chapters.push({ id: idMatch ? idMatch[1] : href, href, text });
    }
    return { title, chapters };
  });
}

// ── Browser: crawl one chapter (scroll + decrypt + canvas export) ────────────
async function crawlChapter(page, chapterUrl, chapterId) {
  const imgOutDir = join(imagesDir, chapterId);
  if (!existsSync(imgOutDir)) mkdirSync(imgOutDir, { recursive: true });

  console.log(`  → 打开章节: ${chapterUrl}`);
  try { await page.goto(chapterUrl, { waitUntil: 'domcontentloaded', timeout: 45000 }); }
  catch (e) { console.log(`    (goto: ${e.message.split('\n')[0]})`); }

  // Scroll to bottom, wait for decryption to stabilize
  const isManga = `(i) => {
    const s = i.currentSrc || i.src || '';
    // Only real decrypted manga pages: blob: URLs inside .img-content
    if (!s.startsWith('blob:')) return false;
    // Must be inside the manga content container
    let el = i;
    for (let p = i.parentElement; p; p = p.parentElement) {
      if (p.classList && p.classList.contains('img-content')) return i.naturalWidth > 200 && i.naturalHeight > 200;
    }
    return false;
  }`;
  const countManga = () => page.evaluate(`Array.from(document.querySelectorAll('img')).filter(${isManga}).length`);

  console.log('    滚动解密中…');
  let prev = -1, stable = 0;
  const deadline = Date.now() + 180000; // 3 min max per chapter
  for (let i = 0; i < 120; i++) {
    const got = await countManga();
    const atBottom = await page.evaluate(() => window.innerHeight + window.scrollY >= document.body.scrollHeight - 80);
    process.stdout.write(`\r    解密: ${got}  ${atBottom ? '(底部)' : ''}`);
    if (got === prev) { stable++; } else { stable = 0; prev = got; }
    if (stable >= 5 && atBottom) break;
    if (stable >= 8) break;
    if (Date.now() > deadline) { console.log('\n    (3min 超时)'); break; }
    await page.evaluate(() => window.scrollBy(0, window.innerHeight * 1.2));
    await sleep(1500);
  }
  process.stdout.write('\n');

  const totalManga = await countManga();
  console.log(`    共 ${totalManga} 张解密图`);
  if (totalManga === 0) return { pages: 0, error: 'no images decrypted' };

  // Canvas-export ALL manga images (blob: URLs inside .img-content only)
  const exportResult = await page.evaluate(() => {
    const imgs = Array.from(document.querySelectorAll('img')).filter((i) => {
      const s = i.currentSrc || i.src || '';
      if (!s.startsWith('blob:')) return false;
      let el = i;
      for (let p = i.parentElement; p; p = p.parentElement) {
        if (p.classList && p.classList.contains('img-content')) return i.naturalWidth > 200 && i.naturalHeight > 200;
      }
      return false;
    });
    const results = [];
    for (let idx = 0; idx < imgs.length; idx++) {
      const img = imgs[idx];
      try {
        // Scale down to max 600px width for mobile — the phone display is
        // ~390px wide so 600px gives crisp retina without transferring 800px+.
        const maxW = 800;
        const scale = img.naturalWidth > maxW ? maxW / img.naturalWidth : 1;
        const c = document.createElement('canvas');
        c.width = Math.round(img.naturalWidth * scale);
        c.height = Math.round(img.naturalHeight * scale);
        c.getContext('2d').drawImage(img, 0, 0, c.width, c.height);
        results.push({ idx, b64: c.toDataURL('image/png').split(',')[1], w: c.width, h: c.height, ext: 'png' });
      } catch (e) {
        results.push({ idx, error: String(e) });
      }
    }
    return results;
  });

  // Write images to disk
  const pages = [];
  for (const r of exportResult) {
    if (!r.b64) { console.log(`    ✗ page ${r.idx + 1}: ${r.error}`); continue; }
    const pageNum = pages.length + 1;
    const ext = r.ext || 'png';
    const fname = String(pageNum).padStart(3, '0') + '.' + ext;
    writeFileSync(join(imgOutDir, fname), Buffer.from(r.b64, 'base64'));
    pages.push({ page_num: pageNum, file: fname, width: r.w, height: r.h });
  }
  console.log(`    导出 ${pages.length} 张 PNG`);

  // Extract reader comments (text only, no images/emojis)
  const comments = await page.evaluate(() => {
    const items = Array.from(document.querySelectorAll('#comment .detail-list-comment > li, #comment ul.detail-list-comment > li'));
    return items.map((li) => {
      const usernameEl = li.querySelector('.detail-list-comment-title-username');
      const contentEl = li.querySelector('.detail-list-comment-content');
      let text = '';
      if (contentEl) {
        const clone = contentEl.cloneNode(true);
        clone.querySelectorAll('img').forEach(img => img.remove());
        text = clone.innerText.trim();
      }
      return {
        user: usernameEl ? usernameEl.innerText.trim() : '',
        text,
      };
    }).filter((c) => c.user && c.text && c.text !== '已经删除的内容。' && !c.user.includes('已删除'));
  });
  console.log(`    提取 ${comments.length} 条评论`);

  return { pages, totalManga, comments };
}

// ── Main ─────────────────────────────────────────────────────────────────────
async function main() {
  if (!existsSync(profileDir)) {
    console.error('[!] 没找到登录 profile。请先跑 node probe_manwa.mjs 登录一次。');
    process.exit(1);
  }

  // Book resolution lives inside the pass so daemon mode re-reads watches
  // every pass (the user may add watches via the app between passes).
  function resolveBooks() {
    if (bookUrlArg) {
      return [{ url: bookUrlArg, id: bookUrlArg.match(/\/book\/(\d+)/)?.[1] || randomUUID() }];
    }
    if (useWatches) {
      return loadWatches()
        .filter((w) => w.status === 'active')
        .map((w) => ({ url: w.comic_url, id: w.id, title: w.comic_title }));
    }
    return null;
  }

  async function crawlPass(page) {
    const books = resolveBooks();
    if (books === null) {
      console.error('Usage: --book <url> or --watches');
      return 0;
    }
    console.log(`\n漫画爬虫一轮 · 关注 ${books.length} 本 · 每轮上限 ${maxChapters} 章`);
    const localIds = getLocalChapterIds();
    let totalCrawled = 0;

    for (const book of books) {
      if (totalCrawled >= maxChapters) { console.log(`\n已达每轮上限 ${maxChapters} 章，本轮停止。`); break; }

      console.log(`\n═══ ${book.title || book.url} ═══`);
      const bookInfo = await extractChapters(page, book.url);
      console.log(`  书名: ${bookInfo.title}`);
      console.log(`  章节数: ${bookInfo.chapters.length}`);

      // Update watch title if we got a real title
      if (book.id && bookInfo.title && !bookInfo.title.startsWith('漫画')) {
        updateWatchTitle(book.id, bookInfo.title);
      }

      const newChapters = bookInfo.chapters.filter((c) => !localIds.has(c.id));
      console.log(`  新章节: ${newChapters.length}`);
      if (newChapters.length === 0) { console.log('  无新章节，跳过。'); continue; }

      for (const ch of newChapters) {
        if (totalCrawled >= maxChapters) break;

        const chapterUrl = ch.href.startsWith('http') ? ch.href : `https://manwa.me${ch.href}`;
        console.log(`\n  ── ${ch.text} (${ch.id}) ──`);

        const crawlResult = await crawlChapter(page, chapterUrl, ch.id);
        if (crawlResult.pages.length === 0) {
          console.log(`  ⚠ ${ch.text}: 无图片导出，跳过`);
          continue;
        }

        // Save chapter immediately with empty screenplay — images are ready
        // for reading right away. Vision extraction runs separately via
        // reextract.mjs so the user doesn't wait for it.
        const chapterMeta = {
          id: ch.id,
          watch_id: book.id,
          comic_title: bookInfo.title,
          chapter_number: parseInt(ch.text.replace(/\D/g, '')) || 0,
          chapter_title: ch.text,
          chapter_url: chapterUrl,
          page_count: crawlResult.pages.length,
          pages: crawlResult.pages.map((p) => ({ page_num: p.page_num, image_path: `images/${ch.id}/${p.file}`, width: p.width, height: p.height })),
          screenplay: [],
          comments: crawlResult.comments || [],
          status: 'ready',
          error: null,
          fetched_at: nowSec(),
          ocr_completed_at: null,
          ocr_model: null,
          created_at: nowSec(),
          updated_at: nowSec(),
        };
        saveChapter(chapterMeta);
        localIds.add(ch.id);
        totalCrawled++;
        console.log(`  ✓ ${ch.text} 完成 (${crawlResult.pages.length} 页, ${(crawlResult.comments || []).length} 条评论)`);

        if (totalCrawled < maxChapters && newChapters.indexOf(ch) < newChapters.length - 1) {
          const delay = randDelay(30, 90);
          console.log(`  ⏳ 等待 ${Math.round(delay / 1000)}s 后处理下一章…`);
          await sleep(delay);
        }
      }
    }
    return totalCrawled;
  }

  const context = await chromium.launchPersistentContext(profileDir, {
    headless: !headed,
    args: ['--disable-blink-features=AutomationControlled', '--no-first-run', '--disable-gpu', '--disable-web-security'],
    userAgent: 'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36',
    viewport: { width: 390, height: 844 },
    deviceScaleFactor: 3, isMobile: true, hasTouch: true,
    locale: 'zh-CN', ignoreHTTPSErrors: true,
  });
  await context.addInitScript(STEALTH);
  const page = context.pages()[0] || (await context.newPage());

  console.log(`漫画爬虫 · 模型 ${visionModel} · ${headed ? '有窗口' : '无窗口'}`);
  if (daemon) {
    if (resolveBooks() === null) { console.error('守护模式需要 --watches 或 --book'); process.exit(1); }
    console.log(`守护模式：每 ${intervalMin} 分钟检查一次关注列表的更新 · Ctrl+C 退出\n`);
    // Daemon never returns; the browser context stays open across passes.
    while (true) {
      try {
        const n = await crawlPass(page);
        console.log(`\n本轮爬取: ${n} 章`);
      } catch (e) {
        console.error('[本轮异常，跳过等待下一轮]', e.message);
      }
      console.log(`⏳ 下一轮在 ${intervalMin} 分钟后…\n`);
      await sleep(intervalMin * 60 * 1000);
    }
  } else {
    const n = await crawlPass(page);
    await context.close();
    console.log(`\n═══ 完成 ═══`);
    console.log(`  本轮爬取: ${n} 章`);
    console.log(`  数据目录: ${dataDir}`);
  }
}

main().catch((e) => { console.error('\n[FATAL]', e); process.exit(1); });