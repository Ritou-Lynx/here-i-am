import { execFileSync } from 'node:child_process';
import { createHash, randomUUID } from 'node:crypto';
import { existsSync } from 'node:fs';
import path from 'node:path';
import process from 'node:process';
import { fileURLToPath } from 'node:url';

const CHATGPT_PACKAGE = 'com.openai.chatgpt';
const MAX_ADB_BUFFER = 16 * 1024 * 1024;

const DEFAULT_TIMEOUTS = Object.freeze({
  foregroundMs: 10_000,
  draftMs: 15_000,
  sendMs: 15_000,
  responseMs: 120_000,
  audioStartMs: 15_000,
  audioEndMs: 180_000,
  recordAudioMs: 20_000,
  pollMs: 650,
});

export const SUPPORTED_PROFILES = Object.freeze([
  Object.freeze({
    id: 'chatgpt-1.2026.223-sm-s9110-zh-wetype-v1',
    packageName: CHATGPT_PACKAGE,
    versionCode: 2622320,
    versionName: '1.2026.223',
    deviceModel: 'SM-S9110',
    display: Object.freeze({ width: 1080, height: 2340 }),
    localePrefix: 'zh',
    inputMethodPackage: 'com.tencent.wetype',
    ui: Object.freeze({
      actionRowSize: 6,
      readAloudIndex: 3,
      populatedComposerControlRowSize: 3,
      populatedComposerControlRowSizes: Object.freeze([3]),
      emptyComposerRowSize: 4,
      emptyComposerVoiceLayouts: Object.freeze(['controls_right_of_editor']),
      actionRowMinHeightRatio: 0.04,
      actionRowMaxHeightRatio: 0.08,
      actionRowMaxWidthRatio: 0.7,
      controlRowGapRatio: 0.02,
      edgeControlMinWidthRatio: 0.08,
      edgeControlMaxWidthRatio: 0.18,
      composerLeftAnchorMaxRatio: 0.05,
      composerClusterGapMinRatio: 0.2,
      composerClusterContiguityRatio: 0.015,
      composerRightEdgeMinRatio: 0.95,
    }),
  }),
  Object.freeze({
    id: 'chatgpt-1.2026.230-sm-s9110-zh-wetype-v1',
    packageName: CHATGPT_PACKAGE,
    versionCode: 2623032,
    versionName: '1.2026.230',
    deviceModel: 'SM-S9110',
    display: Object.freeze({ width: 1080, height: 2340 }),
    localePrefix: 'zh',
    inputMethodPackage: 'com.tencent.wetype',
    ui: Object.freeze({
      actionRowSize: 6,
      readAloudIndex: 3,
      populatedComposerControlRowSize: 3,
      populatedComposerControlRowSizes: Object.freeze([3, 4]),
      populatedProjectComposerControlRowSizes: Object.freeze([5]),
      projectComposerLayout: Object.freeze({
        rowSize: 5,
        rightClusterSize: 4,
        rightClusterFirstLeftMinRatio: 0.42,
        rightClusterFirstLeftMaxRatio: 0.45,
        rightControlMinWidthRatio: 0.125,
        rightControlMaxWidthRatio: 0.135,
        rightControlGapMaxRatio: 0.006,
        targetRightMinRatio: 0.955,
        targetRightMaxRatio: 0.97,
      }),
      projectHeader: Object.freeze({
        allowedClassNames: Object.freeze(['android.view.View']),
        minTopRatio: 0.03,
        maxTopRatio: 0.12,
        maxBottomRatio: 0.16,
        maxLeftRatio: 0.35,
        maxRightRatio: 0.65,
        minHeightRatio: 0.02,
        maxHeightRatio: 0.1,
      }),
      emptyComposerRowSize: 4,
      emptyComposerVoiceLayouts: Object.freeze([
        'controls_right_of_editor',
        'controls_overlaid_in_editor',
      ]),
      actionRowMinHeightRatio: 0.04,
      actionRowMaxHeightRatio: 0.08,
      actionRowMaxWidthRatio: 0.7,
      controlRowGapRatio: 0.02,
      edgeControlMinWidthRatio: 0.08,
      edgeControlMaxWidthRatio: 0.18,
      composerLeftAnchorMaxRatio: 0.05,
      composerClusterGapMinRatio: 0.2,
      composerClusterContiguityRatio: 0.015,
      composerRightEdgeMinRatio: 0.95,
    }),
  }),
]);

export class BridgeError extends Error {
  constructor(code, state, message) {
    super(message);
    this.name = 'BridgeError';
    this.code = code;
    this.state = state;
  }
}

function sha256(value) {
  return createHash('sha256').update(String(value), 'utf8').digest('hex');
}

function isoNow(now = Date.now) {
  return new Date(now()).toISOString();
}

function asPositiveInteger(value, fallback) {
  if (value === undefined || value === null || value === '') return fallback;
  const parsed = Number(value);
  if (!Number.isInteger(parsed) || parsed <= 0) {
    throw new BridgeError('E_INPUT_INVALID', 'VALIDATE_INPUT', 'Timeouts must be positive integers');
  }
  return parsed;
}

function safePrompt(value) {
  const prompt = String(value ?? '').trim();
  if (!prompt) {
    throw new BridgeError('E_INPUT_PROMPT_REQUIRED', 'VALIDATE_INPUT', 'Live execution requires a prompt');
  }
  if (prompt.length > 1500 || /[\u0000\r\n]/u.test(prompt)) {
    throw new BridgeError(
      'E_INPUT_PROMPT_INVALID',
      'VALIDATE_INPUT',
      'Prompt must be one paragraph of at most 1500 characters',
    );
  }
  return prompt;
}

function safeConversationId(value) {
  const conversationId = String(value ?? '').trim().toLowerCase();
  if (!/^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$/u.test(conversationId)) {
    throw new BridgeError(
      'E_INPUT_CONVERSATION_ID_INVALID',
      'VALIDATE_INPUT',
      'Conversation ID must be a UUID-shaped ChatGPT conversation identifier',
    );
  }
  return conversationId;
}

function safeProjectTitle(value) {
  const projectTitle = String(value ?? '').trim();
  if (
    !projectTitle
    || projectTitle.length > 100
    || /[\u0000\r\n]/u.test(projectTitle)
  ) {
    throw new BridgeError(
      'E_INPUT_PROJECT_TITLE_INVALID',
      'VALIDATE_INPUT',
      'Project title must be one non-empty line of at most 100 characters',
    );
  }
  return projectTitle;
}

export function parseAdbDevices(output) {
  return String(output ?? '')
    .split(/\r?\n/u)
    .slice(1)
    .map((line) => line.trim().split(/\s+/u))
    .filter((parts) => parts.length >= 2 && parts[0])
    .map(([serial, state]) => ({ serial, state }));
}

export function selectDevice(devices, requestedSerial) {
  const online = devices.filter((device) => device.state === 'device');
  if (requestedSerial) {
    const selected = online.find((device) => device.serial === requestedSerial);
    if (!selected) {
      throw new BridgeError(
        'E_DEVICE_NOT_FOUND',
        'SELECT_DEVICE',
        'The requested ADB device is not online',
      );
    }
    return selected.serial;
  }
  if (online.length !== 1) {
    throw new BridgeError(
      online.length === 0 ? 'E_DEVICE_NOT_FOUND' : 'E_DEVICE_AMBIGUOUS',
      'SELECT_DEVICE',
      `Expected exactly one online ADB device; found ${online.length}`,
    );
  }
  return online[0].serial;
}

