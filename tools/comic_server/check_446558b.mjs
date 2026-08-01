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

// Capture all redirects
page.on('response', resp => {
  if (resp.status() >= 300 && resp.status() < 400) {
    console.log('REDIRECT:', resp.status(), resp.url(), '->', resp.headers()['location'] || '?');
  }
});

console.log('Navigating to https://manwa.me/book/446558 ...');
await page.goto('https://manwa.me/book/446558', { waitUntil: 'networkidle', timeout: 60000 });
await page.waitForTimeout(3000);

console.log('Final URL:', page.url());

const info = await page.evaluate(() => {
  const chapterLinks = Array.from(document.querySelectorAll('[href*="/chapter/"]'));
  const bodyText = document.body?.innerText?.substring(0, 300) || 'no body';
  return {
    title: document.title,
    url: window.location.href,
    chapterCount: chapterLinks.length,
    firstChapters: chapterLinks.slice(0, 5).map(a => ({ href: a.getAttribute('href'), text: a.innerText?.trim()?.substring(0, 40) })),
    bodyText,
  };
});

console.log(JSON.stringify(info, null, 2));
await ctx.close();