// Explicit opt-in Core server entry for personal domains. The legacy packaged
// i_core_server entry remains unchanged until the fixed package inventory is revised.
import { existsSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { CORE_PROTOCOL_VERSION } from './i_core_store.mjs';
import { createICoreServer, installICoreGracefulShutdown,
  isShortcutMailManualTestEnabled } from './i_core_server.mjs';
import { createConfiguredPersonalDomainRuntime } from './personal_domain_runtime.mjs';
import { createConfiguredShortcutMailRelay } from './shortcut_mail_relay.mjs';

const modulePath = fileURLToPath(import.meta.url);
const moduleDir = path.dirname(modulePath);

export async function startPersonalDomainServer({
  environment = process.env,
  createRuntime = createConfiguredPersonalDomainRuntime,
  installShutdown = installICoreGracefulShutdown,
  logger = console,
} = {}) {
  const configValue = environment.I_CORE_PERSONAL_DOMAIN_CONFIG?.trim();
  if (!configValue) throw new Error('I_CORE_PERSONAL_DOMAIN_CONFIG is required');
  const databasePath = path.resolve(environment.I_CORE_DATABASE ?? path.join(moduleDir, '.state', 'i-core.sqlite'));
  const configPath = path.resolve(configValue);
  const pairingCode = environment.I_CORE_PAIRING_CODE?.trim() ? environment.I_CORE_PAIRING_CODE : null;
  const host = environment.I_CORE_HOST ?? '127.0.0.1';
  const port = Number(environment.I_CORE_PORT ?? 47841);
  const shortcutMailConfigPath = environment.I_CORE_SHORTCUT_MAIL_CONFIG
    ?? path.join(moduleDir, '.state', 'shortcut-mail-relay.json');
  const shortcutMailDatabasePath = environment.I_CORE_SHORTCUT_MAIL_DATABASE
    ?? path.join(moduleDir, '.state', 'shortcut-mail-journal.sqlite');
  let shortcutMailRelay = null;
  if (isShortcutMailManualTestEnabled(environment) && existsSync(shortcutMailConfigPath)) {
    try {
      shortcutMailRelay = createConfiguredShortcutMailRelay({
        configPath: shortcutMailConfigPath,
        databasePath: shortcutMailDatabasePath,
      });
    } catch (error) {
      logger.error(`Shortcut mail relay is disabled because its local configuration is invalid: ${error.message}`);
    }
  }
  const runtime = await createRuntime({
    databasePath,
    configPath,
    createServer: createICoreServer,
    serverOptions: {
      pairingCode,
      certPath: environment.I_CORE_CERT ?? null,
      keyPath: environment.I_CORE_KEY ?? null,
      workerSecret: environment.I_CORE_WORKER_SECRET ?? null,
      companionReplyJobsEnabled: environment.I_CORE_COMPANION_REPLY_JOBS === '1',
      companionUploadMode: environment.I_CORE_COMPANION_UPLOAD_MODE ?? 'legacy_b3',
      localTranscriptGrantsPath: environment.I_CORE_LOCAL_TRANSCRIPT_GRANTS,
      historicalReplayApprovalsPath: environment.I_CORE_HISTORICAL_REPLAY_APPROVALS,
      shortcutMailRelay,
      ownsShortcutMailRelay: Boolean(shortcutMailRelay),
      activityAdminSecret: environment.I_CORE_ACTIVITY_ADMIN_SECRET ?? null,
    },
  });
  try {
    const address = await runtime.core.listen({ host, port });
    installShutdown(runtime.core);
    const protocol = environment.I_CORE_CERT && environment.I_CORE_KEY ? 'https' : 'http';
    logger.log(`i core ${CORE_PROTOCOL_VERSION} with personal domains listening on ${protocol}://${address.address}:${address.port}`);
    if (!pairingCode) logger.log('Device pairing is disabled. Existing paired devices can continue using their tokens.');
    logger.log(shortcutMailRelay ? 'Manual Shortcut mail test relay is enabled.'
      : 'Manual Shortcut mail test relay is disabled.');
    if (protocol === 'http') logger.log('Keep this bound to loopback and expose it through Tailscale Serve for phone access.');
    return runtime;
  } catch (error) {
    await runtime.core.close().catch(() => {});
    throw error;
  }
}

if (process.argv[1] && path.resolve(process.argv[1]) === path.resolve(modulePath)) {
  startPersonalDomainServer().catch(error => {
    console.error(`i core personal-domain server failed to start: ${error.message}`);
    process.exitCode = 1;
  });
}
