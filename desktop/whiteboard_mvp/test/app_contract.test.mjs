import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

const root = new URL('../', import.meta.url);

test('desktop shell has no permanent top bar and keeps the three product entries', async () => {
  const html = await readFile(new URL('index.html', root), 'utf8');
  assert.ok(!html.includes('<header'));
  assert.match(html, /data-route="home"/);
  assert.match(html, /data-route="boards"/);
  assert.match(html, /data-route="cards"/);
  assert.match(html, /hia-sidebar-toggle/);
  assert.match(html, /hia-brand-mark/);
  assert.match(html, /hia-i-mark/);
  assert.ok(!html.includes('<span class="hia-brand-mark">i</span>'));
});

test('board UI exposes move, resize, zoom and durable snapshot hooks', async () => {
  const app = await readFile(new URL('src/app.mjs', root), 'utf8');
  assert.match(app, /data-resize-item/);
  assert.match(app, /moveBoardItem/);
  assert.match(app, /updateViewport/);
  assert.match(app, /localStorage\.setItem/);
  assert.match(app, /application\/x-hia-card/);
  assert.match(app, /<h2 class="hia-module-label">/);
  assert.match(app, /放入最近白板/);
  assert.ok(!app.includes("'今日'"), 'time grouping is not rendered as a status pill');
});

test('neutral paper tokens keep Palm green and gold as restrained accents', async () => {
  const css = await readFile(new URL('styles.css', root), 'utf8');
  assert.match(css, /--hia-green:/);
  assert.match(css, /--hia-gold:/);
  assert.match(css, /--hia-sidebar-width:/);
  assert.match(css, /\.hia-app\.is-nav-collapsed/);
  assert.match(css, /--hia-divider-strong:/);
  assert.match(css, /mask: url\("\/brand-mark\.svg"\)/);
});