export function parsePackageInfo(output) {
  const text = String(output ?? '');
  const versionCode = text.match(/\bversionCode=(\d+)/u)?.[1];
  const versionName = text.match(/\bversionName=([^\s]+)/u)?.[1];
  if (!versionCode || !versionName) {
    throw new BridgeError(
      'E_PROFILE_PACKAGE_NOT_FOUND',
      'RESOLVE_APP_PROFILE',
      'ChatGPT package version could not be read',
    );
  }
  return { versionCode: Number(versionCode), versionName };
}

export function parseDisplaySize(output) {
  const match = String(output ?? '').match(/(?:Physical|Override) size:\s*(\d+)x(\d+)/iu);
  if (!match) {
    throw new BridgeError(
      'E_DEVICE_DISPLAY_UNKNOWN',
      'RESOLVE_APP_PROFILE',
      'Display size could not be read',
    );
  }
  return { width: Number(match[1]), height: Number(match[2]) };
}

export function parseKeyguardUnlocked(output) {
  const text = String(output ?? '');
  const locked = /(?:mShowingLockscreen|isStatusBarKeyguard|mKeyguardShowing|mIsShowing|\bshowing)\s*=\s*true/iu
    .test(text);
  const explicitUnlocked = /(?:mShowingLockscreen|isStatusBarKeyguard|mKeyguardShowing|mIsShowing|\bshowing)\s*=\s*false/iu
    .test(text);
  return explicitUnlocked && !locked;
}

export function parseDeviceAwake(output) {
  return /mWakefulness\s*=\s*Awake/iu.test(String(output ?? ''));
}

export function parseTopPackage(output) {
  return String(output ?? '')
    .match(/topResumedActivity=.*?\s([a-zA-Z0-9._]+)\//u)?.[1] ?? null;
}

export function resolveProfile(facts, profiles = SUPPORTED_PROFILES) {
  const inputPackage = String(facts.inputMethod ?? '').split('/')[0];
  const profile = profiles.find((candidate) => (
    candidate.packageName === facts.packageName
    && candidate.versionCode === facts.versionCode
    && candidate.versionName === facts.versionName
    && candidate.deviceModel === facts.deviceModel
    && candidate.display.width === facts.display.width
    && candidate.display.height === facts.display.height
    && String(facts.locale ?? '').startsWith(candidate.localePrefix)
    && inputPackage === candidate.inputMethodPackage
  ));
  if (!profile) {
    throw new BridgeError(
      'E_PROFILE_UNKNOWN',
      'RESOLVE_APP_PROFILE',
      'No exact ChatGPT UI profile matches this app, device, display, locale, and keyboard',
    );
  }
  return profile;
}

function decodeXmlAttribute(value) {
  return String(value ?? '')
    .replace(/&quot;/gu, '"')
    .replace(/&apos;/gu, "'")
    .replace(/&lt;/gu, '<')
    .replace(/&gt;/gu, '>')
    .replace(/&amp;/gu, '&');
}

function parseBounds(value) {
  const match = String(value ?? '').match(/^\[(\d+),(\d+)\]\[(\d+),(\d+)\]$/u);
  if (!match) return null;
  const bounds = {
    left: Number(match[1]),
    top: Number(match[2]),
    right: Number(match[3]),
    bottom: Number(match[4]),
  };
  bounds.width = bounds.right - bounds.left;
  bounds.height = bounds.bottom - bounds.top;
  bounds.centerX = Math.round((bounds.left + bounds.right) / 2);
  bounds.centerY = Math.round((bounds.top + bounds.bottom) / 2);
  return bounds;
}

export function parseUiSnapshot(xml, display) {
  const nodes = [];
  const nodePattern = /<node\b([^>]*)\/?>(?:<\/node>)?/gu;
  let nodeMatch;
  while ((nodeMatch = nodePattern.exec(String(xml ?? ''))) !== null) {
    const attributes = {};
    const attributePattern = /([\w-]+)="([^"]*)"/gu;
    let attributeMatch;
    while ((attributeMatch = attributePattern.exec(nodeMatch[1])) !== null) {
      attributes[attributeMatch[1]] = decodeXmlAttribute(attributeMatch[2]);
    }
    const bounds = parseBounds(attributes.bounds);
    if (!bounds) continue;
    nodes.push({
      className: attributes.class ?? '',
      packageName: attributes.package ?? '',
      resourceId: attributes['resource-id'] ?? '',
      textPresent: Boolean(attributes.text),
      contentDescriptionPresent: Boolean(attributes['content-desc']),
      clickable: attributes.clickable === 'true',
      enabled: attributes.enabled !== 'false',
      focusable: attributes.focusable === 'true',
      bounds,
    });
  }
  const structural = nodes.map((node) => ({
    c: node.className,
    p: node.packageName,
    r: node.resourceId,
    t: node.textPresent,
    d: node.contentDescriptionPresent,
    k: node.clickable,
    e: node.enabled,
    b: [
      node.bounds.left,
      node.bounds.top,
      node.bounds.right,
      node.bounds.bottom,
    ],
  }));
  return {
    display,
    nodes,
    fingerprint: sha256(JSON.stringify(structural)),
  };
}

export function countExactUiText(xml, expectedText) {
  const expected = String(expectedText ?? '');
  if (!expected) return 0;
  let count = 0;
  const nodePattern = /<node\b([^>]*)\/?>(?:<\/node>)?/gu;
  let nodeMatch;
  while ((nodeMatch = nodePattern.exec(String(xml ?? ''))) !== null) {
    const text = nodeMatch[1].match(/\btext="([^"]*)"/u)?.[1];
    if (text !== undefined && decodeXmlAttribute(text) === expected) count += 1;
  }
  return count;
}

export function countExactProjectHeaderText(xml, expectedText, display, profile) {
  const expected = String(expectedText ?? '');
  const header = profile?.ui?.projectHeader;
  if (!expected || !header || !display?.width || !display?.height) return 0;
  let count = 0;
  const nodePattern = /<node\b([^>]*)\/?>(?:<\/node>)?/gu;
  let nodeMatch;
  while ((nodeMatch = nodePattern.exec(String(xml ?? ''))) !== null) {
    const attributes = {};
    const attributePattern = /([\w-]+)="([^"]*)"/gu;
    let attributeMatch;
    while ((attributeMatch = attributePattern.exec(nodeMatch[1])) !== null) {
      attributes[attributeMatch[1]] = decodeXmlAttribute(attributeMatch[2]);
    }
    if (
      attributes.text !== expected
      || attributes.package !== CHATGPT_PACKAGE
      || !header.allowedClassNames.includes(attributes.class ?? '')
      || attributes.enabled === 'false'
    ) {
      continue;
    }
    const bounds = parseBounds(attributes.bounds);
    if (!bounds) continue;
    const topRatio = bounds.top / display.height;
    const bottomRatio = bounds.bottom / display.height;
    const leftRatio = bounds.left / display.width;
    const rightRatio = bounds.right / display.width;
    const heightRatio = bounds.height / display.height;
    if (
      topRatio >= header.minTopRatio
      && topRatio <= header.maxTopRatio
      && bottomRatio <= header.maxBottomRatio
      && leftRatio <= header.maxLeftRatio
      && rightRatio <= header.maxRightRatio
      && heightRatio >= header.minHeightRatio
      && heightRatio <= header.maxHeightRatio
    ) {
      count += 1;
    }
  }
  return count;
}

