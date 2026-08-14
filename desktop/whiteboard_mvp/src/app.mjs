import {
  createBoard,
  createInitialSnapshot,
  filterCards,
  moveBoardItem,
  normalizeSnapshot,
  placeCard,
  removeBoardItem,
  storageKey,
  updateViewport,
} from './model.mjs';

const app = document.querySelector('#app');
const workspace = app.querySelector('.hia-workspace');
const sidebarToggle = app.querySelector('.hia-sidebar-toggle');
const chatTrigger = app.querySelector('.hia-i-trigger');
const chatPopover = app.querySelector('.hia-i-popover');
const chatForm = app.querySelector('.hia-chat-input');
const toast = app.querySelector('.hia-toast');

let snapshot = loadSnapshot();
let cardFilter = 'all';
let cardQuery = '';
let selectedBoardItemId = null;
let toastTimer = null;
let viewportSaveTimer = null;

function loadSnapshot() {
  try {
    const stored = localStorage.getItem(storageKey);
    return normalizeSnapshot(stored ? JSON.parse(stored) : createInitialSnapshot());
  } catch {
    return createInitialSnapshot();
  }
}

function saveSnapshot() {
  localStorage.setItem(storageKey, JSON.stringify(snapshot));
}

function escapeHtml(value) {
  return String(value ?? '')
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#039;');
}

