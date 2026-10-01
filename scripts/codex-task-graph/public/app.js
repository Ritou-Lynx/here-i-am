/* global dagre */
'use strict';

// ---------- State ----------
const state = {
  threads: [],
  forest: [],
  overlay: { nodes: {}, edges: {} },
  scannedAt: null,
  filters: { q: '', showSubagents: true, showOrphans: true, onlyActive: false },
  selectedId: null,
  // Pan/zoom transform. (x,y) is world coords rendered at scale.
  view: { x: 0, y: 0, scale: 0.9 },
  // Cached layout. Positions keyed by node id.
  layout: null,
  // Which nodes are actually visible after filters.
  visibleIds: new Set(),
};

// ---------- DOM ----------
const $ = (s) => document.querySelector(s);
const board = $('#board');
const edgesSvg = $('#edges');
const nodesDiv = $('#nodes');
const detail = $('#detail');
const statusText = $('#status-text');
const statusDetail = $('#status-detail');

const esc = (s) => String(s ?? '').replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');

// ---------- Data loading ----------
async function load({ force = false } = {}) {
  statusText.textContent = '加载中…';
  try {
    const res = await fetch(`/api/graph${force ? '?force=1' : ''}`);
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    const data = await res.json();
    state.threads = data.threads ?? [];
    state.forest = data.forest ?? [];
    state.overlay = data.overlay ?? { nodes: {}, edges: {} };
    state.scannedAt = data.scannedAt;
    state.layout = null; // recompute
    renderAll();
    statusText.textContent = `已加载 ${state.threads.length} 个线程`;
    statusDetail.textContent = state.scannedAt ? `数据截至 ${new Date(state.scannedAt).toLocaleString()}` : '';
  } catch (err) {
    statusText.textContent = `加载失败：${err.message}`;
    statusDetail.textContent = '确认 Codex 数据存在、server 启动正常。';
  }
}

// ---------- Filtering ----------

function overlayFor(id) {
  return state.overlay.nodes[id] ?? {};
}

function displayTitle(t) {
  const o = overlayFor(t.id);
  return o.pinnedTitle || t.name || o.goal || t.lastSnippet?.slice(0, 80) || t.id;
}

function isSubagent(t) {
  return !!t.agentPath || (t.source && typeof t.source === 'object' && t.source.subagent);
}

function matchesFilters(t) {
  const o = overlayFor(t.id);
  if (!state.filters.showSubagents && isSubagent(t)) return false;

  if (state.filters.q) {
    const q = state.filters.q.toLowerCase();
    const hay = [
      t.id, t.sessionId, t.name, o.pinnedTitle, o.goal, o.nextAction, o.blocker, o.note, t.lastSnippet,
      t.cwd, t.originator, t.threadSource, t.agentPath,
    ].filter(Boolean).join(' ').toLowerCase();
    if (!hay.includes(q)) return false;
  }

  if (state.filters.onlyActive) {
    if (computeFrontierIds().has(t.id)) return true;
  }

  if (!state.filters.showOrphans) {
    const hasChildren = (state.forest ?? []).some((root) => includesNode(root, t.id));
    // Show orphans only when showOrphans=true; otherwise keep nodes that are inside a root.
    if (!hasChildren && (!t.parentThreadId && !t.forkedFromId)) {
      // It's a root with no children.
      return false;
    }
  }
  return true;
}

function includesNode(node, id) {
  if (node.id === id) return true;
  return (node.children ?? []).some((c) => includesNode(c, id));
}

function computeFrontierIds() {
  // Heuristic: in each root's tree, frontier = leaves that are either (a) explicitly
  // tagged run=pending/running/blocked via overlay, or (b) the most recently updated
  // leaf when nothing is tagged.
  const frontier = new Set();
  for (const root of state.forest) {
    const leaves = [];
    const taggedActive = [];
    const walk = (n, path) => {
      const ov = overlayFor(n.id);
      const newPath = [...path, n.id];
      const kids = n.children ?? [];
      if (kids.length === 0) {
        if (ov.runState && ['pending', 'running', 'blocked'].includes(ov.runState)) {
          taggedActive.push({ id: n.id, path: newPath });
        } else {
          leaves.push({ id: n.id, path: newPath, updatedAt: n.updatedAt ?? n.createdAt ?? '' });
        }
      } else {
        kids.forEach((k) => walk(k, newPath));
      }
    };
    walk(root, []);
    for (const p of taggedActive) frontier.add(p.id);
    if (taggedActive.length === 0 && leaves.length > 0) {
      leaves.sort((a, b) => (b.updatedAt ?? '').localeCompare(a.updatedAt ?? ''));
      frontier.add(leaves[0].id);
    }
  }
  return frontier;
}