function enabledClickableNodes(snapshot) {
  return snapshot.nodes.filter((node) => (
    node.clickable && node.enabled && node.packageName === CHATGPT_PACKAGE
  ));
}

export function findSingleEditor(snapshot) {
  const editors = snapshot.nodes.filter((node) => (
    node.className === 'android.widget.EditText'
    && node.packageName === CHATGPT_PACKAGE
    && node.enabled
  ));
  if (editors.length > 1) {
    throw new BridgeError(
      'E_UI_EDITOR_AMBIGUOUS',
      'FIND_EDITOR',
      'More than one enabled editor is visible',
    );
  }
  return editors[0] ?? null;
}

function assertEdgeControl(target, snapshot, profile, state, missingCode) {
  const widthRatio = target.bounds.width / snapshot.display.width;
  if (
    target.bounds.right < snapshot.display.width * 0.85
    || widthRatio < profile.ui.edgeControlMinWidthRatio
    || widthRatio > profile.ui.edgeControlMaxWidthRatio
  ) {
    throw new BridgeError(missingCode, state, 'The right-edge control did not match the profile');
  }
}

export function findSendTarget(snapshot, profile, options = {}) {
  const editor = findSingleEditor(snapshot);
  if (!editor || !editor.textPresent) return null;
  const maximumGap = snapshot.display.height * profile.ui.controlRowGapRatio;
  const minimumControlHeight = snapshot.display.height * profile.ui.actionRowMinHeightRatio;
  const maximumControlHeight = snapshot.display.height * profile.ui.actionRowMaxHeightRatio;
  const candidates = enabledClickableNodes(snapshot)
    .filter((node) => node !== editor)
    .filter((node) => node.bounds.top >= editor.bounds.bottom)
    .filter((node) => node.bounds.top - editor.bounds.bottom <= maximumGap)
    .filter((node) => (
      node.bounds.height >= minimumControlHeight
      && node.bounds.height <= maximumControlHeight
    ));
  const rows = new Map();
  for (const node of candidates) {
    const key = `${node.bounds.top}:${node.bounds.bottom}`;
    const row = rows.get(key) ?? [];
    row.push(node);
    rows.set(key, row);
  }
  const allowedRowSizes = options.allowedRowSizes
    ?? profile.ui.populatedComposerControlRowSizes
    ?? [profile.ui.populatedComposerControlRowSize];
  const controlWidthMatches = (node) => {
    const widthRatio = node.bounds.width / snapshot.display.width;
    return (
      widthRatio >= profile.ui.edgeControlMinWidthRatio
      && widthRatio <= profile.ui.edgeControlMaxWidthRatio
    );
  };
  const rowMatchesComposerLayout = (row) => {
    if (!allowedRowSizes.includes(row.length) || !row.every(controlWidthMatches)) {
      return false;
    }
    const sorted = [...row].sort((left, right) => left.bounds.left - right.bounds.left);
    const [leftAnchor, ...rightCluster] = sorted;
    if (
      !leftAnchor
      || rightCluster.length < 2
      || leftAnchor.bounds.left > snapshot.display.width * profile.ui.composerLeftAnchorMaxRatio
      || rightCluster[0].bounds.left - leftAnchor.bounds.right
        < snapshot.display.width * profile.ui.composerClusterGapMinRatio
      || rightCluster.at(-1).bounds.right
        < snapshot.display.width * profile.ui.composerRightEdgeMinRatio
    ) {
      return false;
    }
    const maximumClusterGap = (
      snapshot.display.width * profile.ui.composerClusterContiguityRatio
    );
    const contiguous = rightCluster.slice(1).every((node, index) => {
      const previousRight = rightCluster[index].bounds.right;
      return (
        node.bounds.left >= previousRight
        && node.bounds.left - previousRight <= maximumClusterGap
      );
    });
    if (!contiguous) return false;

    const projectLayout = options.projectLayout;
    if (!projectLayout) return true;
    if (
      sorted.length !== projectLayout.rowSize
      || rightCluster.length !== projectLayout.rightClusterSize
    ) {
      return false;
    }
    const firstRightLeftRatio = rightCluster[0].bounds.left / snapshot.display.width;
    const targetRightRatio = rightCluster.at(-1).bounds.right / snapshot.display.width;
    const projectControlWidthsMatch = rightCluster.every((node) => {
      const widthRatio = node.bounds.width / snapshot.display.width;
      return (
        widthRatio >= projectLayout.rightControlMinWidthRatio
        && widthRatio <= projectLayout.rightControlMaxWidthRatio
      );
    });
    const projectMaximumGap = snapshot.display.width * projectLayout.rightControlGapMaxRatio;
    const projectClusterIsContiguous = rightCluster.slice(1).every((node, index) => {
      const previousRight = rightCluster[index].bounds.right;
      return (
        node.bounds.left >= previousRight
        && node.bounds.left - previousRight <= projectMaximumGap
      );
    });
    return (
      firstRightLeftRatio >= projectLayout.rightClusterFirstLeftMinRatio
      && firstRightLeftRatio <= projectLayout.rightClusterFirstLeftMaxRatio
      && targetRightRatio >= projectLayout.targetRightMinRatio
      && targetRightRatio <= projectLayout.targetRightMaxRatio
      && projectControlWidthsMatch
      && projectClusterIsContiguous
    );
  };
  const matchingRows = [...rows.values()]
    .filter(rowMatchesComposerLayout)
    .map((row) => row.sort((left, right) => left.bounds.right - right.bounds.right));
  if (matchingRows.length !== 1) {
    throw new BridgeError(
      'E_UI_SEND_ROW_AMBIGUOUS',
      'PREPARE_SEND',
      'The composer control row did not match the profile',
    );
  }
  const target = matchingRows[0].at(-1);
  assertEdgeControl(target, snapshot, profile, 'PREPARE_SEND', 'E_UI_SEND_NOT_FOUND');
  return target;
}

export function findActionRows(snapshot, profile) {
  const editor = findSingleEditor(snapshot);
  if (!editor) return [];
  const groups = new Map();
  for (const node of enabledClickableNodes(snapshot)) {
    if (node === editor || node.bounds.bottom >= editor.bounds.top) continue;
    const key = `${node.bounds.top}:${node.bounds.bottom}`;
    const group = groups.get(key) ?? [];
    group.push(node);
    groups.set(key, group);
  }
  const minimumHeight = snapshot.display.height * profile.ui.actionRowMinHeightRatio;
  const maximumHeight = snapshot.display.height * profile.ui.actionRowMaxHeightRatio;
  const maximumWidth = snapshot.display.width * profile.ui.actionRowMaxWidthRatio;
  const rows = [];
  for (const group of groups.values()) {
    if (group.length !== profile.ui.actionRowSize) continue;
    const sorted = [...group].sort((left, right) => left.bounds.left - right.bounds.left);
    const height = sorted[0].bounds.height;
    const contiguous = sorted.every((node, index) => (
      index === 0 || node.bounds.left - sorted[index - 1].bounds.right <= 12
    ));
    const totalWidth = sorted.at(-1).bounds.right - sorted[0].bounds.left;
    if (
      height >= minimumHeight
      && height <= maximumHeight
      && sorted[0].bounds.left <= 20
      && totalWidth <= maximumWidth
      && contiguous
    ) {
      rows.push(sorted);
    }
  }
  return rows.sort((left, right) => left[0].bounds.top - right[0].bounds.top);
}