function currentRoute() {
  const raw = location.hash.replace(/^#/, '') || 'home';
  const [name, id] = raw.split('/');
  if (name === 'board') return { name, boardId: id || snapshot.ui.lastBoardId };
  if (['home', 'boards', 'cards'].includes(name)) return { name };
  return { name: 'home' };
}

function navigate(route) {
  if (location.hash === `#${route}`) {
    render();
    return;
  }
  location.hash = route;
}

function setNavigationCollapsed(collapsed) {
  snapshot.ui.navigationCollapsed = collapsed;
  app.classList.toggle('is-nav-collapsed', collapsed);
  sidebarToggle.setAttribute('aria-expanded', String(!collapsed));
  sidebarToggle.setAttribute('aria-label', collapsed ? '打开侧栏' : '收起侧栏');
  sidebarToggle.innerHTML = collapsed
    ? '<svg viewBox="0 0 20 20" aria-hidden="true"><path d="m7.5 4.5 5.5 5.5-5.5 5.5" /></svg>'
    : '<svg viewBox="0 0 20 20" aria-hidden="true"><path d="M12.5 4.5 7 10l5.5 5.5" /></svg>';
  saveSnapshot();
}

function showToast(message) {
  clearTimeout(toastTimer);
  toast.textContent = message;
  toast.hidden = false;
  toastTimer = setTimeout(() => {
    toast.hidden = true;
  }, 1700);
}

function formatTime(value) {
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return '';
  return new Intl.DateTimeFormat('zh-CN', {
    month: 'numeric',
    day: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
  }).format(date);
}

function render() {
  const route = currentRoute();
  const boardMode = route.name === 'board';
  app.classList.toggle('hia-board-mode', boardMode);

  if (boardMode && !snapshot.ui.navigationCollapsed) {
    snapshot.ui.navigationCollapsed = true;
    saveSnapshot();
  }
  setNavigationCollapsed(snapshot.ui.navigationCollapsed);

  app.querySelectorAll('.hia-nav-item').forEach((item) => {
    const activeRoute = route.name === 'board' ? 'boards' : route.name;
    item.classList.toggle('is-active', item.dataset.route === activeRoute);
  });

  if (route.name === 'home') renderHome();
  if (route.name === 'cards') renderCards();
  if (route.name === 'boards') renderBoards();
  if (route.name === 'board') renderBoard(route.boardId);
}

function pageHead(title, kicker, actions = '') {
  return `
    <header class="hia-page-head">
      <div><h1>${escapeHtml(title)}</h1><p class="hia-page-kicker">${escapeHtml(kicker)}</p></div>
      <div class="hia-page-actions">${actions}</div>
    </header>
  `;
}

function renderHome() {
  const activeBoard = snapshot.boards.find((board) => board.boardId === snapshot.ui.lastBoardId)
    ?? snapshot.boards[0];
  const boardCount = snapshot.boards.length;
  const unplaced = snapshot.cards.filter((card) =>
    !snapshot.boardItems.some((item) => item.cardId === card.cardId)).length;

  workspace.innerHTML = `
    <section class="hia-page">
      ${pageHead('工作台', '2026.08.14 · PALM · MVP 示例数据', `
        <button class="hia-button is-primary" type="button" data-action="create-board">新建白板</button>
      `)}
      <div class="hia-dashboard-grid">
        <section class="hia-module hia-span-4">
          <div class="hia-module-head"><h2 class="hia-module-label">林埃观察</h2><span class="hia-module-stat">本月</span></div>
          <div class="hia-metric-row">
            <div><div class="hia-metric-value">6,240</div><div class="hia-metric-label">本月字数</div><div class="hia-metric-delta">+12%</div></div>
            <div><div class="hia-metric-value">4.2h</div><div class="hia-metric-label">昨日阅读</div><div class="hia-metric-delta">+0.8h</div></div>
            <div><div class="hia-metric-value">87%</div><div class="hia-metric-label">完成率</div><div class="hia-metric-delta">≈ 持平</div></div>
          </div>
          <div class="hia-bars" role="img" aria-label="最近十一日专注时长，金黄色柱表示本期峰值">
            <i style="--bar-height:32%"></i><i style="--bar-height:46%"></i><i style="--bar-height:55%"></i><i style="--bar-height:42%"></i><i style="--bar-height:68%"></i><i style="--bar-height:53%"></i><i style="--bar-height:73%"></i><i style="--bar-height:62%"></i><i class="is-focus" style="--bar-height:88%"></i><i style="--bar-height:59%"></i><i class="is-strong" style="--bar-height:78%"></i>
          </div>
          <div class="hia-insight-head"><span class="hia-insight-mark"></span><span>i 的观察</span></div>
          <p class="hia-insight-copy">上午 9–11 点仍是最稳定的深度窗口，适合把需要思考的阅读任务放在这里。</p>
        </section>

        <section class="hia-module hia-span-4">
          <div class="hia-module-head"><h2 class="hia-module-label">日程与待办</h2><span class="hia-module-stat">今天 · 5 项</span></div>
          <div class="hia-list">
            ${taskRow('完成《置身事内》第四章', '阅读任务')}
            ${taskRow('整理上周健康记录', '健康', '紧急', 'warning')}
            ${taskRow('回复周末计划消息', '消息 · 待回复')}
            ${taskRow('更新项目状态文件', '完成于 09:32', '', '', true)}
            ${taskRow('查看昨夜睡眠数据', '完成于 08:15', '', '', true)}
          </div>
        </section>

        <section class="hia-module hia-span-4">
          <div class="hia-module-head"><h2 class="hia-module-label">今日总结</h2><span class="hia-module-stat">今天</span></div>
          <p class="hia-summary-copy">上午集中处理了白板组件和语音链路，下午适合留给阅读与整理。当前有一条值得确认的项目决定。</p>
          <div class="hia-memory-proposal">
            <div class="hia-tiny">待确认记忆</div>
            <div>白板组件基础层 v0.1 已冻结，进入第一条功能纵切。</div>
            <div class="hia-inline-actions" style="margin-top:8px">
              <button class="hia-button is-primary" type="button" data-action="confirm-memory">记下来</button>
              <button class="hia-button" type="button" data-action="skip-memory">跳过</button>
            </div>
          </div>
        </section>

        <section class="hia-module hia-span-3">
          <div class="hia-module-head"><h2 class="hia-module-label">继续工作</h2><button class="hia-module-link" type="button" data-open-board="${activeBoard.boardId}">打开白板</button></div>
          ${contentRow('▦', activeBoard.title, `白板 · ${snapshot.boardItems.filter((item) => item.boardId === activeBoard.boardId).length} 张卡`)}
          ${contentRow('◇', '白板 UI 设计探索', '任务房间 · 进行中')}
          ${contentRow('▦', '健康数据统一方案', '白板 · 3 天前')}
        </section>

        <section class="hia-module hia-span-3">
          <div class="hia-module-head"><h2 class="hia-module-label">继续阅读</h2><span class="hia-module-stat">3 本</span></div>
          ${readingRow('置身事内', '第四章 · 62%', 62)}
          ${readingRow('草枕', '第三章 · 34%', 34)}
          ${readingRow('The Pragmatic Programmer', 'Chapter 2 · 19%', 19)}
        </section>

        <section class="hia-module hia-span-3">
          <div class="hia-module-head"><h2 class="hia-module-label">待整理卡片</h2><button class="hia-module-link" type="button" data-go="cards">查看卡片库</button></div>
          <div class="hia-chip-cloud">
            <span class="hia-chip"><small>网页</small>AFFiNE 架构</span>
            <span class="hia-chip"><small>截图</small>睡眠 8/13</span>
            <span class="hia-chip"><small>笔记</small>土地财政</span>
            <span class="hia-chip"><small>视频</small>tldraw 解析</span>
          </div>
          <p class="hia-tiny">${unplaced} 项尚未放入任何白板</p>
        </section>

        <section class="hia-module hia-span-3">
          <div class="hia-module-head"><h2 class="hia-module-label">后台任务</h2><span class="hia-module-stat">4 项</span></div>
          ${agentTask('Whiteboard MVP 壳', '运行中', 'running')}
          ${agentTask('白板引擎赛马', '等待决定', 'waiting')}
          ${agentTask('Palm Token 整理', '2h 前', '')}
          ${agentTask('组件规范检查', '昨天', '')}
        </section>

        <section class="hia-module hia-span-5">
          <div class="hia-module-head"><h2 class="hia-module-label">记忆回顾</h2><span class="hia-module-stat">4 条</span></div>
          <div class="hia-memory-grid">
            ${memoryRow('事实', '统一 Card 身份不等于统一缩略条', '白板设计 · 今天')}
            ${memoryRow('决定', '任务区先采用高密度看板结构，列名后定', '产品决定 · 今天')}
            ${memoryRow('计划', '首条纵切跑通卡片库到白板保存恢复', '开发任务 · 今天')}
            ${memoryRow('事件', 'Lieflat Charts 已同步至 v1.2.0', '项目记录 · 今天')}
          </div>
        </section>

        <section class="hia-module hia-span-4">
          <div class="hia-module-head"><h2 class="hia-module-label">睡眠区间</h2><span class="hia-module-stat">近 4 天</span></div>
          <div class="hia-metric-value">7h 18m</div>
          <div class="hia-range-chart" role="img" aria-label="最近四天入睡与醒来时间区间">
            ${rangeRow('一', 18, 58)}${rangeRow('二', 25, 54)}${rangeRow('三', 12, 63)}${rangeRow('四', 22, 59)}
          </div>
        </section>

        <section class="hia-module hia-span-3">
          <div class="hia-module-head"><h2 class="hia-module-label">本月账本</h2><span class="hia-module-stat">8 月</span></div>
          <div class="hia-metric-value">¥1,840</div><div class="hia-tiny">当前结余</div>
          <div class="hia-ledger-bars" role="img" aria-label="本月三类主要支出，金黄色表示本月最高分类">
            ${ledgerRow('餐饮', 68, true, '¥860')}${ledgerRow('交通', 36, false, '¥420')}${ledgerRow('书籍', 49, false, '¥610')}
          </div>
        </section>
      </div>
      <p class="hia-page-footnote">${boardCount} 张白板 · ${snapshot.cards.length} 张卡片 · 数据仅用于 MVP 结构验证</p>
    </section>
  `;
  bindCommonActions();
}

function taskRow(title, subtitle, status = '', tone = '', done = false) {
  return `<div class="hia-list-row"><span class="hia-checkbox ${done ? 'is-done' : ''}"></span><div><strong>${escapeHtml(title)}</strong><div class="hia-row-subtitle">${escapeHtml(subtitle)}</div></div>${status ? `<span class="hia-status-pill ${tone ? `is-${tone}` : ''}">${escapeHtml(status)}</span>` : '<span></span>'}</div>`;
}

function contentRow(icon, title, subtitle) {
  return `<div class="hia-content-row"><span class="hia-thumb-mini">${escapeHtml(icon)}</span><div><strong>${escapeHtml(title)}</strong><div class="hia-row-subtitle">${escapeHtml(subtitle)}</div></div></div>`;
}

function readingRow(title, subtitle, progress) {
  return `<div class="hia-content-row"><span class="hia-thumb-mini">书</span><div><strong>${escapeHtml(title)}</strong><div class="hia-progress"><i style="--progress:${progress}%"></i></div><div class="hia-row-subtitle">${escapeHtml(subtitle)}</div></div></div>`;
}

function agentTask(title, status, state) {
  return `<div class="hia-task-row"><span class="hia-task-dot ${state ? `is-${state}` : ''}"></span><span>${escapeHtml(title)}</span><span class="hia-tiny">${escapeHtml(status)}</span></div>`;
}

function memoryRow(type, title, source) {
  return `<div class="hia-memory-item"><div class="hia-tiny">${escapeHtml(type)}</div><strong>${escapeHtml(title)}</strong><div class="hia-row-subtitle">${escapeHtml(source)}</div></div>`;
}

function rangeRow(label, start, width) {
  return `<div class="hia-range-row"><span>${label}</span><span class="hia-range-track"><i style="--range-start:${start}%;--range-width:${width}%"></i></span></div>`;
}

function ledgerRow(label, amount, focus, value) {
  return `<div class="hia-ledger-row ${focus ? 'is-focus' : ''}"><span>${label}</span><span class="hia-ledger-track"><i style="--amount:${amount}%"></i></span><span class="hia-tiny">${value}</span></div>`;
}

function renderCards() {
  const visibleCards = filterCards(snapshot.cards, cardQuery, cardFilter);
  const filters = [
    ['all', '全部'], ['text', '文字'], ['book', '书籍'], ['image', '图片'],
    ['web', '网页'], ['video', '视频'], ['annotation', '批注'],
  ];

  workspace.innerHTML = `
    <section class="hia-page">
      ${pageHead('卡片库', `${snapshot.cards.length} 张卡片 · 一个库，按类型筛选`, `
        <label class="hia-search-box"><input type="search" value="${escapeHtml(cardQuery)}" placeholder="搜索标题、正文、来源或标签" data-card-search /></label>
      `)}
      <div class="hia-filter-row">
        ${filters.map(([value, label]) => `<button class="hia-filter-button" type="button" aria-pressed="${cardFilter === value}" data-card-filter="${value}">${label}</button>`).join('')}
      </div>
      ${visibleCards.length ? `<div class="hia-card-grid">${visibleCards.map(libraryCard).join('')}</div>` : '<div class="hia-empty-state">没有符合条件的卡片</div>'}
    </section>
  `;
  bindCommonActions();

  workspace.querySelector('[data-card-search]')?.addEventListener('input', (event) => {
    cardQuery = event.target.value;
    renderCards();
    const input = workspace.querySelector('[data-card-search]');
    input?.focus();
    input?.setSelectionRange(cardQuery.length, cardQuery.length);
  });
  workspace.querySelectorAll('[data-card-filter]').forEach((button) => {
    button.addEventListener('click', () => {
      cardFilter = button.dataset.cardFilter;
      renderCards();
    });
  });
  workspace.querySelectorAll('[data-add-card]').forEach((button) => {
    button.addEventListener('click', () => addCardToLastBoard(button.dataset.addCard));
  });
}

function libraryCard(card) {
  if (card.mediaType === 'text' || card.mediaType === 'annotation') {
    return `
      <article class="hia-library-card is-text">
        <div class="hia-text-card">
          <div class="hia-card-meta"><span class="hia-card-type">${escapeHtml(typeLabel(card.mediaType))}</span><span>${formatTime(card.createdAt)}</span></div>
          <p>${escapeHtml(card.body)}</p>
          <h3>${escapeHtml(card.title)}</h3>
          <div class="hia-card-meta"><span>${escapeHtml(card.source)}</span><span>${escapeHtml((card.tags ?? []).join(' · '))}</span></div>
        </div>
        ${cardActions(card)}
      </article>
    `;
  }

  return `
    <article class="hia-library-card">
      ${cardPreview(card)}
      <div class="hia-card-copy"><h3>${escapeHtml(card.title)}</h3><div class="hia-card-meta"><span>${escapeHtml(card.source)}</span><span class="hia-card-type">${escapeHtml(typeLabel(card.mediaType))}</span></div></div>
      ${cardActions(card)}
    </article>
  `;
}

function cardPreview(card) {
  if (card.mediaType === 'web') {
    return '<div class="hia-card-preview is-paper"><div class="hia-web-preview"><i></i><i></i><i></i><i></i></div></div>';
  }
  if (card.mediaType === 'book') {
    return `<div class="hia-card-preview is-book"><div class="hia-book-cover">${escapeHtml(card.title.slice(0, 4))}</div></div>`;
  }
  const accent = card.accent === 'dark' ? 'is-dark' : card.accent === 'sleep' ? 'is-sleep' : 'is-rain';
  return `<div class="hia-card-preview ${accent}"><span>${escapeHtml(card.mediaType === 'video' ? '02:22 / 11:20' : card.title)}</span></div>`;
}

function cardActions(card) {
  return `<div class="hia-card-actions"><span class="hia-tiny">${escapeHtml((card.tags ?? []).slice(0, 2).join(' · '))}</span><button class="hia-button is-quiet" type="button" data-add-card="${card.cardId}" title="MVP 临时放入最近使用的白板；正式版将选择目标白板">放入最近白板</button></div>`;
}

function typeLabel(mediaType) {
  return ({ text: '文字', book: '书籍', image: '图片', web: '网页', video: '视频', annotation: '批注' })[mediaType] ?? mediaType;
}

function addCardToLastBoard(cardId) {
  const boardId = snapshot.ui.lastBoardId || snapshot.boards[0].boardId;
  const count = snapshot.boardItems.filter((item) => item.boardId === boardId).length;
  const placed = placeCard(snapshot, {
    boardId,
    cardId,
    x: 140 + (count % 3) * 70,
    y: 110 + (count % 4) * 54,
  });
  snapshot = placed.snapshot;
  saveSnapshot();
  navigate(`board/${boardId}`);
  showToast('已放入白板');
}

function renderBoards() {
  workspace.innerHTML = `
    <section class="hia-page">
      ${pageHead('白板', `${snapshot.boards.length} 张白板`, '<button class="hia-button is-primary" type="button" data-action="create-board">新建白板</button>')}
      <div class="hia-board-list">
        ${snapshot.boards.map((board) => {
          const count = snapshot.boardItems.filter((item) => item.boardId === board.boardId).length;
          return `<article class="hia-board-tile"><div><h2>${escapeHtml(board.title)}</h2><div class="hia-meta">${count} 张卡片 · ${formatTime(board.updatedAt)}</div></div><div class="hia-board-preview"><i></i><i></i></div><button class="hia-button" type="button" data-open-board="${board.boardId}">进入白板</button></article>`;
        }).join('')}
      </div>
    </section>
  `;
  bindCommonActions();
}

function createNewBoard() {
  const result = createBoard(snapshot, `新白板 ${snapshot.boards.length + 1}`);
  snapshot = result.snapshot;
  saveSnapshot();
  navigate(`board/${result.boardId}`);
  showToast('白板已创建');
}

function renderBoard(requestedBoardId) {
  const board = snapshot.boards.find((candidate) => candidate.boardId === requestedBoardId)
    ?? snapshot.boards[0];
  if (!board) {
    navigate('boards');
    return;
  }
  snapshot.ui.lastBoardId = board.boardId;
  saveSnapshot();

  const items = snapshot.boardItems.filter((item) => item.boardId === board.boardId);
  workspace.innerHTML = `
    <section class="hia-board-view" data-board-view="${board.boardId}">
      <div class="hia-board-toolbar">
        <button class="hia-icon-button" type="button" aria-label="返回白板列表" data-go="boards"><svg viewBox="0 0 20 20" aria-hidden="true"><path d="M12.5 4.5 7 10l5.5 5.5" /></svg></button>
        <span class="hia-board-title">${escapeHtml(board.title)}</span>
        <button class="hia-button" type="button" data-action="toggle-card-dock">卡片库</button>
        <button class="hia-icon-button" type="button" aria-label="缩小" data-action="zoom-out">−</button>
        <span class="hia-board-zoom" data-board-zoom>${Math.round(board.viewport.zoom * 100)}%</span>
        <button class="hia-icon-button" type="button" aria-label="放大" data-action="zoom-in">＋</button>
      </div>
      <aside class="hia-card-dock" data-card-dock>
        <div class="hia-card-dock-head"><strong>卡片库</strong><button class="hia-icon-button" type="button" aria-label="关闭卡片库" data-action="toggle-card-dock">×</button></div>
        <div class="hia-tiny" style="margin-bottom:9px">拖到画布中；卡片内容不会被复制</div>
        <div class="hia-card-dock-list">${snapshot.cards.map(dockCard).join('')}</div>
      </aside>
      <div class="hia-board-canvas" data-board-canvas style="--grid-x:${board.viewport.x}px;--grid-y:${board.viewport.y}px;--grid-size:${22 * board.viewport.zoom}px">
        <div class="hia-board-world" data-board-world style="--world-x:${board.viewport.x}px;--world-y:${board.viewport.y}px;--world-zoom:${board.viewport.zoom}">
          ${items.map((item) => boardItem(item, snapshot.cards.find((card) => card.cardId === item.cardId))).join('')}
        </div>
        ${items.length ? '' : '<div class="hia-board-empty">从卡片库拖一张卡到这里</div>'}
      </div>
      <div class="hia-board-help">滚轮缩放 · 拖动画布平移 · Delete 移除摆放</div>
    </section>
  `;

  bindCommonActions();
  bindBoardInteractions(board.boardId);
}

function dockCard(card) {
  return `<article class="hia-dock-card" draggable="true" data-drag-card="${card.cardId}"><strong>${escapeHtml(card.title)}</strong><span class="hia-tiny">${escapeHtml(typeLabel(card.mediaType))} · ${escapeHtml(card.source)}</span></article>`;
}

function boardItem(item, card) {
  if (!card) return '';
  const hasMedia = !['text', 'annotation'].includes(card.mediaType);
  const mediaClass = card.accent === 'dark' ? 'is-dark' : card.mediaType === 'web' ? 'is-paper' : '';
  return `
    <article class="hia-board-item ${selectedBoardItemId === item.itemId ? 'is-selected' : ''}" data-board-item="${item.itemId}" style="--item-x:${item.x}px;--item-y:${item.y}px;--item-width:${item.width}px;--item-height:${item.height}px;--item-z:${item.zIndex}">
      ${hasMedia ? `<div class="hia-board-item-media ${mediaClass}"></div>` : ''}
      <div class="hia-board-item-copy"><span class="hia-tiny">${escapeHtml(typeLabel(card.mediaType))} · ${escapeHtml(card.source)}</span><strong>${escapeHtml(card.title)}</strong><p>${escapeHtml(card.body)}</p></div>
      <button class="hia-board-resize-handle" type="button" aria-label="调整卡片大小" data-resize-item="${item.itemId}"></button>
    </article>
  `;
}

function bindCommonActions() {
  workspace.querySelectorAll('[data-go]').forEach((button) => {
    button.addEventListener('click', () => navigate(button.dataset.go));
  });
  workspace.querySelectorAll('[data-open-board]').forEach((button) => {
    button.addEventListener('click', () => navigate(`board/${button.dataset.openBoard}`));
  });
  workspace.querySelectorAll('[data-action="create-board"]').forEach((button) => {
    button.addEventListener('click', createNewBoard);
  });
  workspace.querySelector('[data-action="confirm-memory"]')?.addEventListener('click', (event) => {
    event.currentTarget.closest('.hia-memory-proposal')?.remove();
    showToast('已记录为一条待整理记忆');
  });
  workspace.querySelector('[data-action="skip-memory"]')?.addEventListener('click', (event) => {
    event.currentTarget.closest('.hia-memory-proposal')?.remove();
    showToast('已跳过');
  });
}

function bindBoardInteractions(boardId) {
  const board = snapshot.boards.find((candidate) => candidate.boardId === boardId);
  const view = workspace.querySelector('[data-board-view]');
  const canvas = view.querySelector('[data-board-canvas]');
  const world = view.querySelector('[data-board-world]');
  const zoomLabel = view.querySelector('[data-board-zoom]');
  const cardDock = view.querySelector('[data-card-dock]');

  view.querySelectorAll('[data-action="toggle-card-dock"]').forEach((button) => {
    button.addEventListener('click', () => cardDock.classList.toggle('is-open'));
  });

  const applyViewport = () => {
    world.style.setProperty('--world-x', `${board.viewport.x}px`);
    world.style.setProperty('--world-y', `${board.viewport.y}px`);
    world.style.setProperty('--world-zoom', board.viewport.zoom);
    canvas.style.setProperty('--grid-x', `${board.viewport.x}px`);
    canvas.style.setProperty('--grid-y', `${board.viewport.y}px`);
    canvas.style.setProperty('--grid-size', `${22 * board.viewport.zoom}px`);
    zoomLabel.textContent = `${Math.round(board.viewport.zoom * 100)}%`;
  };

  const commitViewportSoon = () => {
    clearTimeout(viewportSaveTimer);
    viewportSaveTimer = setTimeout(() => {
      snapshot = updateViewport(snapshot, boardId, board.viewport);
      saveSnapshot();
    }, 140);
  };

  const setZoom = (nextZoom, clientPoint = null) => {
    const rect = canvas.getBoundingClientRect();
    const point = clientPoint ?? { x: rect.width / 2, y: rect.height / 2 };
    const localX = point.x - rect.left;
    const localY = point.y - rect.top;
    const worldX = (localX - board.viewport.x) / board.viewport.zoom;
    const worldY = (localY - board.viewport.y) / board.viewport.zoom;
    board.viewport.zoom = Math.min(2.2, Math.max(0.35, nextZoom));
    board.viewport.x = localX - worldX * board.viewport.zoom;
    board.viewport.y = localY - worldY * board.viewport.zoom;
    applyViewport();
    commitViewportSoon();
  };

  view.querySelector('[data-action="zoom-in"]').addEventListener('click', () => setZoom(board.viewport.zoom * 1.12));
  view.querySelector('[data-action="zoom-out"]').addEventListener('click', () => setZoom(board.viewport.zoom / 1.12));

  canvas.addEventListener('wheel', (event) => {
    event.preventDefault();
    setZoom(board.viewport.zoom * (event.deltaY > 0 ? 0.9 : 1.1), { x: event.clientX, y: event.clientY });
  }, { passive: false });

  let pan = null;
  canvas.addEventListener('pointerdown', (event) => {
    if (event.target.closest('[data-board-item]')) return;
    pan = { pointerId: event.pointerId, clientX: event.clientX, clientY: event.clientY, x: board.viewport.x, y: board.viewport.y };
    canvas.setPointerCapture(event.pointerId);
    canvas.classList.add('is-panning');
    selectedBoardItemId = null;
    canvas.querySelectorAll('.hia-board-item').forEach((item) => item.classList.remove('is-selected'));
  });
  canvas.addEventListener('pointermove', (event) => {
    if (!pan || pan.pointerId !== event.pointerId) return;
    board.viewport.x = pan.x + event.clientX - pan.clientX;
    board.viewport.y = pan.y + event.clientY - pan.clientY;
    applyViewport();
  });
  const finishPan = (event) => {
    if (!pan || pan.pointerId !== event.pointerId) return;
    pan = null;
    canvas.classList.remove('is-panning');
    snapshot = updateViewport(snapshot, boardId, board.viewport);
    saveSnapshot();
  };
  canvas.addEventListener('pointerup', finishPan);
  canvas.addEventListener('pointercancel', finishPan);

  view.querySelectorAll('[data-board-item]').forEach((element) => {
    element.addEventListener('pointerdown', (event) => {
      if (event.target.closest('[data-resize-item]')) return;
      if (event.button !== 0) return;
      event.stopPropagation();
      const itemId = element.dataset.boardItem;
      const item = snapshot.boardItems.find((candidate) => candidate.itemId === itemId);
      if (!item) return;
      selectedBoardItemId = itemId;
      view.querySelectorAll('[data-board-item]').forEach((candidate) => candidate.classList.toggle('is-selected', candidate === element));
      const drag = { pointerId: event.pointerId, clientX: event.clientX, clientY: event.clientY, x: item.x, y: item.y };
      element.setPointerCapture(event.pointerId);

      const move = (moveEvent) => {
        if (moveEvent.pointerId !== drag.pointerId) return;
        const x = drag.x + (moveEvent.clientX - drag.clientX) / board.viewport.zoom;
        const y = drag.y + (moveEvent.clientY - drag.clientY) / board.viewport.zoom;
        element.style.setProperty('--item-x', `${Math.round(x)}px`);
        element.style.setProperty('--item-y', `${Math.round(y)}px`);
      };
      const up = (upEvent) => {
        if (upEvent.pointerId !== drag.pointerId) return;
        const x = drag.x + (upEvent.clientX - drag.clientX) / board.viewport.zoom;
        const y = drag.y + (upEvent.clientY - drag.clientY) / board.viewport.zoom;
        snapshot = moveBoardItem(snapshot, itemId, { x, y });
        saveSnapshot();
        element.removeEventListener('pointermove', move);
        element.removeEventListener('pointerup', up);
        element.removeEventListener('pointercancel', up);
      };
      element.addEventListener('pointermove', move);
      element.addEventListener('pointerup', up);
      element.addEventListener('pointercancel', up);
    });
  });

  view.querySelectorAll('[data-resize-item]').forEach((handle) => {
    handle.addEventListener('pointerdown', (event) => {
      if (event.button !== 0) return;
      event.preventDefault();
      event.stopPropagation();
      const itemId = handle.dataset.resizeItem;
      const item = snapshot.boardItems.find((candidate) => candidate.itemId === itemId);
      const element = handle.closest('[data-board-item]');
      if (!item || !element) return;
      selectedBoardItemId = itemId;
      view.querySelectorAll('[data-board-item]').forEach((candidate) => candidate.classList.toggle('is-selected', candidate === element));
      const resize = {
        pointerId: event.pointerId,
        clientX: event.clientX,
        clientY: event.clientY,
        width: item.width,
        height: item.height,
      };
      handle.setPointerCapture(event.pointerId);

      const move = (moveEvent) => {
        if (moveEvent.pointerId !== resize.pointerId) return;
        const width = Math.max(180, resize.width + (moveEvent.clientX - resize.clientX) / board.viewport.zoom);
        const height = Math.max(140, resize.height + (moveEvent.clientY - resize.clientY) / board.viewport.zoom);
        element.style.setProperty('--item-width', `${Math.round(width)}px`);
        element.style.setProperty('--item-height', `${Math.round(height)}px`);
      };
      const up = (upEvent) => {
        if (upEvent.pointerId !== resize.pointerId) return;
        const width = Math.max(180, resize.width + (upEvent.clientX - resize.clientX) / board.viewport.zoom);
        const height = Math.max(140, resize.height + (upEvent.clientY - resize.clientY) / board.viewport.zoom);
        snapshot = moveBoardItem(snapshot, itemId, { width, height });
        saveSnapshot();
        handle.removeEventListener('pointermove', move);
        handle.removeEventListener('pointerup', up);
        handle.removeEventListener('pointercancel', up);
      };
      handle.addEventListener('pointermove', move);
      handle.addEventListener('pointerup', up);
      handle.addEventListener('pointercancel', up);
    });
  });

  view.querySelectorAll('[data-drag-card]').forEach((card) => {
    card.addEventListener('dragstart', (event) => {
      event.dataTransfer.effectAllowed = 'copy';
      event.dataTransfer.setData('application/x-hia-card', card.dataset.dragCard);
    });
  });

  canvas.addEventListener('dragover', (event) => {
    if (!event.dataTransfer.types.includes('application/x-hia-card')) return;
    event.preventDefault();
    event.dataTransfer.dropEffect = 'copy';
  });
  canvas.addEventListener('drop', (event) => {
    const cardId = event.dataTransfer.getData('application/x-hia-card');
    if (!cardId) return;
    event.preventDefault();
    const rect = canvas.getBoundingClientRect();
    const x = (event.clientX - rect.left - board.viewport.x) / board.viewport.zoom - 130;
    const y = (event.clientY - rect.top - board.viewport.y) / board.viewport.zoom - 90;
    const placed = placeCard(snapshot, { boardId, cardId, x, y });
    snapshot = placed.snapshot;
    selectedBoardItemId = placed.item.itemId;
    saveSnapshot();
    renderBoard(boardId);
    workspace.querySelector('[data-card-dock]')?.classList.add('is-open');
    showToast('卡片已放入白板');
  });
}

sidebarToggle.addEventListener('click', () => {
  setNavigationCollapsed(!snapshot.ui.navigationCollapsed);
});

chatTrigger.addEventListener('click', () => {
  const open = chatPopover.hidden;
  chatPopover.hidden = !open;
  chatTrigger.setAttribute('aria-expanded', String(open));
  if (open) chatForm.querySelector('input').focus();
});

chatForm.addEventListener('submit', (event) => {
  event.preventDefault();
  const input = chatForm.querySelector('input');
  const value = input.value.trim();
  if (!value) return;
  const bubble = document.createElement('div');
  bubble.className = 'hia-chat-bubble hia-chat-user';
  bubble.textContent = value;
  chatForm.before(bubble);
  input.value = '';
  showToast('MVP 暂未连接执行 Agent');
});

window.addEventListener('keydown', (event) => {
  if (event.key !== 'Delete' || !selectedBoardItemId || currentRoute().name !== 'board') return;
  const boardId = currentRoute().boardId;
  snapshot = removeBoardItem(snapshot, selectedBoardItemId);
  selectedBoardItemId = null;
  saveSnapshot();
  renderBoard(boardId);
  showToast('已从白板移除，卡片仍保留在卡片库');
});

window.addEventListener('hashchange', render);
render();