// ---------- Layout ----------

function buildGraphInputs() {
  const nodes = [];
  const edges = [];

  const walk = (n, parentId) => {
    if (!matchesFilters(n)) return;
    const visibleChildren = (n.children ?? []).filter(matchesFilters);
    nodes.push(n);
    if (parentId && matchesFiltersById(parentId)) edges.push({ from: parentId, to: n.id, type: 'branch' });
    visibleChildren.forEach((c) => walk(c, n.id));
  };
  state.forest.forEach((r) => walk(r, null));

  // Overlay edges (user-defined): include only when both ends visible.
  const visibleIds = new Set(nodes.map((n) => n.id));
  for (const key of Object.keys(state.overlay.edges ?? {})) {
    const e = state.overlay.edges[key];
    if (visibleIds.has(e.from) && visibleIds.has(e.to)) {
      edges.push(e);
    }
  }

  return { nodes, edges, visibleIds };
}

function matchesFiltersById(id) {
  const t = state.threads.find((x) => x.id === id);
  return t ? matchesFilters(t) : false;
}

function computeLayout() {
  const { nodes, edges, visibleIds } = buildGraphInputs();
  state.visibleIds = visibleIds;

  const NodeW = parseInt(getComputedStyle(document.documentElement).getPropertyValue('--node-w'), 10) || 240;
  const NodeH = 100;

  const g = new dagre.graphlib.Graph();
  g.setGraph({
    rankdir: 'LR',
    nodesep: 24,
    ranksep: 70,
    marginx: 24,
    marginy: 24,
  });
  g.setDefaultEdgeLabel(() => ({}));

  for (const n of nodes) g.setNode(n.id, { width: NodeW, height: NodeH });
  for (const e of edges) g.setEdge(e.from, e.to);

  dagre.layout(g);

  const positions = {};
  g.nodes().forEach((id) => {
    const p = g.node(id);
    positions[id] = { x: p.x - NodeW / 2, y: p.y - NodeH / 2, w: NodeW, h: NodeH };
  });

  state.layout = { positions, edges };
}

// ---------- Render ----------

function renderAll() {
  if (!state.layout) computeLayout();
  renderEdges();
  renderNodes();
  renderDetail();
}

function renderEdges() {
  const { positions, edges } = state.layout;
  const frontier = computeFrontierIds();

  // Compute canvas size and offset so entire graph fits before applying pan/zoom.
  let minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity;
  for (const id of Object.keys(positions)) {
    const p = positions[id];
    minX = Math.min(minX, p.x); minY = Math.min(minY, p.y);
    maxX = Math.max(maxX, p.x + p.w); maxY = Math.max(maxY, p.y + p.h);
  }
  if (minX === Infinity) { minX = 0; minY = 0; maxX = 600; maxY = 400; }

  // Apply current transform. We bake view transform into attributes for pan/zoom.
  const transform = `translate(${state.view.x},${state.view.y}) scale(${state.view.scale})`;

  const pathEls = [];
  for (const e of edges) {
    const a = positions[e.from];
    const b = positions[e.to];
    if (!a || !b) continue;

    const sx = a.x + a.w;
    const sy = a.y + a.h / 2;
    const tx = b.x;
    const ty = b.y + b.h / 2;
    const dx = (tx - sx) * 0.5;
    const d = `M ${sx} ${sy} C ${sx + dx} ${sy}, ${tx - dx} ${ty}, ${tx} ${ty}`;

    const isFrontier = frontier.has(e.to) || frontier.has(e.from);
    pathEls.push(
      `<path d="${d}" data-type="${esc(e.type)}" data-frontier="${isFrontier ? 1 : 0}" />`
    );
  }

  edgesSvg.innerHTML = `<g transform="${transform}">${pathEls.join('')}</g>`;
}