export function findReadAloudTarget(snapshot, profile) {
  const rows = findActionRows(snapshot, profile);
  if (rows.length === 0) return null;
  if (rows.length !== 1) {
    throw new BridgeError(
      'E_UI_ACTION_ROW_AMBIGUOUS',
      'FIND_READ_ALOUD',
      'More than one response action row matches the profile',
    );
  }
  return rows[0][profile.ui.readAloudIndex] ?? null;
}

export function findVoiceTarget(snapshot, profile) {
  const editor = findSingleEditor(snapshot);
  if (!editor || editor.textPresent) return null;
  const candidates = enabledClickableNodes(snapshot)
    .filter((node) => (
      node.bounds.top === editor.bounds.top
      && node.bounds.bottom === editor.bounds.bottom
    ))
    .sort((left, right) => left.bounds.right - right.bounds.right);
  if (
    candidates.length !== profile.ui.emptyComposerRowSize
    || candidates.filter((node) => node === editor).length !== 1
  ) {
    throw new BridgeError(
      'E_UI_VOICE_ROW_AMBIGUOUS',
      'FIND_VOICE',
      'The empty composer row did not match the Voice profile',
    );
  }

  const maximumGap = snapshot.display.width * profile.ui.composerClusterContiguityRatio;
  const leftAnchors = candidates.filter((node) => (
    node !== editor
    && node.bounds.right <= editor.bounds.left
    && editor.bounds.left - node.bounds.right <= maximumGap
  ));
  if (leftAnchors.length !== 1) {
    throw new BridgeError(
      'E_UI_VOICE_ROW_AMBIGUOUS',
      'FIND_VOICE',
      'The empty composer row did not have one adjacent left anchor',
    );
  }

  const controls = candidates
    .filter((node) => node !== editor && node !== leftAnchors[0])
    .sort((left, right) => left.bounds.left - right.bounds.left);
  if (
    controls.length !== 2
    || controls[1].bounds.left < controls[0].bounds.right
    || controls[1].bounds.left - controls[0].bounds.right > maximumGap
  ) {
    throw new BridgeError(
      'E_UI_VOICE_ROW_AMBIGUOUS',
      'FIND_VOICE',
      'The empty composer Voice controls were not one contiguous pair',
    );
  }

  const allowedLayouts = profile.ui.emptyComposerVoiceLayouts
    ?? ['controls_right_of_editor'];
  const matchingLayouts = [];
  if (
    allowedLayouts.includes('controls_right_of_editor')
    && controls.every((node) => node.bounds.left >= editor.bounds.right)
    && controls[0].bounds.left - editor.bounds.right <= maximumGap
  ) {
    matchingLayouts.push('controls_right_of_editor');
  }
  if (
    allowedLayouts.includes('controls_overlaid_in_editor')
    && controls.every((node) => (
      node.bounds.left >= editor.bounds.left
      && node.bounds.right <= editor.bounds.right
    ))
    && controls[0].bounds.left >= editor.bounds.left + editor.bounds.width * 0.5
    && editor.bounds.right - controls.at(-1).bounds.right <= maximumGap
  ) {
    matchingLayouts.push('controls_overlaid_in_editor');
  }
  if (matchingLayouts.length !== 1) {
    throw new BridgeError(
      'E_UI_VOICE_ROW_AMBIGUOUS',
      'FIND_VOICE',
      'The empty composer Voice layout did not match exactly one profiled variant',
    );
  }

  const target = controls.at(-1);
  assertEdgeControl(target, snapshot, profile, 'FIND_VOICE', 'E_UI_VOICE_NOT_FOUND');
  return target;
}

export function parseAudioEvidence(output, packageName = CHATGPT_PACKAGE) {
  const packagePiids = new Set();
  const events = new Map();
  const states = new Map();
  for (const line of String(output ?? '').split(/\r?\n/u)) {
    const created = line.match(/new player piid:(\d+).*?package:([^\s]+)/u);
    if (created && created[2] === packageName) packagePiids.add(Number(created[1]));
    const event = line.match(/player piid:(\d+) event:(started|stopped)/u);
    if (event) {
      const piid = Number(event[1]);
      const list = events.get(piid) ?? [];
      list.push(event[2]);
      events.set(piid, list);
    }
    const released = line.match(/releasing player piid:(\d+)/u);
    if (released) {
      const piid = Number(released[1]);
      const list = events.get(piid) ?? [];
      list.push('released');
      events.set(piid, list);
    }
    const current = line.match(/AudioPlaybackConfiguration piid:(\d+).*?state:(started|stopped|idle)/u);
    if (current) states.set(Number(current[1]), current[2]);
  }
  return [...packagePiids].map((piid) => ({
    piid,
    events: events.get(piid) ?? [],
    state: states.get(piid) ?? null,
  }));
}

export function findNewAudioPlayer(audioPlayers, baselinePiids) {
  const candidates = audioPlayers.filter((player) => (
    !baselinePiids.has(player.piid) && player.events.includes('started')
  ));
  if (candidates.length > 1) {
    throw new BridgeError(
      'E_AUDIO_PLAYER_AMBIGUOUS',
      'WAIT_AUDIO_START',
      'More than one new ChatGPT audio player started',
    );
  }
  return candidates[0] ?? null;
}

export function audioPlayerEnded(player) {
  if (!player?.events.includes('started')) return false;
  const startIndex = player.events.indexOf('started');
  const endIndex = player.events.findIndex((event, index) => (
    index > startIndex && (event === 'stopped' || event === 'released')
  ));
  return endIndex > startIndex || player.state === 'stopped';
}

export function parseRecordAudioRunning(output) {
  return /RECORD_AUDIO:.*\(running\)/iu.test(String(output ?? ''));
}

export function validateSuccessReceipt(receipt) {
  const required = [
    receipt.evidence.foregroundPackageVerified,
    receipt.evidence.draftVerifiedWithoutReadingText,
    receipt.evidence.sendSelectorUnique,
    receipt.evidence.sendConfirmed,
    receipt.evidence.sendUiTransitionObserved,
    receipt.evidence.assistantResponseReady,
    receipt.evidence.responseUiTransitionObserved,
    receipt.evidence.readAloudSelectorUnique,
    receipt.evidence.readAloudTapIssued,
    receipt.evidence.audioStartObserved,
    receipt.evidence.audioEndObserved,
    receipt.evidence.voiceSelectorUnique,
    receipt.evidence.voiceTapIssued,
    receipt.evidence.recordAudioBaselineIdle,
    receipt.evidence.recordAudioRunning,
    receipt.evidence.uiArtifactCleanupAttempted,
    receipt.evidence.uiArtifactCleanupSucceeded,
  ];
  if (
    required.some((value) => value !== true)
    || receipt.evidence.audioOwnerPackage !== CHATGPT_PACKAGE
    || receipt.evidence.coordinateFallback !== false
    || (
      receipt.route?.mode === 'project_conversation'
      && (
        receipt.evidence.conversationRouteVerified !== true
        || receipt.evidence.projectTitleMatched !== true
      )
    )
  ) {
    throw new BridgeError(
      'E_RECEIPT_INCOMPLETE',
      'SUCCESS',
      'The success receipt does not contain the full evidence chain',
    );
  }
  return true;
}

