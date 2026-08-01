import { chromium } from 'playwright';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const profileDir = join(__dirname, 'data', 'browser-profile');

const ctx = await chromium.launchPersistentContext(profileDir, {
  headless: true,
  args: ['--disable-blink-features=AutomationControlled', '--no-first-run', '--disable-gpu', '--disable-web-security'],
  userAgent: 'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36',
  viewport: { width: 390, height: 844 },
  deviceScaleFactor: 3, isMobile: true, hasTouch: true,
  locale: 'zh-CN', ignoreHTTPSErrors: true,
});

const page = ctx.pages()[0] || await ctx.newPage();
await page.goto('https://manwa.me/book/446558', { waitUntil: 'domcontentloaded', timeout: 45000 });
await page.waitForTimeout(3000);

const info = await page.evaluate(() => {
  const title = document.title;
  const chapterLinks = Array.from(document.querySelectorAll('[href*="/chapter/"]'));
  return {
    title,
    chapterCount: chapterLinks.length,
    firstChapters: chapterLinks.slice(0, 5).map(a => ({ href: a.getAttribute('href'), text: a.innerText?.trim()?.substring(0, 30) })),
  };
});

console.log(JSON.stringify(info, null, 2));
await ctx.close();