function renderNodes() {
  const { positions } = state.layout;
  const frontier = computeFrontierIds();

  nodesDiv.innerHTML = '';
  const fragment = document.createDocumentFragment();

  // Baked transform via style on a wrapper div. Node positions are world coords;
  // we translate by view.x/y and scale via CSS transform on the container.
  nodesDiv.style.transform = `translate(${state.view.x}px, ${state.view.y}px) scale(${state.view.scale})`;
  nodesDiv.style.transformOrigin = '0 0';

  for (const t of state.threads) {
    if (!state.visibleIds.has(t.id)) continue;
    const pos = positions[t.id];
    if (!pos) continue;

    const o = overlayFor(t.id);
    const div = document.createElement('div');
    div.className = 'node';
    div.style.setProperty('--x', `${pos.x}px`);
    div.style.setProperty('--y', `${pos.y}px`);
    div.dataset.id = t.id;
    div.dataset.kind = o.kind || (t.goal ? 'goal' : 'work');
    div.dataset.frontier = frontier.has(t.id) ? 1 : 0;
    if (state.selectedId === t.id) div.classList.add('selected');

    const title = esc(displayTitle(t));
    const badges = [];
    badges.push(`<span class="badge kind">${esc(o.kind ?? (t.goal ? 'goal' : 'work'))}</span>`);
    if (o.runState) badges.push(`<span class="badge run run-${esc(o.runState)}">${esc(o.runState)}</span>`);
    if (o.acceptanceState) badges.push(`<span class="badge acc acc-${esc(o.acceptanceState)}">${esc(o.acceptanceState)}</span>`);
    if (o.blocker) badges.push(`<span class="badge">阻塞</span>`);

    div.innerHTML = `
      <h3>${title}</h3>
      <div class="sub">
        ${badges.join('')}
        <span title="更新时间">${timeAgo(t.updatedAt ?? t.createdAt)}</span>
      </div>
    `;
    div.addEventListener('click', (e) => {
      e.stopPropagation();
      select(t.id);
    });
    fragment.appendChild(div);
  }
  nodesDiv.appendChild(fragment);
}

function timeAgo(ts) {
  if (!ts) return '';
  const t = new Date(ts);
  const delta = Date.now() - t.getTime();
  if (delta < 60e3) return '刚刚';
  if (delta < 3600e3) return `${Math.floor(delta / 60e3)} 分钟前`;
  if (delta < 86400e3) return `${Math.floor(delta / 3600e3)} 小时前`;
  return t.toLocaleDateString();
}

// ---------- Detail panel ----------

function select(id) {
  state.selectedId = id;
  renderDetail();
  renderNodes();
  // Scroll/centre selected node into view.
  const pos = state.layout?.positions?.[id];
  if (pos) {
    const cx = pos.x + pos.w / 2;
    const cy = pos.y + pos.h / 2;
    const scale = state.view.scale;
    const bw = board.clientWidth;
    const bh = board.clientHeight;
    state.view.x = bw / 2 - cx * scale;
    state.view.y = bh / 2 - cy * scale;
    renderAll();
  }
}

function deselect() {
  state.selectedId = null;
  detail.hidden = true;
  renderNodes();
}