export function resolveAdbPath(env = process.env) {
  const explicit = String(env.CHATGPT_BRIDGE_ADB_PATH ?? '').trim();
  if (explicit) return explicit;
  const roots = [env.ANDROID_HOME, env.ANDROID_SDK_ROOT]
    .map((value) => String(value ?? '').trim())
    .filter(Boolean);
  const localAppData = String(env.LOCALAPPDATA ?? '').trim();
  if (localAppData) roots.push(path.join(localAppData, 'Android', 'Sdk'));
  for (const root of roots) {
    const candidate = path.join(root, 'platform-tools', 'adb.exe');
    if (existsSync(candidate)) return candidate;
  }
  return 'adb';
}

function posixShellQuote(value) {
  return `'${String(value).replace(/'/gu, `'"'"'`)}'`;
}

export function buildActionSendRemoteCommand(prompt) {
  const encoded = Buffer.from(safePrompt(prompt), 'utf8').toString('base64');
  const script = [
    `payload="$(printf %s ${posixShellQuote(encoded)} | base64 -d)"`,
    'test -n "$payload"',
    `exec am start -W -a android.intent.action.SEND -t text/plain -p ${CHATGPT_PACKAGE} --es android.intent.extra.TEXT "$payload"`,
  ].join(' && ');
  return `sh -c ${posixShellQuote(script)}`;
}

export function buildConversationDraftRemoteCommand(conversationId, prompt) {
  const id = safeConversationId(conversationId);
  const url = new URL(`https://chatgpt.com/c/${id}`);
  url.searchParams.set('q', safePrompt(prompt));
  const encodedUrl = Buffer.from(url.toString(), 'utf8').toString('base64');
  const script = [
    `url="$(printf %s ${posixShellQuote(encodedUrl)} | base64 -d)"`,
    'test -n "$url"',
    `exec am start -W -a android.intent.action.VIEW -d "$url" -p ${CHATGPT_PACKAGE}`,
  ].join(' && ');
  return `sh -c ${posixShellQuote(script)}`;
}

function makeTransport({ adbPath, serial, execFile = execFileSync }) {
  function run(args, timeoutMs = 30_000, withSerial = true) {
    const fullArgs = withSerial && serial ? ['-s', serial, ...args] : args;
    try {
      return String(execFile(adbPath, fullArgs, {
        encoding: 'utf8',
        maxBuffer: MAX_ADB_BUFFER,
        timeout: timeoutMs,
        windowsHide: true,
      }) ?? '').trim();
    } catch (error) {
      throw new BridgeError(
        'E_DEVICE_ADB_COMMAND',
        'ADB_COMMAND',
        `ADB command failed with exit status ${error?.status ?? 'unknown'}`,
      );
    }
  }
  return {
    run,
    host(args, timeoutMs) { return run(args, timeoutMs, false); },
    shell(args, timeoutMs) { return run(['shell', ...args], timeoutMs, true); },
    remote(command, timeoutMs) { return run(['shell', command], timeoutMs, true); },
  };
}

function makeReceipt({ runId, dryRun, now }) {
  return {
    schemaVersion: 1,
    runId,
    result: 'failed',
    failedState: null,
    errorCode: null,
    errorMessage: null,
    dryRun,
    device: {
      serial: null,
      adbState: null,
      model: null,
      display: null,
      locale: null,
      inputMethodPackage: null,
      unlocked: false,
      awake: false,
    },
    app: {
      package: CHATGPT_PACKAGE,
      versionCode: null,
      versionName: null,
      profileId: null,
      profileHash: null,
    },
    route: {
      mode: 'new_chat',
      conversationIdHash: null,
      projectTitleHash: null,
    },
    timing: {
      startedAtUtc: isoNow(now),
      assistantReadyAtUtc: null,
      audioStartedAtUtc: null,
      audioEndedAtUtc: null,
      recordAudioRunningAtUtc: null,
      completedAtUtc: null,
    },
    transitions: [],
    evidence: {
      foregroundPackageVerified: false,
      conversationRouteVerified: false,
      projectTitleMatched: false,
      draftVerifiedWithoutReadingText: false,
      sendSelectorUnique: false,
      sendConfirmed: false,
      sendUiTransitionObserved: false,
      assistantResponseReady: false,
      responseUiTransitionObserved: false,
      readAloudSelectorUnique: false,
      readAloudTapIssued: false,
      audioOwnerPackage: null,
      audioStartObserved: false,
      audioEndObserved: false,
      voiceSelectorUnique: false,
      voiceTapIssued: false,
      recordAudioBaselineIdle: false,
      recordAudioRunning: false,
      coordinateFallback: false,
      selectorKind: 'version_profile_structural_geometry',
      uiArtifactCleanupAttempted: false,
      uiArtifactCleanupSucceeded: true,
      uiArtifactCleanupFailurePath: null,
      failureForceStopAttempted: false,
      failureForceStopSucceeded: null,
      failureForceStopReason: null,
      failureForceStopContextStatus: null,
      failureForceStopSkippedReason: null,
      leavesVoiceActiveOnSuccess: true,
      draftUiFingerprint: null,
      sentUiFingerprint: null,
      responseUiFingerprint: null,
    },
  };
}

function profileDigest(profile) {
  return sha256(JSON.stringify(profile));
}

function clickTarget(transport, target) {
  transport.shell([
    'input',
    'touchscreen',
    'tap',
    String(target.bounds.centerX),
    String(target.bounds.centerY),
  ]);
}

async function waitFor({ timeoutMs, pollMs, probe, timeoutError, sleep, now }) {
  const deadline = now() + timeoutMs;
  while (now() <= deadline) {
    const value = await probe();
    if (value) return value;
    await sleep(pollMs);
  }
  throw timeoutError;
}

function defaultSleep(milliseconds) {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}

