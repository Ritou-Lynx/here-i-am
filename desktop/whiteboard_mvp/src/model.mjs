export const storageKey = 'here-i-am.whiteboard-mvp.snapshot.v1';

const clone = (value) => JSON.parse(JSON.stringify(value));

function nowIso() {
  return new Date().toISOString();
}

function makeId(prefix) {
  const random = globalThis.crypto?.randomUUID?.() ??
    `${Date.now()}-${Math.random().toString(16).slice(2)}`;
  return `${prefix}_${random}`;
}

export function createInitialSnapshot() {
  const cards = [
    {
      cardId: 'card_video_plave',
      kind: 'source',
      mediaType: 'video',
      title: 'PLAVE 舞台灯光研究',
      body: '02:22 后灯光由冷色切换到暖白，适合与舞台配色参考并置。',
      source: '哔哩哔哩',
      tags: ['视频', '舞台'],
      accent: 'dark',
      createdAt: '2026-08-13T10:20:00.000Z',
    },
    {
      cardId: 'card_image_rain',
      kind: 'source',
      mediaType: 'image',
      title: '春雨绿色配色采样',
      body: '低饱和绿色、灰纸底与一点暖黄焦点。',
      source: '图片',
      tags: ['图片', '配色'],
      accent: 'rain',
      createdAt: '2026-08-13T08:42:00.000Z',
    },
    {
      cardId: 'card_web_affine',
      kind: 'source',
      mediaType: 'web',
      title: 'AFFiNE 白板架构分析',
      body: 'BlockSuite、Edgeless 与自有数据快照之间的适配边界。',
      source: '网页',
      tags: ['网页', '白板'],
      accent: 'paper',
      createdAt: '2026-08-12T09:15:00.000Z',
    },
    {
      cardId: 'card_note_spine',
      kind: 'note',
      mediaType: 'text',
      title: '统一卡片脊柱',
      body: '统一 Card 身份不意味着统一缩略条。媒体卡让原媒体成为主体，纯文字卡直接展示正文；白板只保存摆放，不复制内容。',
      source: '笔记',
      tags: ['文字', '架构'],
      createdAt: '2026-08-14T08:32:00.000Z',
    },
    {
      cardId: 'card_book_zhishen',
      kind: 'source',
      mediaType: 'book',
      title: '置身事内',
      body: '第四章 · 阅读进度 62%',
      source: '书籍',
      tags: ['书籍', '经济'],
      accent: 'book',
      createdAt: '2026-08-11T15:10:00.000Z',
    },
    {
      cardId: 'card_annotation_land',
      kind: 'annotation',
      mediaType: 'annotation',
      title: '土地财政的结构',
      body: '土地出让金不仅是收入项目，也影响城市扩张、融资方式和公共服务节奏。',
      source: '《置身事内》第三章',
      tags: ['批注', '财政'],
      createdAt: '2026-08-14T06:18:00.000Z',
    },
    {
      cardId: 'card_image_sleep',
      kind: 'source',
      mediaType: 'image',
      title: '8 月 13 日睡眠记录',
      body: '睡眠 7 小时 18 分，深睡分布较前一日稳定。',
      source: '健康截图',
      tags: ['图片', '健康'],
      accent: 'sleep',
      createdAt: '2026-08-14T00:15:00.000Z',
    },
    {
      cardId: 'card_web_tldraw',
      kind: 'source',
      mediaType: 'web',
      title: 'tldraw 数据模型笔记',
      body: '验证自有 card_id 与引擎 shape id 是否能完全分离。',
      source: '网页',
      tags: ['网页', '引擎'],
      accent: 'paper',
      createdAt: '2026-08-10T12:00:00.000Z',
    },
  ];

  const boards = [
    {
      boardId: 'board_whiteboard_mvp',
      title: '白板 MVP 结构',
      updatedAt: '2026-08-14T10:30:00.000Z',
      viewport: { x: 64, y: 52, zoom: 1 },
    },
    {
      boardId: 'board_stage_color',
      title: '舞台灯光与配色',
      updatedAt: '2026-08-13T18:20:00.000Z',
      viewport: { x: 80, y: 64, zoom: 1 },
    },
  ];

  const boardItems = [
    {
      itemId: 'item_spine',
      boardId: 'board_whiteboard_mvp',
      cardId: 'card_note_spine',
      x: 120,
      y: 90,
      width: 280,
      height: 200,
      zIndex: 1,
    },
    {
      itemId: 'item_affine',
      boardId: 'board_whiteboard_mvp',
      cardId: 'card_web_affine',
      x: 470,
      y: 150,
      width: 260,
      height: 220,
      zIndex: 2,
    },
    {
      itemId: 'item_plave',
      boardId: 'board_stage_color',
      cardId: 'card_video_plave',
      x: 110,
      y: 90,
      width: 320,
      height: 250,
      zIndex: 1,
    },
    {
      itemId: 'item_rain',
      boardId: 'board_stage_color',
      cardId: 'card_image_rain',
      x: 510,
      y: 150,
      width: 270,
      height: 230,
      zIndex: 2,
    },
  ];

  return {
    schemaVersion: 1,
    cards,
    boards,
    boardItems,
    groups: [],
    edges: [],
    ui: { lastBoardId: boards[0].boardId, navigationCollapsed: false },
    updatedAt: '2026-08-14T10:30:00.000Z',
  };
}

