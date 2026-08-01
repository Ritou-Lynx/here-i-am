import { chromium } from 'playwright';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const profileDir = join(__dirname, 'data', 'browser-profile');

const ctx = await chromium.launchPersistentContext(profileDir, {
  headless: true,
  args: ['--disable-blink-features=AutomationControlled', '--no-first-run', '--disable-gpu'],
  userAgent: 'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36',
  viewport: { width: 390, height: 844 },
  deviceScaleFactor: 3, isMobile: true, hasTouch: true,
  locale: 'zh-CN', ignoreHTTPSErrors: true,
});

const page = ctx.pages()[0] || await ctx.newPage();

const cookies = await ctx.cookies('https://manwa.me');
console.log('Cookies:', cookies.length);
for (const c of cookies) console.log(' ', c.name, '=', c.value.substring(0, 30));

// Try first book to verify login works
await page.goto('https://manwa.me/book/451355', { waitUntil: 'domcontentloaded', timeout: 30000 });
console.log('First book URL:', page.url());
const chCount = await page.evaluate(() => Array.from(document.querySelectorAll('[href*="/chapter/"]')).length);
console.log('First book chapters:', chCount);

// Now try second book
await page.goto('https://manwa.me/book/446558', { waitUntil: 'domcontentloaded', timeout: 30000 });
console.log('Second book URL:', page.url());

await ctx.close();