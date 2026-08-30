import assert from 'node:assert/strict';
import test from 'node:test';
import {
  BridgeError,
  SUPPORTED_PROFILES,
  audioPlayerEnded,
  buildActionSendRemoteCommand,
  buildConversationDraftRemoteCommand,
  countExactProjectHeaderText,
  countExactUiText,
  findActionRows,
  findNewAudioPlayer,
  findReadAloudTarget,
  findSendTarget,
  findVoiceTarget,
  parseAdbDevices,
  parseAudioEvidence,
  parseCliArguments,
  parseDeviceAwake,
  parseDisplaySize,
  parseKeyguardUnlocked,
  parsePackageInfo,
  parseRecordAudioRunning,
  parseTopPackage,
  parseUiSnapshot,
  resolveProfile,
  runBridge,
  selectDevice,
  validateSuccessReceipt,
} from './chatgpt_sleep_bridge.mjs';

const profile = SUPPORTED_PROFILES[0];
const profile230 = SUPPORTED_PROFILES[1];
const display = { width: 1080, height: 2340 };

function node(attributes) {
  const values = {
    index: '0',
    text: '',
    resourceId: '',
    className: 'android.view.View',
    packageName: 'com.openai.chatgpt',
    contentDescription: '',
    clickable: 'true',
    enabled: 'true',
    focusable: 'true',
    bounds: '[0,0][1,1]',
    ...attributes,
  };
  return `<node index="${values.index}" text="${values.text}" resource-id="${values.resourceId}" class="${values.className}" package="${values.packageName}" content-desc="${values.contentDescription}" clickable="${values.clickable}" enabled="${values.enabled}" focusable="${values.focusable}" bounds="${values.bounds}" />`;
}

function hierarchy(nodes) {
  return `<?xml version="1.0" encoding="UTF-8"?><hierarchy rotation="0">${nodes.join('')}</hierarchy>`;
}

function withProjectTitle(xml, title = '林埃') {
  return xml.replace(
    '</hierarchy>',
    `${node({ text: title, bounds: '[42,120][240,220]' })}</hierarchy>`,
  );
}

function withProjectTitleInMessage(xml, title = '林埃') {
  return xml.replace(
    '</hierarchy>',
    `${node({ text: title, bounds: '[84,760][420,860]' })}</hierarchy>`,
  );
}

function withDuplicateProjectHeaders(xml, title = '林埃') {
  return withProjectTitle(withProjectTitle(xml, title), title);
}

function draftXml({
  offsetY = 0,
  decoy = false,
  duplicateRow = false,
  tallEditor = false,
  longPrompt = false,
} = {}) {
  const bounds = (left, top, right, bottom) => (
    `[${left},${top + offsetY}][${right},${bottom + offsetY}]`
  );
  const nodes = [
    node({
      text: 'private prompt that must never survive parsing',
      className: 'android.widget.EditText',
      bounds: longPrompt
        ? bounds(84, 530, 996, 1216)
        : bounds(84, tallEditor ? 1866 : 1938, 996, 2082),
    }),
    node({ bounds: longPrompt ? bounds(36, 1228, 180, 1372) : bounds(36, 2094, 180, 2238) }),
    ...(longPrompt ? [node({ bounds: bounds(636, 1228, 768, 1372) })] : []),
    node({ bounds: longPrompt ? bounds(768, 1228, 900, 1372) : bounds(768, 2094, 900, 2238) }),
    node({ bounds: longPrompt ? bounds(900, 1228, 1044, 1372) : bounds(900, 2094, 1044, 2238) }),
  ];
  if (decoy) {
    nodes.push(node({
      bounds: longPrompt ? bounds(492, 1228, 624, 1372) : bounds(600, 2094, 732, 2238),
    }));
  }
  if (duplicateRow) {
    nodes.push(
      node({ bounds: bounds(36, 2110, 180, 2254) }),
      node({ bounds: bounds(768, 2110, 900, 2254) }),
      node({ bounds: bounds(900, 2110, 1044, 2254) }),
    );
  }
  return hierarchy(nodes);
}

function projectDraftXml({ extraControl = false, malformed = null, duplicateRow = false } = {}) {
  const rightControls = malformed === 'internal_gap'
    ? [
      '[468,2094][606,2238]',
      '[614,2094][758,2238]',
      '[758,2094][902,2238]',
      '[902,2094][1046,2238]',
    ]
    : malformed === 'wrong_width'
      ? [
        '[468,2094][606,2238]',
        '[606,2094][760,2238]',
        '[760,2094][894,2238]',
        '[894,2094][1038,2238]',
      ]
      : [
        '[468,2094][606,2238]',
        '[606,2094][750,2238]',
        '[750,2094][894,2238]',
        '[894,2094][1038,2238]',
      ];
  const rowTop = malformed === 'overlap_editor' ? 2070 : 2094;
  const rowBottom = malformed === 'overlap_editor' ? 2214 : 2238;
  const nodes = [
    node({
      text: 'private Project prompt that must never survive parsing',
      className: 'android.widget.EditText',
      bounds: '[84,1362][996,2082]',
    }),
    node({ bounds: `[36,${rowTop}][180,${rowBottom}]` }),
    ...rightControls.map((bounds) => node({
      bounds: malformed === 'overlap_editor'
        ? bounds.replaceAll('2094', '2070').replaceAll('2238', '2214')
        : bounds,
    })),
  ];
  if (extraControl) nodes.push(node({ bounds: '[312,2094][456,2238]' }));
  if (duplicateRow) {
    nodes.push(
      node({ bounds: '[36,2110][180,2254]' }),
      node({ bounds: '[468,2110][606,2254]' }),
      node({ bounds: '[606,2110][750,2254]' }),
      node({ bounds: '[750,2110][894,2254]' }),
      node({ bounds: '[894,2110][1038,2254]' }),
    );
  }
  return hierarchy(nodes);
}

