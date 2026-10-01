import { RuntimeAdapterError, RuntimeErrorCode } from './runtime_adapter.mjs';

export const WORKBENCH_TEXT_ONLY_PROFILE = 'workbench_text_only_v1';

// Evidence from an isolated synthetic provider does not attest the capabilities
// of the ordinary authenticated app-server. No success receipt is issued until
// that execution boundary and terminal-stop confirmation are implemented.
export function workbenchTextOnlyAvailability() {
  return {
    profile: WORKBENCH_TEXT_ONLY_PROFILE,
    available: false,
    reason: 'text_only_isolation_unverified',
    fail_closed: true,
  };
}

export function requireSupportedRuntimeProfile(config, operation) {
  if (!Object.hasOwn(config, 'runtime_profile')) return;
  if (config.runtime_profile !== WORKBENCH_TEXT_ONLY_PROFILE) {
    throw new RuntimeAdapterError('Unknown runtime profile.', {
      code: RuntimeErrorCode.INVALID_REQUEST,
      operation,
      details: { reason: 'unknown_runtime_profile', fail_closed: true },
    });
  }
  throw new RuntimeAdapterError('The text-only runtime isolation has not been verified.', {
    code: RuntimeErrorCode.UNSUPPORTED_CAPABILITY,
    operation,
    details: workbenchTextOnlyAvailability(),
  });
}