export function normalizeSnapshot(raw) {
  const fallback = createInitialSnapshot();
  if (!raw || typeof raw !== 'object' || raw.schemaVersion !== 1) return fallback;

  const cards = Array.isArray(raw.cards) ? raw.cards.filter((card) => card?.cardId) : [];
  const boards = Array.isArray(raw.boards) ? raw.boards.filter((board) => board?.boardId) : [];
  if (boards.length === 0) return fallback;

  const cardIds = new Set(cards.map((card) => card.cardId));
  const boardIds = new Set(boards.map((board) => board.boardId));
  const boardItems = Array.isArray(raw.boardItems)
    ? raw.boardItems.filter((item) =>
        item?.itemId && boardIds.has(item.boardId) && cardIds.has(item.cardId))
    : [];

  return {
    schemaVersion: 1,
    cards,
    boards: boards.map((board) => ({
      ...board,
      viewport: {
        x: Number(board.viewport?.x ?? 64),
        y: Number(board.viewport?.y ?? 52),
        zoom: Math.min(2.2, Math.max(0.35, Number(board.viewport?.zoom ?? 1))),
      },
    })),
    boardItems,
    groups: Array.isArray(raw.groups) ? raw.groups : [],
    edges: Array.isArray(raw.edges) ? raw.edges : [],
    ui: {
      lastBoardId: boardIds.has(raw.ui?.lastBoardId)
        ? raw.ui.lastBoardId
        : boards[0].boardId,
      navigationCollapsed: Boolean(raw.ui?.navigationCollapsed),
    },
    updatedAt: typeof raw.updatedAt === 'string' ? raw.updatedAt : nowIso(),
  };
}

export function createBoard(snapshot, title, options = {}) {
  const next = clone(snapshot);
  const boardId = options.boardId ?? makeId('board');
  const timestamp = options.now ?? nowIso();
  next.boards.push({
    boardId,
    title: title?.trim() || `未命名白板 ${next.boards.length + 1}`,
    updatedAt: timestamp,
    viewport: { x: 64, y: 52, zoom: 1 },
  });
  next.ui.lastBoardId = boardId;
  next.updatedAt = timestamp;
  return { snapshot: next, boardId };
}

export function placeCard(snapshot, input) {
  const { boardId, cardId } = input;
  if (!snapshot.boards.some((board) => board.boardId === boardId)) {
    throw new Error(`Unknown board: ${boardId}`);
  }
  if (!snapshot.cards.some((card) => card.cardId === cardId)) {
    throw new Error(`Unknown card: ${cardId}`);
  }

  const next = clone(snapshot);
  const timestamp = input.now ?? nowIso();
  const item = {
    itemId: input.itemId ?? makeId('item'),
    boardId,
    cardId,
    x: Math.round(Number(input.x ?? 120)),
    y: Math.round(Number(input.y ?? 100)),
    width: Math.max(180, Math.round(Number(input.width ?? 260))),
    height: Math.max(140, Math.round(Number(input.height ?? 210))),
    zIndex: Math.max(0, ...next.boardItems
      .filter((candidate) => candidate.boardId === boardId)
      .map((candidate) => Number(candidate.zIndex ?? 0))) + 1,
  };
  next.boardItems.push(item);
  const board = next.boards.find((candidate) => candidate.boardId === boardId);
  board.updatedAt = timestamp;
  next.ui.lastBoardId = boardId;
  next.updatedAt = timestamp;
  return { snapshot: next, item };
}

export function moveBoardItem(snapshot, itemId, position, options = {}) {
  const next = clone(snapshot);
  const item = next.boardItems.find((candidate) => candidate.itemId === itemId);
  if (!item) throw new Error(`Unknown board item: ${itemId}`);
  if (position.x != null) item.x = Math.round(Number(position.x));
  if (position.y != null) item.y = Math.round(Number(position.y));
  if (position.width != null) item.width = Math.max(180, Math.round(Number(position.width)));
  if (position.height != null) item.height = Math.max(140, Math.round(Number(position.height)));
  item.zIndex = Math.max(1, ...next.boardItems
    .filter((candidate) => candidate.boardId === item.boardId)
    .map((candidate) => Number(candidate.zIndex ?? 0))) + 1;
  const timestamp = options.now ?? nowIso();
  next.boards.find((board) => board.boardId === item.boardId).updatedAt = timestamp;
  next.updatedAt = timestamp;
  return next;
}

export function removeBoardItem(snapshot, itemId, options = {}) {
  const next = clone(snapshot);
  const item = next.boardItems.find((candidate) => candidate.itemId === itemId);
  if (!item) return next;
  next.boardItems = next.boardItems.filter((candidate) => candidate.itemId !== itemId);
  const timestamp = options.now ?? nowIso();
  next.boards.find((board) => board.boardId === item.boardId).updatedAt = timestamp;
  next.updatedAt = timestamp;
  return next;
}

export function updateViewport(snapshot, boardId, viewport, options = {}) {
  const next = clone(snapshot);
  const board = next.boards.find((candidate) => candidate.boardId === boardId);
  if (!board) throw new Error(`Unknown board: ${boardId}`);
  board.viewport = {
    x: Math.round(Number(viewport.x)),
    y: Math.round(Number(viewport.y)),
    zoom: Math.min(2.2, Math.max(0.35, Number(viewport.zoom))),
  };
  const timestamp = options.now ?? nowIso();
  next.ui.lastBoardId = boardId;
  next.updatedAt = timestamp;
  return next;
}

export function filterCards(cards, query, mediaType = 'all') {
  const normalizedQuery = String(query ?? '').trim().toLocaleLowerCase('zh-CN');
  return cards.filter((card) => {
    if (mediaType !== 'all' && card.mediaType !== mediaType) return false;
    if (!normalizedQuery) return true;
    const haystack = [card.title, card.body, card.source, ...(card.tags ?? [])]
      .join(' ')
      .toLocaleLowerCase('zh-CN');
    return haystack.includes(normalizedQuery);
  });
}