function responseXml({
  duplicateActionRow = false,
  offsetY = 0,
  voiceDecoy = false,
  voiceOverlap = false,
} = {}) {
  const shiftedBounds = (left, top, right, bottom) => (
    `[${left},${top + offsetY}][${right},${bottom + offsetY}]`
  );
  const nodes = [
    node({
      className: 'android.widget.EditText',
      bounds: shiftedBounds(246, 2094, 702, 2238),
    }),
    node({ bounds: shiftedBounds(102, 2094, 246, 2238) }),
    node({ bounds: shiftedBounds(702, 2094, 834, 2238) }),
    node({ bounds: voiceOverlap
      ? shiftedBounds(826, 2094, 970, 2238)
      : shiftedBounds(834, 2094, 978, 2238) }),
  ];
  if (voiceDecoy) {
    nodes.push(node({ bounds: shiftedBounds(978, 2094, 1074, 2238) }));
  }
  const addActionRow = (top) => {
    const shiftedTop = top + offsetY;
    const bottoms = shiftedTop + 144;
    const bounds = [
      `[6,${shiftedTop}][114,${bottoms}]`,
      `[114,${shiftedTop}][222,${bottoms}]`,
      `[222,${shiftedTop}][330,${bottoms}]`,
      `[330,${shiftedTop}][438,${bottoms}]`,
      `[438,${shiftedTop}][546,${bottoms}]`,
      `[546,${shiftedTop}][690,${bottoms}]`,
    ];
    nodes.push(...bounds.map((value) => node({ bounds: value })));
  };
  addActionRow(800);
  if (duplicateActionRow) addActionRow(500);
  return hierarchy(nodes);
}

function projectResponseXml({ offsetY = 0, malformed = null } = {}) {
  const shiftedBounds = (left, top, right, bottom) => (
    `[${left},${top + offsetY}][${right},${bottom + offsetY}]`
  );
  const firstControl = malformed === 'gap'
    ? shiftedBounds(684, 2094, 816, 2238)
    : shiftedBounds(684, 2094, 828, 2238);
  const secondControl = malformed === 'gap'
    ? shiftedBounds(840, 2094, 972, 2238)
    : malformed === 'overlap'
      ? shiftedBounds(820, 2094, 964, 2238)
      : shiftedBounds(828, 2094, malformed === 'outside_editor' ? 990 : 972, 2238);
  const nodes = [
    node({
      className: 'android.widget.EditText',
      bounds: shiftedBounds(246, 2094, 978, 2238),
    }),
    node({ bounds: shiftedBounds(102, 2094, 246, 2238) }),
    node({ bounds: firstControl }),
    node({ bounds: secondControl }),
  ];
  if (malformed === 'extra_control') {
    nodes.push(node({ bounds: shiftedBounds(552, 2094, 672, 2238) }));
  }
  const actionBounds = [
    [6, 800, 114, 944],
    [114, 800, 222, 944],
    [222, 800, 330, 944],
    [330, 800, 438, 944],
    [438, 800, 546, 944],
    [546, 800, 690, 944],
  ];
  nodes.push(...actionBounds.map(([left, top, right, bottom]) => node({
    bounds: shiftedBounds(left, top, right, bottom),
  })));
  return hierarchy(nodes);
}

function sentXml() {
  return hierarchy([
    node({
      className: 'android.widget.EditText',
      bounds: '[246,2094][702,2238]',
    }),
    node({ bounds: '[102,2094][246,2238]' }),
    node({ bounds: '[702,2094][834,2238]' }),
    node({ bounds: '[834,2094][978,2238]' }),
  ]);
}

