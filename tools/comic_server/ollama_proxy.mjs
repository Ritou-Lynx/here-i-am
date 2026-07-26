#!/usr/bin/env node
/**
 * Tiny reverse proxy that rewrites the Host header before forwarding to the
 * local Ollama server.
 *
 * Why it exists: Ollama rejects requests whose Host header is not
 * 127.0.0.1/localhost/0.0.0.0 with HTTP 403 (anti-DNS-rebinding guard). When
 * the phone reaches Ollama through a Tailscale Serve proxy, the Host header is
 * the tailnet name (e.g. host.example.invalid), so Ollama 403s it. We cannot
 * rely on OLLAMA_ORIGINS / OLLAMA_HOST env vars because the Windows tray build
 * does not pick them up reliably without admin + a finicky restart.
 *
 * This proxy listens on 127.0.0.1:OLLAMA_PROXY_PORT (default 11435), accepts
 * any Host header (it does not validate it), and forwards the request to
 * 127.0.0.1:OLLAMA_BACKEND_PORT (default 11434) with the Host header rewritten
 * to the backend address — which Ollama accepts. Responses are streamed back
 * unchanged, so streaming generation works too.
 *
 * Tailscale Serve then points at THIS proxy:
 *   tailscale serve --bg --http=8081 http://127.0.0.1:11435
 * and the phone uses http://host.example.invalid:8081/v1 as the Ollama base URL.
 *
 * No admin, no firewall rule, no Ollama config change, Ollama stays loopback-only.
 */
import http from 'node:http';

const LISTEN_HOST = process.env.OLLAMA_PROXY_HOST || '127.0.0.1';
const LISTEN_PORT = Number(process.env.OLLAMA_PROXY_PORT || 11435);
const BACKEND_HOST = process.env.OLLAMA_BACKEND_HOST || '127.0.0.1';
const BACKEND_PORT = Number(process.env.OLLAMA_BACKEND_PORT || 11434);

const server = http.createServer((req, res) => {
  const headers = { ...req.headers, host: `${BACKEND_HOST}:${BACKEND_PORT}` };
  const proxyReq = http.request(
    {
      hostname: BACKEND_HOST,
      port: BACKEND_PORT,
      path: req.url,
      method: req.method,
      headers,
    },
    (proxyRes) => {
      res.writeHead(proxyRes.statusCode || 502, proxyRes.headers);
      proxyRes.pipe(res);
    },
  );
  proxyReq.on('error', (err) => {
    if (!res.headersSent) {
      res.writeHead(502, { 'content-type': 'application/json' });
    }
    res.end(JSON.stringify({ error: 'ollama_proxy_backend_error', message: err.message }));
  });
  req.pipe(proxyReq);
});

server.listen(LISTEN_PORT, LISTEN_HOST, () => {
  console.log(`ollama_proxy ${LISTEN_HOST}:${LISTEN_PORT} -> ${BACKEND_HOST}:${BACKEND_PORT} (Host rewritten)`);
});