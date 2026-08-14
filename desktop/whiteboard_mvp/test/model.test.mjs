import test from 'node:test';
import assert from 'node:assert/strict';

import {
  createBoard,
  createInitialSnapshot,
  filterCards,
  moveBoardItem,
  normalizeSnapshot,
  placeCard,
  removeBoardItem,
  updateViewport,
} from '../src/model.mjs';

test('normalizes invalid snapshots back to a usable seed', () => {
  const snapshot = normalizeSnapshot({ schemaVersion: 999 });
  assert.equal(snapshot.schemaVersion, 1);
  assert.ok(snapshot.cards.length >= 8);
  assert.ok(snapshot.boards.length >= 2);
});

test('creates a board and places one stable card appearance', () => {
  const initial = createInitialSnapshot();
  const created = createBoard(initial, '研究白板', {
    boardId: 'board_test',
    now: '2026-08-14T12:00:00.000Z',
  });
  const placed = placeCard(created.snapshot, {
    boardId: created.boardId,
    cardId: 'card_note_spine',
    itemId: 'item_test',
    x: 140.4,
    y: 88.8,
    now: '2026-08-14T12:01:00.000Z',
  });

  assert.equal(placed.item.itemId, 'item_test');
  assert.equal(placed.item.x, 140);
  assert.equal(placed.item.y, 89);
  assert.equal(placed.snapshot.boardItems.at(-1).cardId, 'card_note_spine');
  assert.equal(initial.boards.length, 2, 'source snapshot is not mutated');
});

test('moves, removes and restores viewport without changing card identity', () => {
  const initial = createInitialSnapshot();
  const moved = moveBoardItem(initial, 'item_spine', { x: 333, y: 222 }, {
    now: '2026-08-14T12:02:00.000Z',
  });
  assert.equal(moved.boardItems.find((item) => item.itemId === 'item_spine').x, 333);
  assert.ok(moved.cards.some((card) => card.cardId === 'card_note_spine'));

  const resized = moveBoardItem(moved, 'item_spine', { width: 412, height: 288 }, {
    now: '2026-08-14T12:02:30.000Z',
  });
  const resizedItem = resized.boardItems.find((item) => item.itemId === 'item_spine');
  assert.equal(resizedItem.x, 333, 'resize preserves the existing x position');
  assert.equal(resizedItem.y, 222, 'resize preserves the existing y position');
  assert.equal(resizedItem.width, 412);
  assert.equal(resizedItem.height, 288);

  const withViewport = updateViewport(resized, 'board_whiteboard_mvp', {
    x: -40,
    y: 120,
    zoom: 9,
  });
  assert.equal(withViewport.boards[0].viewport.zoom, 2.2);

  const removed = removeBoardItem(withViewport, 'item_spine');
  assert.ok(!removed.boardItems.some((item) => item.itemId === 'item_spine'));
  assert.ok(removed.cards.some((card) => card.cardId === 'card_note_spine'));
});

test('filters one library by type, source, title, body and tags', () => {
  const { cards } = createInitialSnapshot();
  assert.equal(filterCards(cards, '', 'image').length, 2);
  assert.equal(filterCards(cards, 'tldraw', 'all').length, 1);
  assert.equal(filterCards(cards, '财政', 'all').length, 1);
  assert.equal(filterCards(cards, '不存在', 'all').length, 0);
});