function makeLiveFake({
  locked = false,
  unknownProfile = false,
  cleanupFails = false,
  projectMode = false,
  projectTitle = '林埃',
  projectTitlePlacement = 'header',
  audioStartNeverObserved = false,
  recordAudioNeverRuns = false,
  contextChangesAfterMediaTap = null,
} = {}) {
  const calls = [];
  const baseSnapshots = projectMode
    ? [projectDraftXml(), sentXml(), projectResponseXml(), projectResponseXml()]
    : [draftXml(), sentXml(), responseXml(), responseXml()];
  const uiSnapshots = baseSnapshots.map((xml) => {
    if (!projectMode) return xml;
    if (projectTitlePlacement === 'message') {
      return withProjectTitleInMessage(xml, projectTitle);
    }
    if (projectTitlePlacement === 'duplicate_headers') {
      return withDuplicateProjectHeaders(xml, projectTitle);
    }
    return withProjectTitle(xml, projectTitle);
  });
  let audioReadCount = 0;
  let appOpsReadCount = 0;
  let mediaTapIssued = false;
  const oldAudio = [
    'new player piid:151 uid/pid:1/2 package:com.openai.chatgpt type:android.media.AudioTrack',
    'player piid:151 event:started',
    'player piid:151 event:stopped',
  ].join('\n');
  const startedAudio = [
    oldAudio,
    'AudioPlaybackConfiguration piid:159 deviceIds:[3] type:android.media.AudioTrack u/pid:1/2 state:started',
    'new player piid:159 uid/pid:1/2 package:com.openai.chatgpt type:android.media.AudioTrack',
    'player piid:159 event:started',
  ].join('\n');
  const stoppedAudio = `${startedAudio}\nplayer piid:159 event:stopped`;

  const execFile = (_file, args) => {
    calls.push([...args]);
    const command = args[0] === '-s' ? args.slice(2) : args;
    const key = command.join(' ');
    if (key === 'devices') return 'List of devices attached\nA\tdevice\n';
    if (key === 'get-state') return 'device';
    if (key === 'shell dumpsys window policy') {
      return locked ? 'showing=true\nmIsShowing=true' : 'showing=false\nmIsShowing=false';
    }
    if (key === 'shell dumpsys power') return 'mWakefulness=Awake';
    if (key === 'shell dumpsys package com.openai.chatgpt') {
      if (unknownProfile) return 'versionCode=2622320 minSdk=32\nversionName=1.2026.999';
      return projectMode
        ? 'versionCode=2623032 minSdk=32\nversionName=1.2026.230'
        : 'versionCode=2622320 minSdk=32\nversionName=1.2026.223';
    }
    if (key === 'shell wm size') return 'Physical size: 1080x2340';
    if (key === 'shell getprop ro.product.model') return 'SM-S9110';
    if (key === 'shell getprop persist.sys.locale') return 'zh-Hans-CN';
    if (key === 'shell settings get secure default_input_method') {
      return 'com.tencent.wetype/.plugin.hld.WxHldService';
    }
    if (key === 'shell dumpsys activity activities') {
      if (contextChangesAfterMediaTap && mediaTapIssued) {
        return 'topResumedActivity=ActivityRecord{x u0 com.example.other/.MainActivity t2}';
      }
      return 'topResumedActivity=ActivityRecord{x u0 com.openai.chatgpt/.MainActivity t1}';
    }
    if (command[0] === 'shell' && command.length === 2 && command[1].includes('am start -W')) {
      return 'Status: ok';
    }
    if (command[0] === 'shell' && command[1] === 'uiautomator' && command[2] === 'dump') {
      return 'UI hierchary dumped';
    }
    if (command[0] === 'exec-out' && command[1] === 'cat') {
      const snapshot = uiSnapshots.shift();
      if (!snapshot) throw new Error('No scripted UI snapshot left');
      return snapshot;
    }
    if (command[0] === 'shell' && command[1] === 'rm') {
      if (cleanupFails) throw new Error('scripted cleanup failure');
      return '';
    }
    if (command[0] === 'shell' && command.length === 2 && command[1].startsWith('test ! -e ')) {
      if (cleanupFails) throw new Error('scripted cleanup verification failure');
      return '';
    }
    if (command[0] === 'shell' && command[1] === 'input') {
      const coordinate = command.slice(-2).join(':');
      if (
        (contextChangesAfterMediaTap === 'read_aloud' && coordinate === '384:872')
        || (
          contextChangesAfterMediaTap === 'voice'
          && (coordinate === '900:2166' || coordinate === '906:2166')
        )
      ) {
        mediaTapIssued = true;
      }
      return '';
    }
    if (key === 'shell dumpsys audio') {
      audioReadCount += 1;
      if (audioReadCount === 1) return oldAudio;
      if (audioStartNeverObserved) return oldAudio;
      if (audioReadCount === 2) return startedAudio;
      return stoppedAudio;
    }
    if (key === 'shell cmd appops get com.openai.chatgpt RECORD_AUDIO') {
      appOpsReadCount += 1;
      if (recordAudioNeverRuns) {
        return 'RECORD_AUDIO: allow; time=+1m; duration=0';
      }
      return appOpsReadCount === 1
        ? 'RECORD_AUDIO: allow; time=+1m; duration=0'
        : 'RECORD_AUDIO: allow; time=+50ms (running)';
    }
    if (key === 'shell am force-stop com.openai.chatgpt') return '';
    throw new Error(`Unexpected fake ADB command: ${key}`);
  };
  return { calls, execFile };
}

function advancingClock() {
  let current = Date.UTC(2026, 7, 30, 0, 0, 0);
  return () => {
    current += 1;
    return current;
  };
}

test('ADB selection requires one online device or the exact requested serial', () => {
  const devices = parseAdbDevices(
    'List of devices attached\nA\tdevice product:x\nB\toffline\n',
  );
  assert.deepEqual(devices, [
    { serial: 'A', state: 'device' },
    { serial: 'B', state: 'offline' },
  ]);
  assert.equal(selectDevice(devices), 'A');
  assert.equal(selectDevice(devices, 'A'), 'A');
  assert.throws(
    () => selectDevice([...devices, { serial: 'C', state: 'device' }]),
    (error) => error instanceof BridgeError && error.code === 'E_DEVICE_AMBIGUOUS',
  );
});

test('preflight parsers are explicit and fail closed', () => {
  assert.deepEqual(
    parsePackageInfo('versionCode=2622320 minSdk=32\nversionName=1.2026.223'),
    { versionCode: 2622320, versionName: '1.2026.223' },
  );
  assert.deepEqual(parseDisplaySize('Physical size: 1080x2340'), display);
  assert.equal(parseKeyguardUnlocked('showing=false\nmIsShowing=false'), true);
  assert.equal(parseKeyguardUnlocked('showing=true\nmIsShowing=false'), false);
  assert.equal(parseDeviceAwake('mWakefulness=Awake'), true);
  assert.equal(
    parseTopPackage('topResumedActivity=ActivityRecord{x u0 com.openai.chatgpt/.MainActivity t1}'),
    'com.openai.chatgpt',
  );
});

