#!/usr/bin/env node
/**
 * manwa.me structure probe.
 *
 * Why this exists: manwa.me has Cloudflare + an anti-debug `debugger` loop +
 * obfuscated JS that decrypts image URLs at runtime. There is NO clean chapter
 * JSON API (the directory page loads chapters from SSR/obfuscated JS, not XHR).
 * So a plain HTTP crawler cannot work — we must drive a real browser and let
 * the site's own JS run, then scrape the rendered DOM + network.
 *
 * This probe opens a VISIBLE browser window so YOU log in once (your account
 * tier decides what is visible — we never search, only follow your watches).
 * The script never reads your password; the login lives only in the local
 * browser profile (.manwa_profile). It then dumps a compact summary of the
 * directory page + one chapter page so the real crawler can be written.
 *
 * Run:
 *   cd tools/comic_server
 *   npm install
 *   npx playwright install chromium
 *   node probe_manwa.mjs [bookUrl]
 *
 * The good news: the `debugger` anti-debug trap only fires when DevTools is
 * open. Automation does not open DevTools, so it is NOT paused by it.
 */
import { existsSync, mkdirSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createInterface } from 'node:readline/promises';

const scriptDir = dirname(fileURLToPath(import.meta.url));
const profileDir = join(scriptDir, '.manwa_profile');
const outDir = join(scriptDir, 'probe_out');
if (!existsSync(outDir)) mkdirSync(outDir, { recursive: true });

let chromium;
try {
  ({ chromium } = await import('playwright'));
} catch {
  console.error('\n[!] playwright 未安装。请先在该目录运行：');
  console.error('    npm install');
  console.error('    npx playwright install chromium\n');
  process.exit(1);
}

const bookUrlArg = process.argv[2] || null;

// Anti-detection: strip automation fingerprints so the site treats us like a
// normal logged-in user. (Does not touch your credentials.)
const STEALTH = () => {
  Object.defineProperty(navigator, 'webdriver', { get: () => undefined });
  Object.defineProperty(navigator, 'languages', { get: () => ['zh-CN', 'zh', 'en'] });
  Object.defineProperty(navigator, 'plugins', {
    get: () => [1, 2, 3, 4, 5],
  });
  // chrome.runtime presence is a common bot check
  if (!window.chrome) window.chrome = {};
  if (!window.chrome.runtime) window.chrome.runtime = { id: undefined };
  // permissions.query should not betray automation by denying notifications
  const origQuery = window.Permissions && window.Permissions.prototype.query;
  if (origQuery) {
    window.Permissions.prototype.query = function (params) {
      return params && params.name === 'notifications'
        ? Promise.resolve({ state: Notification.permission })
        : origQuery.call(this, params);
    };
  }
  // remove chromedriver leak vars if any
  for (const k of Object.keys(window)) {
    if (/^cdc_/.test(k)) {
      try { delete window[k]; } catch {}
    }
  }
};

function hostOf(u) {
  try { return new URL(u).host; } catch { return '?'; }
}

async function ask(rl, q) {
  return (await rl.question(q)).trim();
}

