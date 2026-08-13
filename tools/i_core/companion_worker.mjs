import { readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import { CORE_PROTOCOL_VERSION } from './i_core_store.mjs';

const modulePath = fileURLToPath(import.meta.url);
const moduleDir = path.dirname(modulePath);

export class CompanionWorkerError extends Error {
  constructor(code, message, { status = null, retryable = false } = {}) {
    super(message);
    this.name = 'CompanionWorkerError';
    this.code = code;
    this.status = status;
    this.retryable = retryable;
  }
}

function required(value, name) {
  if (typeof value !== 'string' || !value.trim()) {
    throw new CompanionWorkerError('invalid_config', `${name} is required.`);
  }
  return value.trim();
}

function withoutTrailingSlash(value) {
  return value.replace(/\/+$/, '');
}

async function responseJson(response) {
  const text = await response.text();
  if (!text) return {};
  try {
    return JSON.parse(text);
  } catch (_) {
    throw new CompanionWorkerError(
      'invalid_response',
      `Expected JSON but received HTTP ${response.status}.`,
      { status: response.status },
    );
  }
}

export class ICoreWorkerClient {
  constructor({ baseUrl, workerSecret, fetchImpl = fetch }) {
    this.baseUrl = withoutTrailingSlash(required(baseUrl, 'core base URL'));
    this.workerSecret = required(workerSecret, 'worker secret');
    this.fetchImpl = fetchImpl;
  }

  async request(pathname, body) {
    const response = await this.fetchImpl(`${this.baseUrl}/v1/core${pathname}`, {
      method: 'POST',
      headers: {
        'x-core-protocol': CORE_PROTOCOL_VERSION,
        authorization: `Bearer ${this.workerSecret}`,
        'content-type': 'application/json',
      },
      body: JSON.stringify(body),
    });
    const payload = await responseJson(response);
    if (!response.ok) {
      throw new CompanionWorkerError(
        payload?.error?.code ?? 'core_request_failed',
        payload?.error?.message ?? `Core request failed with HTTP ${response.status}.`,
        {
          status: response.status,
          retryable: payload?.error?.retryable === true,
        },
      );
    }
    return payload;
  }

  acquireLease({ holderId, ttlMs }) {
    return this.request('/workers/leases', {
      workload: 'companion_reply',
      holder_id: holderId,
      ttl_ms: ttlMs,
    });
  }

  renewLease(lease, ttlMs) {
    return this.request('/workers/leases/renew', {
      ...this.#leaseProof(lease),
      ttl_ms: ttlMs,
    });
  }

  releaseLease(lease) {
    return this.request('/workers/leases/release', this.#leaseProof(lease));
  }

  claimReply(lease) {
    return this.request(
      '/workers/companion-replies/claim',
      this.#leaseProof(lease),
    );
  }

  completeReply(lease, { jobId, content, createdAtMs = Date.now() }) {
    return this.request('/workers/companion-replies/complete', {
      ...this.#leaseProof(lease),
      job_id: jobId,
      content,
      created_at_ms: createdAtMs,
    });
  }

  completeShadow(lease, {
    jobId,
    model,
    durationMs,
    replyCharacters,
  }) {
    return this.request('/workers/companion-replies/shadow-complete', {
      ...this.#leaseProof(lease),
      job_id: jobId,
      model,
      duration_ms: durationMs,
      reply_characters: replyCharacters,
    });
  }

  #leaseProof(lease) {
    return {
      workload: 'companion_reply',
      holder_id: lease.holder_id,
      lease_token: lease.lease_token,
      fencing_token: lease.fencing_token,
    };
  }
}

function textFromMessageContent(content) {
  if (typeof content === 'string') return content.trim();
  if (!Array.isArray(content)) return '';
  return content
    .map((part) => typeof part?.text === 'string' ? part.text : '')
    .join('')
    .trim();
}

export class OpenAICompatibleCompanionModel {
  constructor({
    baseUrl,
    apiKey,
    model,
    systemPrompt,
    temperature = 0.8,
    fetchImpl = fetch,
  }) {
    this.baseUrl = withoutTrailingSlash(required(baseUrl, 'model base URL'));
    this.apiKey = required(apiKey, 'model API key');
    this.model = required(model, 'model name');
    this.systemPrompt = required(systemPrompt, 'companion system prompt');
    this.temperature = temperature;
    this.fetchImpl = fetchImpl;
  }

  async generate(context) {
    if (!Array.isArray(context) || context.length === 0) {
      throw new CompanionWorkerError('empty_context', 'A reply job must include chat context.');
    }
    const messages = [
      { role: 'system', content: this.systemPrompt },
      ...context.map((item) => ({
        role: item.sender === 'companion' ? 'assistant' : 'user',
        content: item.content,
      })),
    ];
    const response = await this.fetchImpl(`${this.baseUrl}/chat/completions`, {
      method: 'POST',
      headers: {
        authorization: `Bearer ${this.apiKey}`,
        'content-type': 'application/json',
      },
      body: JSON.stringify({
        model: this.model,
        messages,
        temperature: this.temperature,
        stream: false,
      }),
    });
    const payload = await responseJson(response);
    if (!response.ok) {
      throw new CompanionWorkerError(
        'model_request_failed',
        payload?.error?.message ?? `Model request failed with HTTP ${response.status}.`,
        { status: response.status, retryable: response.status >= 500 || response.status === 429 },
      );
    }
    const content = textFromMessageContent(payload?.choices?.[0]?.message?.content);
    if (!content) {
      throw new CompanionWorkerError('empty_model_reply', 'The model returned an empty reply.');
    }
    return content;
  }
}

export class CompanionReplyWorker {
  constructor({
    coreClient,
    model,
    holderId,
    mode = 'shadow',
    leaseTtlMs = 30_000,
    renewEveryMs = 10_000,
    now = Date.now,
  }) {
    if (!['shadow', 'live'].includes(mode)) {
      throw new CompanionWorkerError('invalid_config', 'mode must be shadow or live.');
    }
    this.coreClient = coreClient;
    this.model = model;
    this.holderId = required(holderId, 'holder ID');
    this.mode = mode;
    this.leaseTtlMs = leaseTtlMs;
    this.renewEveryMs = renewEveryMs;
    this.now = now;
  }

  async runOnce() {
    let lease;
    let renewalError = null;
    let renewal = null;
    let renewalInFlight = Promise.resolve();
    try {
      lease = await this.coreClient.acquireLease({
        holderId: this.holderId,
        ttlMs: this.leaseTtlMs,
      });
    } catch (error) {
      if (error?.code === 'lease_held') {
        return { status: 'lease_held' };
      }
      throw error;
    }
    try {
      renewal = setInterval(() => {
        renewalInFlight = renewalInFlight
          .then(() => this.coreClient.renewLease(lease, this.leaseTtlMs))
          .catch((error) => {
            renewalError ??= error;
          });
      }, this.renewEveryMs);
      renewal.unref?.();

      const claimed = await this.coreClient.claimReply(lease);
      if (!claimed.job) return { status: 'idle' };
      const startedAt = this.now();
      const content = await this.model.generate(claimed.job.context);
      if (renewalError) throw renewalError;
      if (this.mode === 'shadow') {
        const durationMs = this.now() - startedAt;
        await this.coreClient.completeShadow(lease, {
          jobId: claimed.job.job_id,
          model: this.model.model ?? 'unknown',
          durationMs,
          replyCharacters: content.length,
        });
        return {
          status: 'shadow_generated',
          job_id: claimed.job.job_id,
          reply_characters: content.length,
          duration_ms: durationMs,
        };
      }
      const completed = await this.coreClient.completeReply(lease, {
        jobId: claimed.job.job_id,
        content,
        createdAtMs: this.now(),
      });
      return {
        status: 'completed',
        job_id: claimed.job.job_id,
        reply_sync_id: completed.reply_sync_id,
        reply_server_sequence: completed.reply_server_sequence,
        duration_ms: this.now() - startedAt,
      };
    } finally {
      if (renewal) clearInterval(renewal);
      await renewalInFlight;
      if (lease) {
        await this.coreClient.releaseLease(lease).catch(() => {});
      }
    }
  }
}

function secretFromEnvironment(name, fileName) {
  const direct = process.env[name];
  if (direct?.trim()) return direct.trim();
  const configuredFile = process.env[fileName];
  if (!configuredFile?.trim()) return '';
  return readFileSync(path.resolve(configuredFile), 'utf8').trim();
}

function systemPromptFromEnvironment() {
  if (process.env.I_COMPANION_SYSTEM_PROMPT?.trim()) {
    return process.env.I_COMPANION_SYSTEM_PROMPT.trim();
  }
  const promptFile = process.env.I_COMPANION_SYSTEM_PROMPT_FILE;
  if (!promptFile?.trim()) return '';
  return readFileSync(path.resolve(promptFile), 'utf8').trim();
}

export function workerFromEnvironment() {
  const workerSecret = secretFromEnvironment(
    'I_CORE_WORKER_SECRET',
    'I_CORE_WORKER_SECRET_FILE',
  );
  const modelApiKey = secretFromEnvironment(
    'I_COMPANION_MODEL_API_KEY',
    'I_COMPANION_MODEL_API_KEY_FILE',
  );
  return new CompanionReplyWorker({
    coreClient: new ICoreWorkerClient({
      baseUrl: process.env.I_CORE_BASE_URL ?? 'http://127.0.0.1:47841',
      workerSecret,
    }),
    model: new OpenAICompatibleCompanionModel({
      baseUrl: process.env.I_COMPANION_MODEL_BASE_URL,
      apiKey: modelApiKey,
      model: process.env.I_COMPANION_MODEL,
      systemPrompt: systemPromptFromEnvironment(),
      temperature: Number(process.env.I_COMPANION_TEMPERATURE ?? 0.8),
    }),
    holderId: process.env.I_COMPANION_WORKER_ID ?? 'private-pc-companion',
    mode: process.env.I_COMPANION_WORKER_MODE ?? 'shadow',
  });
}

async function main() {
  const once = process.argv.includes('--once');
  const intervalMs = Number(process.env.I_COMPANION_WORKER_POLL_MS ?? 2_000);
  const worker = workerFromEnvironment();
  do {
    const result = await worker.runOnce();
    console.log(JSON.stringify(result));
    if (once) break;
    await new Promise((resolve) => setTimeout(resolve, intervalMs));
  } while (true);
}

if (process.argv[1] && path.resolve(process.argv[1]) === path.resolve(modulePath)) {
  main().catch((error) => {
    console.error(JSON.stringify({
      status: 'failed',
      code: error?.code ?? 'worker_failed',
      message: error instanceof Error ? error.message : String(error),
      retryable: error?.retryable === true,
    }));
    process.exitCode = 1;
  });
}