test('profile resolution binds app, model, display, locale, and keyboard', () => {
  const facts = {
    packageName: 'com.openai.chatgpt',
    versionCode: 2622320,
    versionName: '1.2026.223',
    deviceModel: 'SM-S9110',
    display,
    locale: 'zh-Hans-CN',
    inputMethod: 'com.tencent.wetype/.plugin.hld.WxHldService',
  };
  assert.equal(resolveProfile(facts).id, profile.id);
  assert.equal(
    resolveProfile({
      ...facts,
      versionCode: 2623032,
      versionName: '1.2026.230',
    }).id,
    'chatgpt-1.2026.230-sm-s9110-zh-wetype-v1',
  );
  assert.throws(
    () => resolveProfile({ ...facts, versionName: '1.2026.999' }),
    (error) => error instanceof BridgeError && error.code === 'E_PROFILE_UNKNOWN',
  );
});

test('UI parser discards text and content descriptions while retaining structure', () => {
  const snapshot = parseUiSnapshot(draftXml(), display);
  assert.equal(snapshot.nodes.length, 4);
  assert.equal(snapshot.nodes[0].textPresent, true);
  assert.equal('text' in snapshot.nodes[0], false);
  assert.equal(JSON.stringify(snapshot).includes('private prompt'), false);
  assert.match(snapshot.fingerprint, /^[a-f0-9]{64}$/u);
  const projectXml = withProjectTitle(draftXml());
  assert.equal(countExactUiText(projectXml, '林埃'), 1);
  assert.equal(countExactUiText(projectXml, '不存在'), 0);
  assert.equal(
    countExactProjectHeaderText(projectXml, '林埃', display, profile230),
    1,
  );
  assert.equal(
    countExactProjectHeaderText(
      withProjectTitleInMessage(draftXml()),
      '林埃',
      display,
      profile230,
    ),
    0,
  );
  assert.equal(
    countExactProjectHeaderText(
      withDuplicateProjectHeaders(draftXml()),
      '林埃',
      display,
      profile230,
    ),
    2,
  );
  assert.equal(
    countExactProjectHeaderText(projectXml, '林埃', display, profile),
    0,
  );
});

test('Send target is derived from the populated editor control row', () => {
  const target = findSendTarget(parseUiSnapshot(draftXml(), display), profile);
  assert.deepEqual(
    { x: target.bounds.centerX, y: target.bounds.centerY },
    { x: 972, y: 2166 },
  );
  const tallEditor = findSendTarget(
    parseUiSnapshot(draftXml({ tallEditor: true }), display),
    profile,
  );
  assert.deepEqual(
    { x: tallEditor.bounds.centerX, y: tallEditor.bounds.centerY },
    { x: 972, y: 2166 },
  );
  const shifted = findSendTarget(
    parseUiSnapshot(draftXml({ offsetY: -866 }), display),
    profile,
  );
  assert.deepEqual(
    { x: shifted.bounds.centerX, y: shifted.bounds.centerY },
    { x: 972, y: 1300 },
  );
  assert.throws(
    () => findSendTarget(parseUiSnapshot(draftXml({ decoy: true }), display), profile),
    (error) => error instanceof BridgeError && error.code === 'E_UI_SEND_ROW_AMBIGUOUS',
  );
  const longPrompt = findSendTarget(
    parseUiSnapshot(draftXml({ longPrompt: true }), display),
    profile230,
  );
  assert.deepEqual(
    { x: longPrompt.bounds.centerX, y: longPrompt.bounds.centerY },
    { x: 972, y: 1300 },
  );
  assert.throws(
    () => findSendTarget(
      parseUiSnapshot(draftXml({ decoy: true }), display),
      profile230,
    ),
    (error) => error instanceof BridgeError && error.code === 'E_UI_SEND_ROW_AMBIGUOUS',
  );
  assert.throws(
    () => findSendTarget(
      parseUiSnapshot(draftXml({ longPrompt: true, decoy: true }), display),
      profile230,
    ),
    (error) => error instanceof BridgeError && error.code === 'E_UI_SEND_ROW_AMBIGUOUS',
  );
  assert.throws(
    () => findSendTarget(
      parseUiSnapshot(draftXml({ longPrompt: true }), display),
      profile,
    ),
    (error) => error instanceof BridgeError && error.code === 'E_UI_SEND_ROW_AMBIGUOUS',
  );
  assert.throws(
    () => findSendTarget(
      parseUiSnapshot(draftXml({ duplicateRow: true }), display),
      profile230,
    ),
    (error) => error instanceof BridgeError && error.code === 'E_UI_SEND_ROW_AMBIGUOUS',
  );
  const projectTarget = findSendTarget(
    parseUiSnapshot(projectDraftXml(), display),
    profile230,
    {
      allowedRowSizes: profile230.ui.populatedProjectComposerControlRowSizes,
      projectLayout: profile230.ui.projectComposerLayout,
    },
  );
  assert.deepEqual(
    { x: projectTarget.bounds.centerX, y: projectTarget.bounds.centerY },
    { x: 966, y: 2166 },
  );
  assert.throws(
    () => findSendTarget(parseUiSnapshot(projectDraftXml(), display), profile230),
    (error) => error instanceof BridgeError && error.code === 'E_UI_SEND_ROW_AMBIGUOUS',
  );
  assert.throws(
    () => findSendTarget(
      parseUiSnapshot(projectDraftXml({ extraControl: true }), display),
      profile230,
      {
        allowedRowSizes: profile230.ui.populatedProjectComposerControlRowSizes,
        projectLayout: profile230.ui.projectComposerLayout,
      },
    ),
    (error) => error instanceof BridgeError && error.code === 'E_UI_SEND_ROW_AMBIGUOUS',
  );
  for (const malformed of ['internal_gap', 'wrong_width', 'overlap_editor']) {
    assert.throws(
      () => findSendTarget(
        parseUiSnapshot(projectDraftXml({ malformed }), display),
        profile230,
        {
          allowedRowSizes: profile230.ui.populatedProjectComposerControlRowSizes,
          projectLayout: profile230.ui.projectComposerLayout,
        },
      ),
      (error) => error instanceof BridgeError && error.code === 'E_UI_SEND_ROW_AMBIGUOUS',
    );
  }
  assert.throws(
    () => findSendTarget(
      parseUiSnapshot(projectDraftXml({ duplicateRow: true }), display),
      profile230,
      {
        allowedRowSizes: profile230.ui.populatedProjectComposerControlRowSizes,
        projectLayout: profile230.ui.projectComposerLayout,
      },
    ),
    (error) => error instanceof BridgeError && error.code === 'E_UI_SEND_ROW_AMBIGUOUS',
  );
});

