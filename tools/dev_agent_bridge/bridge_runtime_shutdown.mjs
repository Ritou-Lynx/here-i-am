// Graceful host shutdown coordinates owned runtimes before the HTTP listener.
// This summary is not a task stop receipt or proof about a forced process exit.
const failure = code => Object.assign(new Error(code), { code });

function closeHttpServer(server, graceMs) {
  return new Promise((resolve, reject) => {
    let settled = false; let forceTimer; let deadline;
    const finish = error => {
      if (settled) return;
      settled = true;
      clearTimeout(forceTimer); clearTimeout(deadline);
      if (!error || (error.code === 'ERR_SERVER_NOT_RUNNING' && server.listening === false)) resolve();
      else reject(failure('bridge_http_close_unconfirmed'));
    };
    forceTimer = setTimeout(() => {
      // Runtime owners have already closed. Remaining HTTP connections cannot
      // be used to postpone host exit indefinitely.
      try {
        if (typeof server.closeAllConnections !== 'function') {
          finish(failure('bridge_http_close_timeout')); return;
        }
        server.closeAllConnections();
        if (!settled) deadline = setTimeout(() => finish(failure('bridge_http_close_timeout')), 1000);
      } catch { finish(failure('bridge_http_close_unconfirmed')); }
    }, graceMs);
    try {
      server.close(finish);
      if (!settled) server.closeIdleConnections?.();
    } catch { finish(failure('bridge_http_close_unconfirmed')); }
  });
}

export function createBridgeRuntimeShutdown({ runtimeApi, server, httpGraceMs = 5000 }) {
  if (typeof runtimeApi?.stop !== 'function' || typeof server?.close !== 'function'
    || !Number.isSafeInteger(httpGraceMs) || httpGraceMs < 1 || httpGraceMs > 30000) {
    throw failure('bridge_shutdown_options_invalid');
  }
  let stopping = false; let inFlight = null;
  return Object.freeze({
    get isStopping() { return stopping; },
    shutdown() {
      if (inFlight) return inFlight;
      stopping = true;
      const attempt = Promise.resolve().then(async () => {
        // stop must retain unknown native ownership and reject if any required
        // close is unconfirmed. A failed shutdown can retry that same owner.
        await runtimeApi.stop({ permanent: true });
        await closeHttpServer(server, httpGraceMs);
        return Object.freeze({ status: 'closed', runtime_closed: true, http_server_closed: true });
      });
      inFlight = attempt;
      void attempt.catch(() => { if (inFlight === attempt) inFlight = null; });
      return attempt;
    },
  });
}

export function registerBridgeShutdownSignals({ emitter = process, shutdown, onClosed, onUnconfirmed }) {
  if (typeof emitter?.on !== 'function' || typeof emitter?.off !== 'function'
    || [shutdown, onClosed, onUnconfirmed].some(fn => typeof fn !== 'function')) {
    throw failure('bridge_shutdown_signals_invalid');
  }
  let watched = null;
  const request = () => {
    const attempt = shutdown();
    if (attempt === watched) return;
    watched = attempt;
    void attempt.then(onClosed, () => onUnconfirmed());
  };
  emitter.on('SIGINT', request); emitter.on('SIGTERM', request);
  return () => { emitter.off('SIGINT', request); emitter.off('SIGTERM', request); };
}