function renderDetail() {
  if (!state.selectedId) { detail.hidden = true; return; }
  const t = state.threads.find((x) => x.id === state.selectedId);
  if (!t) { detail.hidden = true; return; }
  const o = overlayFor(t.id);
  detail.hidden = false;

  $('#detail-title').textContent = displayTitle(t);

  const meta = $('#detail-meta');
  meta.innerHTML = [
    ['ID', t.id],
    ['Session', t.sessionId],
    ['Parent', t.parentThreadId ?? '—'],
    ['Forked from', t.forkedFromId ?? '—'],
    ['Goal', o.goal ?? t.goal ?? '—'],
    ['cwd', t.cwd ?? '—'],
    ['Source', t.originator ?? t.threadSource ?? '—'],
    ['Updated', new Date(t.updatedAt ?? t.createdAt ?? 0).toLocaleString()],
  ].map(([k, v]) => `<dt>${esc(k)}</dt><dd>${esc(v)}</dd>`).join('');

  $('#detail-goal').innerHTML = o.goal || t.goal ? `<h4>Goal</h4><p>${esc(o.goal ?? t.goal)}</p>` : '';
  $('#detail-note').innerHTML = o.note ? `<h4>备注</h4><p>${esc(o.note)}</p>` : '';

  const children = (function findChildren() {
    const walk = (n) => {
      if (n.id === t.id) return n.children ?? [];
      for (const c of n.children ?? []) {
        const found = walk(c);
        if (found) return found;
      }
      return null;
    };
    for (const r of state.forest) {
      const found = walk(r);
      if (found) return found;
    }
    return [];
  })();

  $('#detail-children').innerHTML = children.length
    ? `<h4>子分支 (${children.length})</h4><ul>${children
        .map((c) => `<li><a data-id="${esc(c.id)}">${esc(displayTitle(c))}</a></li>`)
        .join('')}</ul>`
    : '';

  $('#detail-children').querySelectorAll('a[data-id]').forEach((a) => {
    a.addEventListener('click', () => select(a.dataset.id));
  });

  // Populate edit form.
  $('#edit-title').value = o.pinnedTitle ?? t.name ?? '';
  $('#edit-goal').value = o.goal ?? t.goal ?? '';
  $('#edit-kind').value = o.kind ?? (t.goal ? 'goal' : 'work');
  $('#edit-run').value = o.runState ?? '';
  $('#edit-acceptance').value = o.acceptanceState ?? '';
  $('#edit-blocker').value = o.blocker ?? '';
  $('#edit-next').value = o.nextAction ?? '';
  $('#edit-note').value = o.note ?? '';
  $('#save-msg').textContent = '';

  // Edge list for this node.
  const edgeList = $('#edge-list');
  const allEdges = Object.values(state.overlay.edges ?? {});
  const mine = allEdges.filter((e) => e.from === t.id || e.to === t.id);
  edgeList.innerHTML = mine.length
    ? mine
        .map(
          (e) =>
            `<div class="edge" data-from="${esc(e.from)}" data-to="${esc(e.to)}" data-type="${esc(e.type)}">
              <span>${e.from === t.id ? '→' : '←'} ${esc(e.type)} · ${esc(e.from === t.id ? e.to : e.from)}</span>
              <button type="button" data-remove>移除</button>
            </div>`
        )
        .join('')
    : '<div style="opacity:.5">还没有手动关系。</div>';

  edgeList.querySelectorAll('[data-remove]').forEach((btn) => {
    btn.addEventListener('click', async () => {
      const el = btn.closest('.edge');
      await fetch('/api/edge/remove', {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ from: el.dataset.from, to: el.dataset.to, type: el.dataset.type }),
      });
      await load();
      renderDetail();
    });
  });

  // Datalist for the new-edge form.
  $('#thread-ids').innerHTML = state.threads
    .map((th) => `<option value="${esc(th.id)}">${esc(displayTitle(th))}</option>`)
    .join('');
}

// ---------- Save / edge APIs ----------

$('#btn-save-node').addEventListener('click', async () => {
  if (!state.selectedId) return;
  const patch = {
    pinnedTitle: $('#edit-title').value.trim() || null,
    goal: $('#edit-goal').value.trim() || null,
    kind: $('#edit-kind').value,
    runState: $('#edit-run').value || null,
    acceptanceState: $('#edit-acceptance').value || null,
    blocker: $('#edit-blocker').value.trim() || null,
    nextAction: $('#edit-next').value.trim() || null,
    note: $('#edit-note').value.trim() || null,
  };
  // Strip null keys so the overlay only stores meaningful values.
  Object.keys(patch).forEach((k) => patch[k] == null && delete patch[k]);
  const res = await fetch('/api/node', {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ threadId: state.selectedId, patch }),
  });
  if (res.ok) {
    $('#save-msg').textContent = '已保存';
    setTimeout(() => ($('#save-msg').textContent = ''), 1800);
    await load();
    renderDetail();
  } else {
    const err = await res.json().catch(() => ({}));
    $('#save-msg').textContent = `保存失败：${err.error ?? res.status}`;
  }
});