async function main() {
  const rl = createInterface({ input: process.stdin, output: process.stdout });

  console.log('\n启动浏览器（会弹出一个窗口）…');
  const context = await chromium.launchPersistentContext(profileDir, {
    headless: false,
    args: [
      '--disable-blink-features=AutomationControlled',
      '--no-first-run',
      '--no-default-browser-check',
    ],
    // manwa.me 是移动优先站：完整 UI（含底栏登录入口）只在移动视口下渲染。
    // 桌面视口会丢掉底栏，导致无法登录 —— 故模拟手机（与你平时手机模式一致）。
    userAgent:
      'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 ' +
      '(KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36',
    viewport: { width: 390, height: 844 },
    deviceScaleFactor: 3,
    isMobile: true,
    hasTouch: true,
    locale: 'zh-CN',
    ignoreHTTPSErrors: true,
  });
  await context.addInitScript(STEALTH);

  const page = context.pages()[0] || (await context.newPage());

  // Network capture (image URLs + fetch/xhr bodies)
  const imgNetUrls = [];
  const fetches = [];
  page.on('response', async (res) => {
    const req = res.request();
    const ct = (res.headers()['content-type'] || '').toLowerCase();
    const u = res.url();
    if (ct.startsWith('image/') || req.resourceType() === 'image') {
      imgNetUrls.push(u);
    }
    if (req.resourceType() === 'fetch' || req.resourceType() === 'xhr') {
      try {
        const body = await res.text();
        fetches.push({ url: u, status: res.status(), body: body.slice(0, 1500) });
      } catch {}
    }
  });

  // 1) Land on the site, let the user log in.
  try {
    await page.goto('https://manwa.me/', { waitUntil: 'domcontentloaded', timeout: 30000 });
  } catch (e) {
    console.log('（首页加载提示：' + e.message.split('\n')[0] + '，没关系，继续）');
  }

  console.log('\n========================================================');
  console.log(' 请在弹出的浏览器窗口里【登录你的 manwa 账号】。');
  console.log(' （现在是手机界面，登录入口在【底栏】的用户/我的图标）');
  console.log(' 看到书架 / 头像 / 已登录状态后，回到这个终端按【回车】。');
  console.log(' （脚本不会读取你的密码，登录态只存在本机 .manwa_profile）');
  console.log('========================================================\n');
  await ask(rl, '登录好了吗？登录好就按回车继续 >>> ');

  // 2) Get a book URL.
  let bookUrl = bookUrlArg || (await ask(rl, '\n粘贴一本漫画的【目录页】URL（含 /book/ 的，如 https://manwa.me/book/495246）>>> '));
  if (!/^https?:\/\//.test(bookUrl)) bookUrl = 'https://manwa.me/' + bookUrl.replace(/^\/+/, '');

  console.log('\n→ 打开目录页：' + bookUrl);
  imgNetUrls.length = 0; fetches.length = 0;
  try {
    await page.goto(bookUrl, { waitUntil: 'networkidle', timeout: 45000 });
  } catch (e) {
    console.log('（networkidle 超时，改用 domcontentloaded 继续：' + e.message.split('\n')[0] + '）');
    try { await page.goto(bookUrl, { waitUntil: 'domcontentloaded', timeout: 30000 }); } catch {}
  }
  // let obfuscated JS settle + render chapter list
  try { await page.waitForSelector('a[href*="/chapter/"], [href*="/chapter/"]', { timeout: 12000 }); } catch {}
  await page.waitForTimeout(3000);

  const bookDump = await page.evaluate(() => {
    const title = document.title;
    const chapterLinks = Array.from(document.querySelectorAll('[href*="/chapter/"]'))
      .map((el) => ({ href: el.getAttribute('href'), text: (el.innerText || el.textContent || '').trim() }))
      .filter((x) => x.href);
    // de-dup by href
    const seen = new Set();
    const chapters = [];
    for (const c of chapterLinks) {
      if (seen.has(c.href)) continue;
      seen.add(c.href);
      chapters.push(c);
    }
    // fallback: any anchor hrefs (in case chapters use onclick, not href)
    const allAnchors = Array.from(document.querySelectorAll('a[href]')).map((a) => a.getAttribute('href'));
    const bodyText = (document.body.innerText || '').slice(0, 1200);
    return { title, chapters, allAnchors: allAnchors.slice(0, 60), bodyText };
  });

  // 3) Open the first chapter.
  let firstChapterHref = bookDump.chapters[0] && bookDump.chapters[0].href;
  if (!firstChapterHref) {
    const m = (bookDump.allAnchors || []).find((h) => h && h.includes('/chapter/'));
    firstChapterHref = m;
  }
  let chapterAbs = null;
  if (firstChapterHref) {
    chapterAbs = /^https?:\/\//.test(firstChapterHref)
      ? firstChapterHref
      : 'https://manwa.me/' + firstChapterHref.replace(/^\/+/, '');
  }

  let chapterDump = null;
  if (chapterAbs) {
    console.log('→ 打开章节页：' + chapterAbs);
    imgNetUrls.length = 0; fetches.length = 0;
    try {
      await page.goto(chapterAbs, { waitUntil: 'networkidle', timeout: 45000 });
    } catch (e) {
      try { await page.goto(chapterAbs, { waitUntil: 'domcontentloaded', timeout: 30000 }); } catch {}
    }
    try { await page.waitForSelector('img', { timeout: 15000 }); } catch {}
    await page.waitForTimeout(5000); // let decryption + lazy images fire

    chapterDump = await page.evaluate(() => {
      const imgs = Array.from(document.querySelectorAll('img'))
        .map((i) => ({ src: i.currentSrc || i.src, dataSrc: i.getAttribute('data-src') || i.getAttribute('data-original') }));
      const bgs = [];
      const els = Array.from(document.querySelectorAll('div,section,figure,li,span')).slice(0, 400);
      for (const el of els) {
        const b = getComputedStyle(el).backgroundImage;
        if (b && b !== 'none' && b.includes('url(')) bgs.push(b);
      }
      const title = document.title;
      const bodyText = (document.body.innerText || '').slice(0, 600);
      return { title, imgs, bgs: [...new Set(bgs)].slice(0, 30), bodyText };
    });
  }

  await context.close();
  rl.close();

  // ── Build compact summary ────────────────────────────────────────────────
  const domainCount = {};
  for (const u of imgNetUrls) {
    const h = hostOf(u);
    domainCount[h] = (domainCount[h] || 0) + 1;
  }
  const chapterImgSrcs = chapterDump ? chapterDump.imgs.map((i) => i.src).filter(Boolean) : [];
  const chapterDataSrcs = chapterDump ? chapterDump.imgs.map((i) => i.dataSrc).filter(Boolean) : [];

  const summary = {
    book_url: bookUrl,
    book_title: bookDump.title,
    chapter_count: bookDump.chapters.length,
    chapter_samples: bookDump.chapters.slice(0, 5),
    chapter_url: chapterAbs,
    chapter_title: chapterDump && chapterDump.title,
    chapter_img_count: chapterDump ? chapterDump.imgs.length : 0,
    chapter_img_src_samples: chapterImgSrcs.slice(0, 5),
    chapter_img_datasrc_samples: chapterDataSrcs.slice(0, 5),
    chapter_bg_samples: chapterDump ? chapterDump.bgs.slice(0, 5) : [],
    network_image_domain_counts: domainCount,
    network_image_url_samples: imgNetUrls.slice(0, 6),
    fetch_xhr_on_chapter: fetches.slice(0, 8),
  };

  writeFileSync(join(outDir, 'summary.json'), JSON.stringify(summary, null, 2));
  writeFileSync(join(outDir, 'book_body.txt'), bookDump.bodyText || '');
  writeFileSync(join(outDir, 'chapter_body.txt'), (chapterDump && chapterDump.bodyText) || '');

  const lines = [];
  lines.push('================ PROBE SUMMARY （复制以下整段发给我）================');
  lines.push('[book] ' + bookUrl);
  lines.push('  title      : ' + bookDump.title);
  lines.push('  章节数     : ' + bookDump.chapters.length);
  lines.push('  章节样本   :');
  for (const c of bookDump.chapters.slice(0, 4)) lines.push('    ' + c.href + '  |  ' + c.text);
  if (bookDump.chapters.length === 0) {
    lines.push('  （没抓到 /chapter/ 链接！allAnchors 样本：）');
    for (const h of (bookDump.allAnchors || []).slice(0, 15)) lines.push('    ' + h);
    lines.push('  bodyText 前 600 字：' + (bookDump.bodyText || '').slice(0, 600).replace(/\n/g, ' ⏎ '));
  }
  lines.push('[chapter] ' + (chapterAbs || '(无)'));
  if (chapterDump) {
    lines.push('  title      : ' + chapterDump.title);
    lines.push('  <img> 数量 : ' + chapterDump.imgs.length);
    lines.push('  img.src 样本:');
    for (const s of chapterImgSrcs.slice(0, 5)) lines.push('    ' + s);
    if (chapterDataSrcs.length) {
      lines.push('  img data-src 样本:');
      for (const s of chapterDataSrcs.slice(0, 5)) lines.push('    ' + s);
    }
    if (chapterDump.bgs.length) {
      lines.push('  背景图样本 :');
      for (const b of chapterDump.bgs.slice(0, 4)) lines.push('    ' + b);
    }
  }
  lines.push('[network] 章节页 image 请求域名统计: ' + JSON.stringify(domainCount));
  lines.push('  image URL 样本:');
  for (const u of imgNetUrls.slice(0, 6)) lines.push('    ' + u);
  if (fetches.length) {
    lines.push('[network] 章节页 fetch/xhr:');
    for (const f of fetches.slice(0, 6)) lines.push('    [' + f.status + '] ' + f.url + '  ::  ' + (f.body || '').slice(0, 160).replace(/\n/g, ' '));
  }
  lines.push('详细文件已写入: ' + outDir);
  lines.push('================ END PROBE SUMMARY ================');

  console.log('\n' + lines.join('\n'));
}

main().catch((e) => {
  console.error('\n[FATAL]', e);
  process.exit(1);
});