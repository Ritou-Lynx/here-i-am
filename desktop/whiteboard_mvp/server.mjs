import { createReadStream, existsSync, statSync } from 'node:fs';
import { createServer } from 'node:http';
import { extname, join, normalize, relative } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('.', import.meta.url));
const brandMark = fileURLToPath(new URL('../../assets/branding/hereiam_v3_logo/logo_monochrome_black_1024.svg', import.meta.url));
const huiwenFont = fileURLToPath(new URL('../../assets/fonts/whiteboard/HuiwenMingChao-Regular.ttf', import.meta.url));
const port = Number(process.env.WHITEBOARD_MVP_PORT ?? 4178);
const mime = {
  '.css': 'text/css; charset=utf-8',
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.mjs': 'text/javascript; charset=utf-8',
  '.svg': 'image/svg+xml',
  '.ttf': 'font/ttf',
};
const extraRoots = new Map([
  ['/brand-mark.svg', brandMark],
  ['/fonts/HuiwenMingChao-Regular.ttf', huiwenFont],
]);

createServer((request, response) => {
  const requested = decodeURIComponent(new URL(request.url, 'http://localhost').pathname);
  const extra = extraRoots.get(requested);
  const relativePath = requested === '/' ? 'index.html' : requested.replace(/^\/+/, '');
  const resolved = extra
    ? extra
    : normalize(join(root, relativePath));
  const allowedExtra = [...extraRoots.values()];
  const outsideRoot = !allowedExtra.includes(resolved) && relative(root, resolved).startsWith('..');
  if (outsideRoot || !existsSync(resolved) || !statSync(resolved).isFile()) {
    response.writeHead(404, { 'content-type': 'text/plain; charset=utf-8' });
    response.end('Not found');
    return;
  }

  const isFont = extname(resolved) === '.ttf';
  response.writeHead(200, {
    'content-type': mime[extname(resolved)] ?? 'application/octet-stream',
    'cache-control': isFont ? 'public, max-age=86400, immutable' : 'no-store',
  });
  createReadStream(resolved).pipe(response);
}).listen(port, '127.0.0.1', () => {
  console.log(`Here I am whiteboard MVP: http://127.0.0.1:${port}`);
});