export async function runBridge(options = {}) {
  const now = options.now ?? Date.now;
  const sleep = options.sleep ?? defaultSleep;
  const runId = options.runId ?? randomUUID();
  const dryRun = options.execute !== true;
  const receipt = makeReceipt({ runId, dryRun, now });
  const timeouts = {
    foregroundMs: asPositiveInteger(options.foregroundMs, DEFAULT_TIMEOUTS.foregroundMs),
    draftMs: asPositiveInteger(options.draftMs, DEFAULT_TIMEOUTS.draftMs),
    sendMs: asPositiveInteger(options.sendMs, DEFAULT_TIMEOUTS.sendMs),
    responseMs: asPositiveInteger(options.responseMs, DEFAULT_TIMEOUTS.responseMs),
    audioStartMs: asPositiveInteger(options.audioStartMs, DEFAULT_TIMEOUTS.audioStartMs),
    audioEndMs: asPositiveInteger(options.audioEndMs, DEFAULT_TIMEOUTS.audioEndMs),
    recordAudioMs: asPositiveInteger(options.recordAudioMs, DEFAULT_TIMEOUTS.recordAudioMs),
    pollMs: asPositiveInteger(options.pollMs, DEFAULT_TIMEOUTS.pollMs),
  };
  let transport;
  let liveStarted = false;
  let currentState = 'INIT';
  let dumpSequence = 0;
  let bridgeAudioActive = false;
  let bridgeRecordingObserved = false;
  let readAloudTapIssued = false;
  let voiceTapIssued = false;
  let projectRoute = false;
  let conversationId = null;
  let projectTitle = null;

  function transition(state) {
    currentState = state;
    receipt.transitions.push({ state, atUtc: isoNow(now) });
  }

  function assertInteractiveContext(state = currentState) {
    const topPackage = parseTopPackage(
      transport.shell(['dumpsys', 'activity', 'activities']),
    );
    const unlocked = parseKeyguardUnlocked(
      transport.shell(['dumpsys', 'window', 'policy']),
    );
    const awake = parseDeviceAwake(transport.shell(['dumpsys', 'power']));
    if (topPackage !== CHATGPT_PACKAGE || !unlocked || !awake) {
      throw new BridgeError(
        'E_DEVICE_CONTEXT_CHANGED',
        state,
        'Foreground app, lock state, or screen state changed before a UI action',
      );
    }
  }

  function assertProjectContext(snapshot, state = currentState) {
    if (!projectRoute) return;
    if (snapshot.projectHeaderMatchCount !== 1) {
      throw new BridgeError(
        'E_UI_PROJECT_CONTEXT_MISMATCH',
        state,
        'The expected ChatGPT Project title was not unique in the profiled header region',
      );
    }
  }

  function dumpUi(profile, expectedText = null) {
    dumpSequence += 1;
    const remotePath = `/data/local/tmp/chatgpt_bridge_${runId.replace(/[^a-zA-Z0-9_-]/gu, '')}_${dumpSequence}.xml`;
    receipt.evidence.uiArtifactCleanupAttempted = true;
    let xml;
    let primaryError = null;
    try {
      transport.shell(['uiautomator', 'dump', remotePath], 20_000);
      xml = transport.run(['exec-out', 'cat', remotePath], 20_000);
    } catch (error) {
      primaryError = error;
    } finally {
      let cleaned = false;
      for (let attempt = 0; attempt < 3 && !cleaned; attempt += 1) {
        try {
          transport.shell(['rm', '-f', remotePath], 10_000);
          transport.remote(`test ! -e ${posixShellQuote(remotePath)}`, 10_000);
          cleaned = true;
        } catch {
          // Retry a bounded number of times, then expose only the non-sensitive path.
        }
      }
      if (!cleaned) {
        receipt.evidence.uiArtifactCleanupSucceeded = false;
        receipt.evidence.uiArtifactCleanupFailurePath = remotePath;
      }
    }
    if (!receipt.evidence.uiArtifactCleanupSucceeded) {
      throw new BridgeError(
        'E_CLEANUP_FAILED',
        currentState,
        'Temporary UI hierarchy cleanup failed',
      );
    }
    if (primaryError) {
      throw new BridgeError('E_UI_DUMP_FAILED', currentState, 'UI hierarchy could not be read');
    }
    const snapshot = parseUiSnapshot(xml, profile.display);
    if (expectedText !== null) {
      snapshot.projectHeaderMatchCount = countExactProjectHeaderText(
        xml,
        expectedText,
        profile.display,
        profile,
      );
    }
    return snapshot;
  }

  try {
    transition('VALIDATE_INPUT');
    const prompt = dryRun ? null : safePrompt(options.prompt);
    const hasConversationId = options.conversationId !== undefined;
    const hasProjectTitle = options.projectTitle !== undefined;
    if (hasConversationId !== hasProjectTitle) {
      throw new BridgeError(
        'E_INPUT_PROJECT_ROUTE_INCOMPLETE',
        currentState,
        'Project routing requires both conversation ID and Project title',
      );
    }
    projectRoute = hasConversationId;
    if (projectRoute) {
      conversationId = safeConversationId(options.conversationId);
      projectTitle = safeProjectTitle(options.projectTitle);
      receipt.route.mode = 'project_conversation';
      receipt.route.conversationIdHash = sha256(conversationId);
      receipt.route.projectTitleHash = sha256(projectTitle);
      receipt.evidence.selectorKind = 'version_profile_geometry_and_project_header';
    }
    const adbPath = options.adbPath ?? resolveAdbPath(options.env ?? process.env);

    transition('SELECT_DEVICE');
    const hostTransport = makeTransport({ adbPath, serial: null, execFile: options.execFile });
    const devices = parseAdbDevices(hostTransport.host(['devices']));
    const serial = selectDevice(devices, options.serial);
    receipt.device.serial = serial;
    receipt.device.adbState = 'device';
    transport = makeTransport({ adbPath, serial, execFile: options.execFile });
    transport.run(['get-state']);

    transition('CHECK_UNLOCKED');
    const policy = transport.shell(['dumpsys', 'window', 'policy']);
    const power = transport.shell(['dumpsys', 'power']);
    receipt.device.unlocked = parseKeyguardUnlocked(policy);
    receipt.device.awake = parseDeviceAwake(power);
    if (!receipt.device.unlocked) {
      throw new BridgeError('E_DEVICE_LOCKED', currentState, 'The device is locked');
    }
    if (!receipt.device.awake) {
      throw new BridgeError('E_DEVICE_ASLEEP', currentState, 'The device screen is not awake');
    }

    transition('RESOLVE_APP_PROFILE');
    const packageInfo = parsePackageInfo(
      transport.shell(['dumpsys', 'package', CHATGPT_PACKAGE]),
    );
    const display = parseDisplaySize(transport.shell(['wm', 'size']));
    const deviceModel = transport.shell(['getprop', 'ro.product.model']);
    const locale = transport.shell(['getprop', 'persist.sys.locale'])
      || transport.shell(['getprop', 'ro.product.locale']);
    const inputMethod = transport.shell(['settings', 'get', 'secure', 'default_input_method']);
    const facts = {
      packageName: CHATGPT_PACKAGE,
      ...packageInfo,
      display,
      deviceModel,
      locale,
      inputMethod,
    };
    const profile = resolveProfile(facts, options.profiles ?? SUPPORTED_PROFILES);
    if (
      projectRoute
      && (
        !profile.ui.populatedProjectComposerControlRowSizes
        || !profile.ui.projectComposerLayout
        || !profile.ui.projectHeader
      )
    ) {
      throw new BridgeError(
        'E_PROFILE_PROJECT_ROUTE_UNSUPPORTED',
        currentState,
        'The exact ChatGPT UI profile does not include a Project composer layout',
      );
    }
    receipt.device.model = deviceModel;
    receipt.device.display = display;
    receipt.device.locale = locale;
    receipt.device.inputMethodPackage = inputMethod.split('/')[0];
    receipt.app.versionCode = packageInfo.versionCode;
    receipt.app.versionName = packageInfo.versionName;
    receipt.app.profileId = profile.id;
    receipt.app.profileHash = profileDigest(profile);

    if (dryRun) {
      transition('DRY_RUN_COMPLETE');
      receipt.result = 'dry_run';
      receipt.timing.completedAtUtc = isoNow(now);
      return receipt;
    }

    transition(projectRoute ? 'LAUNCH_PROJECT_CONVERSATION_DRAFT' : 'LAUNCH_PREFILLED_SEND');
    liveStarted = true;
    const launchOutput = transport.remote(
      projectRoute
        ? buildConversationDraftRemoteCommand(conversationId, prompt)
        : buildActionSendRemoteCommand(prompt),
      30_000,
    );
    if (/\b(?:Error|Exception):/iu.test(launchOutput)) {
      throw new BridgeError(
        'E_LAUNCH_FAILED',
        currentState,
        projectRoute
          ? 'ChatGPT rejected the conversation draft route'
          : 'ChatGPT rejected ACTION_SEND',
      );
    }
    await waitFor({
      timeoutMs: timeouts.foregroundMs,
      pollMs: timeouts.pollMs,
      sleep,
      now,
      probe: async () => {
        const top = parseTopPackage(transport.shell(['dumpsys', 'activity', 'activities']));
        return top === CHATGPT_PACKAGE;
      },
      timeoutError: new BridgeError(
        'E_DEVICE_FOREGROUND_TIMEOUT',
        currentState,
        'ChatGPT did not become the foreground app',
      ),
    });
    receipt.evidence.foregroundPackageVerified = true;

    transition('PREPARE_SEND');
    const draft = await waitFor({
      timeoutMs: timeouts.draftMs,
      pollMs: timeouts.pollMs,
      sleep,
      now,
      probe: async () => {
        const snapshot = dumpUi(profile, projectRoute ? projectTitle : null);
        assertProjectContext(snapshot, currentState);
        const editor = findSingleEditor(snapshot);
        if (!editor?.textPresent) return null;
        const actionRows = findActionRows(snapshot, profile);
        if (!projectRoute && actionRows.length !== 0) {
          throw new BridgeError(
            'E_UI_BASELINE_DIRTY',
            currentState,
            'ACTION_SEND did not open a clean composer surface',
          );
        }
        const sendTarget = findSendTarget(
          snapshot,
          profile,
          projectRoute
            ? {
              allowedRowSizes: profile.ui.populatedProjectComposerControlRowSizes,
              projectLayout: profile.ui.projectComposerLayout,
            }
            : undefined,
        );
        if (!sendTarget) return null;
        return { snapshot, sendTarget };
      },
      timeoutError: new BridgeError(
        'E_SEND_DRAFT_TIMEOUT',
        currentState,
        'A non-empty draft with a unique Send control did not appear',
      ),
    });
    if (projectRoute) {
      receipt.evidence.conversationRouteVerified = true;
      receipt.evidence.projectTitleMatched = true;
    }
    receipt.evidence.draftVerifiedWithoutReadingText = true;
    receipt.evidence.sendSelectorUnique = true;
    receipt.evidence.draftUiFingerprint = draft.snapshot.fingerprint;
    assertInteractiveContext('PREPARE_SEND');
    clickTarget(transport, draft.sendTarget);

    transition('WAIT_USER_SENT');
    const sentSnapshot = await waitFor({
      timeoutMs: timeouts.sendMs,
      pollMs: timeouts.pollMs,
      sleep,
      now,
      probe: async () => {
        const snapshot = dumpUi(profile, projectRoute ? projectTitle : null);
        assertProjectContext(snapshot, currentState);
        const editor = findSingleEditor(snapshot);
        return editor && !editor.textPresent ? snapshot : null;
      },
      timeoutError: new BridgeError(
        'E_SEND_UNCONFIRMED',
        currentState,
        'The composer did not become empty after tapping Send',
      ),
    });
    receipt.evidence.sendConfirmed = true;
    receipt.evidence.sentUiFingerprint = sentSnapshot.fingerprint;
    receipt.evidence.sendUiTransitionObserved = (
      sentSnapshot.fingerprint !== draft.snapshot.fingerprint
    );
    if (!receipt.evidence.sendUiTransitionObserved) {
      throw new BridgeError(
        'E_SEND_STATE_UNCHANGED',
        currentState,
        'The UI structure did not change after tapping Send',
      );
    }

    transition('WAIT_ASSISTANT_RESPONSE');
    const response = await waitFor({
      timeoutMs: timeouts.responseMs,
      pollMs: timeouts.pollMs,
      sleep,
      now,
      probe: async () => {
        const snapshot = dumpUi(profile, projectRoute ? projectTitle : null);
        assertProjectContext(snapshot, currentState);
        const editor = findSingleEditor(snapshot);
        if (!editor || editor.textPresent) return null;
        const readAloudTarget = findReadAloudTarget(snapshot, profile);
        return readAloudTarget ? { snapshot, readAloudTarget } : null;
      },
      timeoutError: new BridgeError(
        'E_RESPONSE_TIMEOUT',
        currentState,
        'A unique completed-response action row did not appear',
      ),
    });
    receipt.evidence.assistantResponseReady = true;
    receipt.evidence.readAloudSelectorUnique = true;
    receipt.evidence.responseUiFingerprint = response.snapshot.fingerprint;
    receipt.evidence.responseUiTransitionObserved = (
      response.snapshot.fingerprint !== sentSnapshot.fingerprint
    );
    if (!receipt.evidence.responseUiTransitionObserved) {
      throw new BridgeError(
        'E_RESPONSE_STATE_UNCHANGED',
        currentState,
        'The response-ready UI structure did not change from the sent state',
      );
    }
    receipt.timing.assistantReadyAtUtc = isoNow(now);

    transition('TAP_READ_ALOUD');
    const audioBaseline = parseAudioEvidence(
      transport.shell(['dumpsys', 'audio']),
      CHATGPT_PACKAGE,
    );
    const baselinePiids = new Set(audioBaseline.map((player) => player.piid));
    assertInteractiveContext('TAP_READ_ALOUD');
    readAloudTapIssued = true;
    receipt.evidence.readAloudTapIssued = true;
    clickTarget(transport, response.readAloudTarget);

    transition('WAIT_AUDIO_START');
    const audioPlayer = await waitFor({
      timeoutMs: timeouts.audioStartMs,
      pollMs: Math.min(timeouts.pollMs, 300),
      sleep,
      now,
      probe: async () => findNewAudioPlayer(
        parseAudioEvidence(transport.shell(['dumpsys', 'audio']), CHATGPT_PACKAGE),
        baselinePiids,
      ),
      timeoutError: new BridgeError(
        'E_AUDIO_START_TIMEOUT',
        currentState,
        'No new ChatGPT audio player start was observed',
      ),
    });
    receipt.evidence.audioOwnerPackage = CHATGPT_PACKAGE;
    receipt.evidence.audioStartObserved = true;
    bridgeAudioActive = true;
    receipt.timing.audioStartedAtUtc = isoNow(now);

    transition('WAIT_AUDIO_END');
    await waitFor({
      timeoutMs: timeouts.audioEndMs,
      pollMs: Math.min(timeouts.pollMs, 400),
      sleep,
      now,
      probe: async () => {
        const players = parseAudioEvidence(
          transport.shell(['dumpsys', 'audio']),
          CHATGPT_PACKAGE,
        );
        return audioPlayerEnded(players.find((player) => player.piid === audioPlayer.piid));
      },
      timeoutError: new BridgeError(
        'E_AUDIO_END_TIMEOUT',
        currentState,
        'The ChatGPT audio player did not stop after it started',
      ),
    });
    receipt.evidence.audioEndObserved = true;
    bridgeAudioActive = false;
    receipt.timing.audioEndedAtUtc = isoNow(now);

    transition('FIND_VOICE');
    const voiceSnapshot = dumpUi(profile, projectRoute ? projectTitle : null);
    assertProjectContext(voiceSnapshot, currentState);
    if (!findReadAloudTarget(voiceSnapshot, profile)) {
      throw new BridgeError(
        'E_RESPONSE_STATE_LOST',
        currentState,
        'The completed response action row disappeared before Voice handoff',
      );
    }
    const voiceTarget = findVoiceTarget(voiceSnapshot, profile);
    if (!voiceTarget) {
      throw new BridgeError('E_UI_VOICE_NOT_FOUND', currentState, 'Voice control not found');
    }
    receipt.evidence.voiceSelectorUnique = true;
    const recordAudioBaseline = transport.shell([
      'cmd', 'appops', 'get', CHATGPT_PACKAGE, 'RECORD_AUDIO',
    ]);
    if (parseRecordAudioRunning(recordAudioBaseline)) {
      throw new BridgeError(
        'E_RECORD_AUDIO_BASELINE_RUNNING',
        currentState,
        'ChatGPT was already recording before this Voice handoff',
      );
    }
    receipt.evidence.recordAudioBaselineIdle = true;
    assertInteractiveContext('TAP_VOICE');
    transition('TAP_VOICE');
    voiceTapIssued = true;
    receipt.evidence.voiceTapIssued = true;
    clickTarget(transport, voiceTarget);

    transition('WAIT_RECORD_AUDIO_RUNNING');
    await waitFor({
      timeoutMs: timeouts.recordAudioMs,
      pollMs: Math.min(timeouts.pollMs, 350),
      sleep,
      now,
      probe: async () => parseRecordAudioRunning(
        transport.shell(['cmd', 'appops', 'get', CHATGPT_PACKAGE, 'RECORD_AUDIO']),
      ),
      timeoutError: new BridgeError(
        'E_RECORD_AUDIO_NOT_RUNNING',
        currentState,
        'Voice did not place RECORD_AUDIO into running state',
      ),
    });
    bridgeRecordingObserved = true;
    assertInteractiveContext('WAIT_RECORD_AUDIO_RUNNING');
    receipt.evidence.recordAudioRunning = true;
    receipt.timing.recordAudioRunningAtUtc = isoNow(now);

    transition('SUCCESS');
    validateSuccessReceipt(receipt);
    receipt.result = 'success';
    receipt.timing.completedAtUtc = isoNow(now);
    return receipt;
  } catch (error) {
    const failure = error instanceof BridgeError
      ? error
      : new BridgeError('E_INTERNAL', currentState, 'Unexpected bridge failure');
    receipt.result = 'failed';
    receipt.failedState = failure.state || currentState;
    receipt.errorCode = failure.code;
    receipt.errorMessage = failure.message;
    const readAloudMayBeActive = readAloudTapIssued && !receipt.evidence.audioEndObserved;
    const voiceMayBeActive = voiceTapIssued;
    if (
      liveStarted
      && transport
      && (
        bridgeAudioActive
        || bridgeRecordingObserved
        || readAloudMayBeActive
        || voiceMayBeActive
      )
    ) {
      let cleanupContextStatus = 'context_check_failed';
      try {
        const topPackage = parseTopPackage(
          transport.shell(['dumpsys', 'activity', 'activities']),
        );
        const stillUnlocked = parseKeyguardUnlocked(
          transport.shell(['dumpsys', 'window', 'policy']),
        );
        const stillAwake = parseDeviceAwake(transport.shell(['dumpsys', 'power']));
        cleanupContextStatus = (
          topPackage === CHATGPT_PACKAGE && stillUnlocked && stillAwake
        )
          ? 'verified_same'
          : 'context_changed';
      } catch {
        // A media tap has already been issued, so diagnostics must not block cleanup.
      }
      receipt.evidence.failureForceStopContextStatus = cleanupContextStatus;
      const baseReason = bridgeAudioActive
        ? 'bridge_audio_still_active'
        : bridgeRecordingObserved
          ? 'bridge_recording_observed'
          : voiceTapIssued
            ? 'voice_tap_issued_unconfirmed'
            : 'read_aloud_tap_issued_unconfirmed';
      receipt.evidence.failureForceStopReason = cleanupContextStatus === 'verified_same'
        ? baseReason
        : `${baseReason}_${cleanupContextStatus}`;
      receipt.evidence.failureForceStopAttempted = true;
      try {
        transport.shell(['am', 'force-stop', CHATGPT_PACKAGE]);
        receipt.evidence.failureForceStopSucceeded = true;
      } catch {
        receipt.evidence.failureForceStopSucceeded = false;
      }
    } else if (liveStarted && transport) {
      receipt.evidence.failureForceStopSkippedReason = 'no_attributable_media_tap_or_activity';
    }
    receipt.timing.completedAtUtc = isoNow(now);
    return receipt;
  }
}