test('Read Aloud and Voice targets are structurally unique', () => {
  const snapshot = parseUiSnapshot(responseXml(), display);
  assert.equal(findActionRows(snapshot, profile).length, 1);
  const readAloud = findReadAloudTarget(snapshot, profile);
  const voice = findVoiceTarget(snapshot, profile);
  assert.deepEqual(
    { x: readAloud.bounds.centerX, y: readAloud.bounds.centerY },
    { x: 384, y: 872 },
  );
  assert.deepEqual(
    { x: voice.bounds.centerX, y: voice.bounds.centerY },
    { x: 906, y: 2166 },
  );
  const shifted = parseUiSnapshot(responseXml({ offsetY: -300 }), display);
  assert.deepEqual(
    {
      read: findReadAloudTarget(shifted, profile).bounds.centerY,
      voice: findVoiceTarget(shifted, profile).bounds.centerY,
    },
    { read: 572, voice: 1866 },
  );
  assert.throws(
    () => findVoiceTarget(
      parseUiSnapshot(responseXml({ voiceDecoy: true }), display),
      profile,
    ),
    (error) => error instanceof BridgeError && error.code === 'E_UI_VOICE_ROW_AMBIGUOUS',
  );
  assert.throws(
    () => findVoiceTarget(
      parseUiSnapshot(responseXml({ voiceOverlap: true }), display),
      profile,
    ),
    (error) => error instanceof BridgeError && error.code === 'E_UI_VOICE_ROW_AMBIGUOUS',
  );
});

test('project chat overlaid Voice controls require the exact profiled layout', () => {
  const snapshot = parseUiSnapshot(projectResponseXml(), display);
  const voice = findVoiceTarget(snapshot, profile230);
  assert.deepEqual(
    {
      left: voice.bounds.left,
      right: voice.bounds.right,
      x: voice.bounds.centerX,
      y: voice.bounds.centerY,
    },
    { left: 828, right: 972, x: 900, y: 2166 },
  );
  const shifted = findVoiceTarget(
    parseUiSnapshot(projectResponseXml({ offsetY: -300 }), display),
    profile230,
  );
  assert.deepEqual(
    { x: shifted.bounds.centerX, y: shifted.bounds.centerY },
    { x: 900, y: 1866 },
  );
  assert.throws(
    () => findVoiceTarget(snapshot, profile),
    (error) => error instanceof BridgeError && error.code === 'E_UI_VOICE_ROW_AMBIGUOUS',
  );
  for (const malformed of ['gap', 'overlap', 'outside_editor', 'extra_control']) {
    assert.throws(
      () => findVoiceTarget(
        parseUiSnapshot(projectResponseXml({ malformed }), display),
        profile230,
      ),
      (error) => error instanceof BridgeError && error.code === 'E_UI_VOICE_ROW_AMBIGUOUS',
    );
  }
});

test('duplicate response action rows are rejected', () => {
  const snapshot = parseUiSnapshot(responseXml({ duplicateActionRow: true }), display);
  assert.throws(
    () => findReadAloudTarget(snapshot, profile),
    (error) => error instanceof BridgeError && error.code === 'E_UI_ACTION_ROW_AMBIGUOUS',
  );
});

test('audio evidence requires a new package-owned player to start and then stop', () => {
  const output = [
    'AudioPlaybackConfiguration piid:159 deviceIds:[3] type:android.media.AudioTrack u/pid:1/2 state:stopped',
    'new player piid:159 uid/pid:1/2 package:com.openai.chatgpt type:android.media.AudioTrack',
    'player piid:159 event:started',
    'player piid:159 event:stopped',
  ].join('\n');
  const players = parseAudioEvidence(output);
  const player = findNewAudioPlayer(players, new Set([151]));
  assert.equal(player.piid, 159);
  assert.equal(audioPlayerEnded(player), true);
  assert.equal(findNewAudioPlayer(players, new Set([159])), null);
});

