import { createReadStream, existsSync, statSync } from 'node:fs';
import { createServer } from 'node:http';
import { extname, join, normalize, relative } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('.', import.meta.url));
const brandMark = fileURLToPath(new URL('../../assets/branding/hereiam_v3_logo/logo_monochrome_black_1024.svg', import.meta.url));
const port = Number(process.env.WHITEBOARD_MVP_PORT ?? 4178);
const mime = {
  '.css': 'text/css; charset=utf-8',
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.mjs': 'text/javascript; charset=utf-8',
  '.svg': 'image/svg+xml',
};

createServer((request, response) => {
  const requested = decodeURIComponent(new URL(request.url, 'http://localhost').pathname);
  const relativePath = requested === '/' ? 'index.html' : requested.replace(/^\/+/, '');
  const resolved = requested === '/brand-mark.svg'
    ? brandMark
    : normalize(join(root, relativePath));
  const outsideRoot = resolved !== brandMark && relative(root, resolved).startsWith('..');
  if (outsideRoot || !existsSync(resolved) || !statSync(resolved).isFile()) {
    response.writeHead(404, { 'content-type': 'text/plain; charset=utf-8' });
    response.end('Not found');
    return;
  }

  response.writeHead(200, {
    'content-type': mime[extname(resolved)] ?? 'application/octet-stream',
    'cache-control': 'no-store',
  });
  createReadStream(resolved).pipe(response);
}).listen(port, '127.0.0.1', () => {
  console.log(`Here I am whiteboard MVP: http://127.0.0.1:${port}`);
});