export function parseCliArguments(argv) {
  const options = { execute: false };
  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    const next = () => {
      index += 1;
      if (index >= argv.length) {
        throw new BridgeError('E_INPUT_INVALID', 'VALIDATE_INPUT', `Missing value for ${argument}`);
      }
      return argv[index];
    };
    switch (argument) {
      case '--execute': options.execute = true; break;
      case '--dry-run': options.execute = false; break;
      case '--serial': options.serial = next(); break;
      case '--adb': options.adbPath = next(); break;
      case '--prompt': options.prompt = next(); break;
      case '--conversation-id': options.conversationId = next(); break;
      case '--project-title': options.projectTitle = next(); break;
      case '--response-timeout-ms': options.responseMs = next(); break;
      case '--audio-end-timeout-ms': options.audioEndMs = next(); break;
      default:
        throw new BridgeError(
          'E_INPUT_INVALID',
          'VALIDATE_INPUT',
          `Unsupported argument: ${argument}`,
        );
    }
  }
  return options;
}

async function main() {
  let receipt;
  try {
    receipt = await runBridge(parseCliArguments(process.argv.slice(2)));
  } catch (error) {
    const failure = error instanceof BridgeError
      ? error
      : new BridgeError('E_INTERNAL', 'INIT', 'Unexpected bridge failure');
    receipt = {
      schemaVersion: 1,
      result: 'failed',
      failedState: failure.state,
      errorCode: failure.code,
      errorMessage: failure.message,
    };
  }
  process.stdout.write(`${JSON.stringify(receipt, null, 2)}\n`);
  if (receipt.result === 'failed') process.exitCode = 1;
}

const invokedPath = process.argv[1] ? path.resolve(process.argv[1]) : null;
if (invokedPath === fileURLToPath(import.meta.url)) {
  await main();
}