test('RECORD_AUDIO success requires running, not merely allowed', () => {
  assert.equal(parseRecordAudioRunning('RECORD_AUDIO: allow; time=+1s (running)'), true);
  assert.equal(parseRecordAudioRunning('RECORD_AUDIO: allow; time=+1s; duration=0'), false);
});

test('ACTION_SEND shell command base64-wraps hostile prompt characters', () => {
  const prompt = '中文 sleep \' " ; $(id) `id` & done';
  const command = buildActionSendRemoteCommand(prompt);
  assert.equal(command.includes(prompt), false);
  assert.match(command, /^sh -c /u);
  const candidates = command.match(/[A-Za-z0-9+/=]{20,}/gu) ?? [];
  assert.equal(
    candidates.some((candidate) => Buffer.from(candidate, 'base64').toString('utf8') === prompt),
    true,
  );
});

test('conversation draft route base64-wraps the full private URL and validates the ID', () => {
  const conversationId = '123e4567-e89b-42d3-a456-426614174000';
  const prompt = '中文 private \' " ; $(id) `id` & done';
  const command = buildConversationDraftRemoteCommand(conversationId, prompt);
  const expectedUrl = new URL(`https://chatgpt.com/c/${conversationId}`);
  expectedUrl.searchParams.set('q', prompt);
  assert.equal(command.includes(prompt), false);
  assert.equal(command.includes('https://chatgpt.com/c/'), false);
  assert.equal(command.includes(expectedUrl.search.slice(1)), false);
  assert.match(command, /^sh -c /u);
  const candidates = command.match(/[A-Za-z0-9+/=]{20,}/gu) ?? [];
  assert.equal(
    candidates.some((candidate) => (
      Buffer.from(candidate, 'base64').toString('utf8') === expectedUrl.toString()
    )),
    true,
  );
  assert.throws(
    () => buildConversationDraftRemoteCommand('../wrong', prompt),
    (error) => (
      error instanceof BridgeError && error.code === 'E_INPUT_CONVERSATION_ID_INVALID'
    ),
  );
});

test('success receipt validator rejects any missing evidence', () => {
  const evidence = {
    foregroundPackageVerified: true,
    draftVerifiedWithoutReadingText: true,
    sendSelectorUnique: true,
    sendConfirmed: true,
    sendUiTransitionObserved: true,
    assistantResponseReady: true,
    responseUiTransitionObserved: true,
    readAloudSelectorUnique: true,
    readAloudTapIssued: true,
    audioOwnerPackage: 'com.openai.chatgpt',
    audioStartObserved: true,
    audioEndObserved: true,
    voiceSelectorUnique: true,
    voiceTapIssued: true,
    recordAudioBaselineIdle: true,
    recordAudioRunning: true,
    uiArtifactCleanupAttempted: true,
    uiArtifactCleanupSucceeded: true,
    coordinateFallback: false,
  };
  assert.equal(validateSuccessReceipt({ evidence }), true);
  assert.throws(
    () => validateSuccessReceipt({ evidence: { ...evidence, audioEndObserved: false } }),
    (error) => error instanceof BridgeError && error.code === 'E_RECEIPT_INCOMPLETE',
  );
});

test('CLI defaults to DryRun and requires explicit --execute for live mutation', () => {
  assert.deepEqual(parseCliArguments(['--serial', 'A']), { execute: false, serial: 'A' });
  assert.deepEqual(
    parseCliArguments(['--execute', '--serial', 'A', '--prompt', 'sleep']),
    { execute: true, serial: 'A', prompt: 'sleep' },
  );
  assert.deepEqual(
    parseCliArguments([
      '--execute',
      '--prompt', 'sleep',
      '--conversation-id', '123e4567-e89b-42d3-a456-426614174000',
      '--project-title', '林埃',
    ]),
    {
      execute: true,
      prompt: 'sleep',
      conversationId: '123e4567-e89b-42d3-a456-426614174000',
      projectTitle: '林埃',
    },
  );
});

test('DryRun performs preflight only and has no UI or app mutation', async () => {
  const calls = [];
  const fakeExec = (_file, args) => {
    calls.push([...args]);
    const command = args[0] === '-s' ? args.slice(2) : args;
    const key = command.join(' ');
    if (key === 'devices') return 'List of devices attached\nA\tdevice\n';
    if (key === 'get-state') return 'device';
    if (key === 'shell dumpsys window policy') return 'showing=false\nmIsShowing=false';
    if (key === 'shell dumpsys power') return 'mWakefulness=Awake';
    if (key === 'shell dumpsys package com.openai.chatgpt') {
      return 'versionCode=2622320 minSdk=32\nversionName=1.2026.223';
    }
    if (key === 'shell wm size') return 'Physical size: 1080x2340';
    if (key === 'shell getprop ro.product.model') return 'SM-S9110';
    if (key === 'shell getprop persist.sys.locale') return 'zh-Hans-CN';
    if (key === 'shell settings get secure default_input_method') {
      return 'com.tencent.wetype/.plugin.hld.WxHldService';
    }
    throw new Error(`Unexpected fake ADB command: ${key}`);
  };
  const receipt = await runBridge({
    adbPath: 'fake-adb',
    serial: 'A',
    execFile: fakeExec,
  });
  assert.equal(receipt.result, 'dry_run');
  assert.equal(receipt.app.profileId, profile.id);
  assert.equal(
    calls.some((args) => args.includes('am') || args.includes('input') || args.includes('uiautomator')),
    false,
  );
});