$('#edge-form').addEventListener('submit', async (e) => {
  e.preventDefault();
  if (!state.selectedId) return;
  const to = $('#edge-to').value.trim();
  const type = $('#edge-type').value;
  const note = $('#edge-note').value.trim() || undefined;
  if (!to || !type) return;
  await fetch('/api/edge', {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ from: state.selectedId, to, type, note }),
  });
  $('#edge-to').value = '';
  $('#edge-note').value = '';
  await load();
  renderDetail();
});

$('#detail-close').addEventListener('click', deselect);

// ---------- Filters ----------

$('#search').addEventListener('input', (e) => {
  state.filters.q = e.target.value.trim();
  state.layout = null;
  renderAll();
});
$('#show-subagents').addEventListener('change', (e) => {
  state.filters.showSubagents = e.target.checked;
  state.layout = null;
  renderAll();
});
$('#show-orphans').addEventListener('change', (e) => {
  state.filters.showOrphans = e.target.checked;
  state.layout = null;
  renderAll();
});
$('#only-active').addEventListener('change', (e) => {
  state.filters.onlyActive = e.target.checked;
  state.layout = null;
  renderAll();
});
$('#btn-rescan').addEventListener('click', () => load({ force: true }));

// ---------- Pan / Zoom ----------

let drag = null;
board.addEventListener('pointerdown', (e) => {
  if (e.target.closest('.node')) return;
  drag = { x: e.clientX, y: e.clientY, startX: state.view.x, startY: state.view.y };
  board.setPointerCapture(e.pointerId);
});
board.addEventListener('pointermove', (e) => {
  if (!drag) return;
  state.view.x = drag.startX + (e.clientX - drag.x);
  state.view.y = drag.startY + (e.clientY - drag.y);
  applyTransform();
});
board.addEventListener('pointerup', () => { drag = null; });
board.addEventListener('pointercancel', () => { drag = null; });

board.addEventListener('wheel', (e) => {
  e.preventDefault();
  const rect = board.getBoundingClientRect();
  const mx = e.clientX - rect.left;
  const my = e.clientY - rect.top;
  const oldScale = state.view.scale;
  const factor = e.deltaY < 0 ? 1.12 : 0.88;
  let newScale = Math.min(2.5, Math.max(0.15, oldScale * factor));
  if (newScale === oldScale) return;
  // Zoom around cursor: worldX = (mx - view.x) / oldScale
  const wx = (mx - state.view.x) / oldScale;
  const wy = (my - state.view.y) / oldScale;
  state.view.x = mx - wx * newScale;
  state.view.y = my - wy * newScale;
  state.view.scale = newScale;
  applyTransform();
}, { passive: false });

function applyTransform() {
  nodesDiv.style.transform = `translate(${state.view.x}px, ${state.view.y}px) scale(${state.view.scale})`;
  // Keep SVG edges in sync by re-rendering whole layer (cheap for a few hundred nodes).
  renderEdges();
}

// Reset view button by double-click on empty canvas.
board.addEventListener('dblclick', (e) => {
  if (e.target.closest('.node')) return;
  fitToView();
});

function fitToView() {
  const positions = state.layout?.positions ?? {};
  const keys = Object.keys(positions);
  if (keys.length === 0) return;
  let minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity;
  for (const id of keys) {
    const p = positions[id];
    minX = Math.min(minX, p.x); minY = Math.min(minY, p.y);
    maxX = Math.max(maxX, p.x + p.w); maxY = Math.max(maxY, p.y + p.h);
  }
  const w = Math.max(1, maxX - minX);
  const h = Math.max(1, maxY - minY);
  const bw = board.clientWidth;
  const bh = board.clientHeight;
  const scale = Math.min(2, Math.max(0.15, Math.min(bw / w, bh / h) * 0.92));
  state.view.scale = scale;
  state.view.x = bw / 2 - (minX + w / 2) * scale;
  state.view.y = bh / 2 - (minY + h / 2) * scale;
  applyTransform();
}

// Center initial view on load.
const origLoad = load;
load = async (opts) => {
  await origLoad(opts);
  fitToView();
};

// ---------- Boot ----------
load();

// Keep data fresh periodically when tab is visible.
document.addEventListener('visibilitychange', () => {
  if (!document.hidden) load();
});
setInterval(() => { if (!document.hidden) load(); }, 60_000);
