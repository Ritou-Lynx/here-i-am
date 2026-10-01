import { ACTIVITY_MAX_TTL_MS } from '../i_core/activity_control_plane.mjs';

export const WINDOWS_SOURCES = Object.freeze(['windows_wts', 'windows_last_input']);
const UINT32_RANGE = 0x1_0000_0000;

export function reject(code) {
  throw Object.assign(new Error(code), { code });
}

function integer(value, minimum = 0, maximum = Number.MAX_SAFE_INTEGER) {
  if (!Number.isSafeInteger(value) || value < minimum || value > maximum) reject('invalid_native_integer');
  return value;
}

function exact(value, keys) {
  if (!value || Object.getPrototypeOf(value) !== Object.prototype
    || Reflect.ownKeys(value).length !== keys.length || keys.some((key) => !Object.hasOwn(value, key))) {
    reject('invalid_native_shape');
  }
}

export function idleBucket(idleMs) {
  integer(idleMs);
  if (idleMs < 60_000) return 'lt_1m';
  if (idleMs < 300_000) return '1_5m';
  if (idleMs < 900_000) return '5_15m';
  return '15m_plus';
}

export function parseNativeFrame(input) {
  if (typeof input !== 'string' || input.length < 20 || input.length > 1024 || /[^\x20-\x7e]/.test(input)) {
    reject('invalid_native_frame');
  }
  const parts = input.split('|');
  if (parts.length !== 11 || parts[0] !== 'MDA2V1') reject('invalid_native_frame');
  const packet = {
    nonce: parts[1], epoch: parts[2], sessionId: Number(parts[3]), source: parts[4], kind: parts[5],
    captureAge: Number(parts[6]), captureWall: Number(parts[7]), sequence: Number(parts[8]),
    qualityEpoch: Number(parts[9]), value: parts[10],
  };
  if (!/^[A-Za-z0-9_-]{32,64}$/.test(packet.nonce)
    || !/^[a-f0-9-]{36}$/.test(packet.epoch)
    || !['windows_wts','windows_last_input','quality'].includes(packet.source)
    || !['session.locked','session.unlocked','input.sample','power.suspended','power.resumed','source.gap'].includes(packet.kind)) {
    reject('invalid_native_frame');
  }
  for (const key of ['sessionId','captureAge','captureWall','sequence','qualityEpoch']) integer(packet[key]);
  if (packet.sequence < 1 || packet.captureWall < 1) reject('invalid_native_frame');
  if (packet.kind === 'input.sample') integer(Number(packet.value), 0, UINT32_RANGE - 1);
  else if (packet.kind === 'source.gap') {
    if (!['native_overflow','callback_gap','permission_lost','source_restart'].includes(packet.value)) reject('invalid_native_frame');
  } else if (packet.value !== '') reject('invalid_native_frame');
  if (packet.kind.startsWith('session.') && packet.source !== 'windows_wts') reject('native_source_mismatch');
  if (packet.kind === 'input.sample' && packet.source !== 'windows_last_input') reject('native_source_mismatch');
  if (packet.kind.startsWith('power.') && packet.source !== 'quality') reject('native_source_mismatch');
  if (packet.kind === 'source.gap' && !WINDOWS_SOURCES.includes(packet.source)) reject('native_source_mismatch');
  return Object.freeze(packet);
}

export function initialNativeSignalState({ nonce, epoch, sessionId }) {
  if (typeof nonce !== 'string' || typeof epoch !== 'string') reject('invalid_native_channel');
  integer(sessionId);
  return {
    nonce, epoch, sessionId, sequence: 0, ageFloor: -1, wallFloor: -1, qualityEpoch: 0,
    suspended: false, reason: 'unobserved', sourceAge: {}, lastInputAbsolute: null,
    lastInputTick32: null, observations: {},
  };
}

function reconstructLastInput(captureAge, tick32, maxTrustedIdleMs) {
  const base = captureAge - (captureAge % UINT32_RANGE);
  let absolute = base + tick32;
  if (absolute > captureAge) absolute -= UINT32_RANGE;
  const idle = captureAge - absolute;
  if (absolute < 0 || idle < 0 || idle > maxTrustedIdleMs) reject('last_input_coordinate_untrusted');
  return { absolute, idle };
}