test('scripted live run preserves ordering, provenance, and prompt privacy', async () => {
  const fake = makeLiveFake();
  const prompt = '私密睡眠提示 ; $(id) \' "';
  const receipt = await runBridge({
    adbPath: 'fake-adb',
    serial: 'A',
    execute: true,
    prompt,
    execFile: fake.execFile,
    sleep: async () => {},
  });
  assert.equal(receipt.result, 'success');
  assert.equal(validateSuccessReceipt(receipt), true);
  assert.equal(JSON.stringify(receipt).includes(prompt), false);
  assert.equal(receipt.evidence.recordAudioBaselineIdle, true);
  assert.notEqual(
    receipt.evidence.draftUiFingerprint,
    receipt.evidence.sentUiFingerprint,
  );
  assert.notEqual(
    receipt.evidence.sentUiFingerprint,
    receipt.evidence.responseUiFingerprint,
  );
  const tapCalls = fake.calls
    .filter((args) => args.includes('input'))
    .map((args) => args.slice(-2).map(Number));
  assert.deepEqual(tapCalls, [
    [972, 2166],
    [384, 872],
    [906, 2166],
  ]);
  const flattened = fake.calls.map((args) => args.join(' '));
  const readTapIndex = flattened.findIndex((value) => value.endsWith('input touchscreen tap 384 872'));
  const audioIndex = flattened.findIndex((value, index) => (
    index > readTapIndex && value.endsWith('shell dumpsys audio')
  ));
  const voiceTapIndex = flattened.findIndex((value) => value.endsWith('input touchscreen tap 906 2166'));
  assert.ok(readTapIndex >= 0 && audioIndex > readTapIndex && voiceTapIndex > audioIndex);
});

test('scripted Project conversation run requires the exact visible Project title', async () => {
  const conversationId = '123e4567-e89b-42d3-a456-426614174000';
  const projectTitle = '林埃';
  const prompt = '私密项目睡眠提示';
  const fake = makeLiveFake({ projectMode: true, projectTitle });
  const receipt = await runBridge({
    adbPath: 'fake-adb',
    serial: 'A',
    execute: true,
    prompt,
    conversationId,
    projectTitle,
    execFile: fake.execFile,
    sleep: async () => {},
  });
  assert.equal(receipt.result, 'success');
  assert.equal(receipt.route.mode, 'project_conversation');
  assert.match(receipt.route.conversationIdHash, /^[a-f0-9]{64}$/u);
  assert.match(receipt.route.projectTitleHash, /^[a-f0-9]{64}$/u);
  assert.equal(receipt.evidence.conversationRouteVerified, true);
  assert.equal(receipt.evidence.projectTitleMatched, true);
  assert.equal(JSON.stringify(receipt).includes(conversationId), false);
  assert.equal(JSON.stringify(receipt).includes(projectTitle), false);
  assert.equal(JSON.stringify(receipt).includes(prompt), false);
  const launch = fake.calls.find((args) => (
    args.join(' ').includes('android.intent.action.VIEW')
  ))?.join(' ') ?? '';
  assert.equal(launch.includes('android.intent.action.VIEW'), true);
  assert.equal(launch.includes('android.intent.action.SEND'), false);
  assert.equal(launch.includes('https://chatgpt.com/c/'), false);
  assert.equal(launch.includes(conversationId), false);
  assert.equal(launch.includes(prompt), false);
  const expectedUrl = new URL(`https://chatgpt.com/c/${conversationId}`);
  expectedUrl.searchParams.set('q', prompt);
  const launchCandidates = launch.match(/[A-Za-z0-9+/=]{20,}/gu) ?? [];
  assert.equal(
    launchCandidates.some((candidate) => (
      Buffer.from(candidate, 'base64').toString('utf8') === expectedUrl.toString()
    )),
    true,
  );

  const mismatch = makeLiveFake({ projectMode: true, projectTitle: '另一个项目' });
  const failed = await runBridge({
    adbPath: 'fake-adb',
    serial: 'A',
    execute: true,
    prompt,
    conversationId,
    projectTitle,
    execFile: mismatch.execFile,
    sleep: async () => {},
  });
  assert.equal(failed.result, 'failed');
  assert.equal(failed.errorCode, 'E_UI_PROJECT_CONTEXT_MISMATCH');
  assert.equal(mismatch.calls.some((args) => args.includes('input')), false);

  for (const projectTitlePlacement of ['message', 'duplicate_headers']) {
    const malformed = makeLiveFake({
      projectMode: true,
      projectTitle,
      projectTitlePlacement,
    });
    const malformedReceipt = await runBridge({
      adbPath: 'fake-adb',
      serial: 'A',
      execute: true,
      prompt,
      conversationId,
      projectTitle,
      execFile: malformed.execFile,
      sleep: async () => {},
    });
    assert.equal(malformedReceipt.result, 'failed');
    assert.equal(malformedReceipt.errorCode, 'E_UI_PROJECT_CONTEXT_MISMATCH');
    assert.equal(malformed.calls.some((args) => args.includes('input')), false);
  }
});

