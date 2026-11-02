import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, writeFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { practiceLink, run, BASE, MAX_LINK } from '../study/practice_link.mjs';

test('practice link encodes Chinese, Japanese and newlines and round-trips', () => {
  const prompt = '你是我的日语教练。\n1. 〜わけだ — 考法：情境选择\nSELECT * FROM t WHERE a = "x" & b;';
  const link = practiceLink(`﻿${prompt.replaceAll('\n', '\r\n')}\n\n`);
  assert.ok(link.startsWith(BASE));
  assert.equal(decodeURIComponent(link.slice(BASE.length)), prompt);
  assert.ok(!/[\s&#"]/u.test(link.slice(BASE.length)));
});

test('practice link refuses empty and over-long prompts', () => {
  assert.throws(() => practiceLink('  \n '), /prompt_missing/u);
  assert.throws(() => practiceLink('a\0b'), /prompt_missing/u);
  assert.throws(() => practiceLink('练'.repeat(Math.ceil(MAX_LINK / 9) + 1)), /prompt_too_long/u);
  assert.ok(practiceLink('练'.repeat(Math.floor((MAX_LINK - BASE.length) / 9))).length <= MAX_LINK);
});

test('practice link CLI reads one file and prints only the link', async () => {
  const dir = await mkdtemp(path.join(tmpdir(), 'practice-link-'));
  try {
    const file = path.join(dir, '英语.txt');
    await writeFile(file, 'Give me 5 interactive questions.', 'utf8');
    const out = [];
    assert.equal(await run([file], s => out.push(s)), 0);
    assert.deepEqual(out, [BASE + encodeURIComponent('Give me 5 interactive questions.')]);
    await assert.rejects(run([]), /usage_invalid/u);
    await assert.rejects(run([path.join(dir, 'missing.txt')]), /prompt_missing/u);
  } finally { await rm(dir, { recursive: true, force: true }); }
});