export function reduceNativePacket(previous, packet, { maxTrustedIdleMs = ACTIVITY_MAX_TTL_MS } = {}) {
  exact(packet, ['nonce','epoch','sessionId','source','kind','captureAge','captureWall','sequence','qualityEpoch','value']);
  integer(maxTrustedIdleMs, 900_000, ACTIVITY_MAX_TTL_MS);
  const state = structuredClone(previous);
  if (packet.nonce !== state.nonce || packet.epoch !== state.epoch) reject('native_channel_mismatch');
  if (packet.sessionId !== state.sessionId) reject('native_session_mismatch');
  if (packet.sequence !== state.sequence + 1) reject('native_sequence_gap');
  if (packet.captureAge < state.ageFloor) reject('native_age_regression');
  if (packet.captureWall < state.wallFloor) reject('native_wall_regression');
  const qualityChange = packet.kind === 'power.suspended' || packet.kind === 'power.resumed';
  if (qualityChange ? packet.qualityEpoch !== state.qualityEpoch + 1 : packet.qualityEpoch !== state.qualityEpoch) {
    reject('native_quality_epoch_mismatch');
  }
  state.sequence = packet.sequence; state.ageFloor = packet.captureAge; state.wallFloor = packet.captureWall;
  if (qualityChange) {
    state.qualityEpoch = packet.qualityEpoch;
    state.suspended = packet.kind === 'power.suspended';
    state.observations = {}; state.lastInputAbsolute = null; state.lastInputTick32 = null;
    state.sourceAge = {}; state.reason = state.suspended ? 'suspended' : 'resume_gap';
    return { state, fact: null };
  }
  if (packet.kind === 'source.gap') {
    delete state.observations[packet.source]; delete state.sourceAge[packet.source];
    if (packet.source === 'windows_last_input') { state.lastInputAbsolute = null; state.lastInputTick32 = null; }
    state.reason = packet.value;
    return { state, fact: null };
  }
  if (state.suspended) reject('native_observation_while_suspended');
  const priorAge = state.sourceAge[packet.source];
  if (priorAge !== undefined && packet.captureAge <= priorAge) reject('native_source_age_non_increasing');
  state.sourceAge[packet.source] = packet.captureAge;
  let fact;
  if (packet.kind.startsWith('session.')) {
    fact = { source: 'windows_wts', kind: packet.kind, payload: {}, signal_at_ms: packet.captureWall };
  } else {
    const tick32=Number(packet.value);
    const reconstructed = state.lastInputTick32===tick32 && state.lastInputAbsolute!==null
      ? {absolute:state.lastInputAbsolute,idle:packet.captureAge-state.lastInputAbsolute}
      : reconstructLastInput(packet.captureAge,tick32,maxTrustedIdleMs);
    if(reconstructed.idle<0||reconstructed.idle>maxTrustedIdleMs)reject('last_input_coordinate_untrusted');
    if (state.lastInputAbsolute !== null && reconstructed.absolute < state.lastInputAbsolute) {
      reject('last_input_tick_regression');
    }
    state.lastInputAbsolute = reconstructed.absolute; state.lastInputTick32=tick32;
    fact = { source: 'windows_last_input', kind: 'input.idle_bucket',
      payload: { bucket: idleBucket(reconstructed.idle) }, signal_at_ms: packet.captureWall };
  }
  state.observations[fact.source] = { at_ms: fact.signal_at_ms, kind: fact.kind,
    payload: structuredClone(fact.payload), quality_epoch: state.qualityEpoch };
  state.reason = 'sample_observed';
  return { state, fact };
}

export function coverageReport(state, nowMs, { maxGapMs, deliveryBySource = {} }) {
  integer(nowMs); integer(maxGapMs, 1, ACTIVITY_MAX_TTL_MS);
  const sources = {};
  for (const source of WINDOWS_SOURCES) {
    const observation = state.observations[source];
    const reason = state.suspended ? 'suspended' : !observation ? state.reason
      : nowMs < observation.at_ms ? 'clock_regression'
        : nowMs - observation.at_ms > maxGapMs ? 'source_stale' : 'sample_observed';
    sources[source] = {
      status: reason === 'sample_observed' ? 'sample_observed' : 'unknown', reason,
      delivery: deliveryBySource[source] ?? 'unobserved',
      observation: reason === 'sample_observed' ? structuredClone(observation) : null,
    };
  }
  return { sources, person_state: 'unknown', server_completeness: 'unknown' };
}