test('locked and unknown-profile live runs stop before ACTION_SEND', async () => {
  for (const [configuration, code] of [
    [{ locked: true }, 'E_DEVICE_LOCKED'],
    [{ unknownProfile: true }, 'E_PROFILE_UNKNOWN'],
  ]) {
    const fake = makeLiveFake(configuration);
    const receipt = await runBridge({
      adbPath: 'fake-adb',
      serial: 'A',
      execute: true,
      prompt: 'sleep',
      execFile: fake.execFile,
    });
    assert.equal(receipt.result, 'failed');
    assert.equal(receipt.errorCode, code);
    assert.equal(fake.calls.some((args) => args.join(' ').includes('am start -W')), false);
    assert.equal(fake.calls.some((args) => args.includes('force-stop')), false);
  }
});

test('UI cleanup failure is explicit and does not force-stop before attributable audio', async () => {
  const fake = makeLiveFake({ cleanupFails: true });
  const receipt = await runBridge({
    adbPath: 'fake-adb',
    serial: 'A',
    execute: true,
    prompt: 'sleep',
    execFile: fake.execFile,
  });
  assert.equal(receipt.result, 'failed');
  assert.equal(receipt.errorCode, 'E_CLEANUP_FAILED');
  assert.equal(receipt.evidence.uiArtifactCleanupSucceeded, false);
  assert.match(receipt.evidence.uiArtifactCleanupFailurePath, /^\/data\/local\/tmp\//u);
  assert.equal(receipt.evidence.failureForceStopAttempted, false);
});

test('Read Aloud start timeout force-stops after the media tap was issued', async () => {
  const fake = makeLiveFake({ audioStartNeverObserved: true });
  const receipt = await runBridge({
    adbPath: 'fake-adb',
    serial: 'A',
    execute: true,
    prompt: 'sleep',
    execFile: fake.execFile,
    sleep: async () => {},
    now: advancingClock(),
    audioStartMs: 2,
    pollMs: 1,
  });
  assert.equal(receipt.result, 'failed');
  assert.equal(receipt.errorCode, 'E_AUDIO_START_TIMEOUT');
  assert.equal(receipt.evidence.readAloudTapIssued, true);
  assert.equal(receipt.evidence.audioStartObserved, false);
  assert.equal(receipt.evidence.failureForceStopAttempted, true);
  assert.equal(receipt.evidence.failureForceStopSucceeded, true);
  assert.equal(
    receipt.evidence.failureForceStopReason,
    'read_aloud_tap_issued_unconfirmed',
  );
  assert.equal(
    fake.calls.some((args) => args.join(' ').endsWith('shell am force-stop com.openai.chatgpt')),
    true,
  );
});

test('Voice RECORD_AUDIO timeout force-stops after the Voice tap was issued', async () => {
  const fake = makeLiveFake({ recordAudioNeverRuns: true });
  const receipt = await runBridge({
    adbPath: 'fake-adb',
    serial: 'A',
    execute: true,
    prompt: 'sleep',
    execFile: fake.execFile,
    sleep: async () => {},
    now: advancingClock(),
    recordAudioMs: 2,
    pollMs: 1,
  });
  assert.equal(receipt.result, 'failed');
  assert.equal(receipt.errorCode, 'E_RECORD_AUDIO_NOT_RUNNING');
  assert.equal(receipt.evidence.voiceTapIssued, true);
  assert.equal(receipt.evidence.recordAudioRunning, false);
  assert.equal(receipt.evidence.failureForceStopAttempted, true);
  assert.equal(receipt.evidence.failureForceStopSucceeded, true);
  assert.equal(
    receipt.evidence.failureForceStopReason,
    'voice_tap_issued_unconfirmed',
  );
  assert.equal(
    fake.calls.some((args) => args.join(' ').endsWith('shell am force-stop com.openai.chatgpt')),
    true,
  );
});

test('media timeout still force-stops ChatGPT after foreground context changes', async () => {
  for (const scenario of [
    {
      fakeOptions: {
        audioStartNeverObserved: true,
        contextChangesAfterMediaTap: 'read_aloud',
      },
      runOptions: { audioStartMs: 2 },
      errorCode: 'E_AUDIO_START_TIMEOUT',
      reason: 'read_aloud_tap_issued_unconfirmed_context_changed',
    },
    {
      fakeOptions: {
        recordAudioNeverRuns: true,
        contextChangesAfterMediaTap: 'voice',
      },
      runOptions: { recordAudioMs: 2 },
      errorCode: 'E_RECORD_AUDIO_NOT_RUNNING',
      reason: 'voice_tap_issued_unconfirmed_context_changed',
    },
  ]) {
    const fake = makeLiveFake(scenario.fakeOptions);
    const receipt = await runBridge({
      adbPath: 'fake-adb',
      serial: 'A',
      execute: true,
      prompt: 'sleep',
      execFile: fake.execFile,
      sleep: async () => {},
      now: advancingClock(),
      pollMs: 1,
      ...scenario.runOptions,
    });
    assert.equal(receipt.result, 'failed');
    assert.equal(receipt.errorCode, scenario.errorCode);
    assert.equal(receipt.evidence.failureForceStopContextStatus, 'context_changed');
    assert.equal(receipt.evidence.failureForceStopAttempted, true);
    assert.equal(receipt.evidence.failureForceStopSucceeded, true);
    assert.equal(receipt.evidence.failureForceStopReason, scenario.reason);
    assert.equal(
      fake.calls.some((args) => (
        args.join(' ').endsWith('shell am force-stop com.openai.chatgpt')
      )),
      true,
    );
  }
});
