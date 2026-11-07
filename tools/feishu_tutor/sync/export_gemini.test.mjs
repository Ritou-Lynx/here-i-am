import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, mkdir, writeFile, readFile, readdir, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { exportGemini, notesMarkdown, progressMarkdown, run, FILES, localToday } from './export_gemini.mjs';

const ledger = {
  pulled_at: '2026-11-02T22:30:00Z',
  records: [
    { record_id: 'r1', fields: { 知识点: '〜わけだ', 科目: '日语', 掌握度: '模糊', 错次: 3, 下次复习: '2026-11-03', 备注: '和 はず 混' } },
    { record_id: 'r2', fields: { 知识点: 'て形', 科目: '日语', 掌握度: '掌握', 错次: 0, 下次复习: '2026-12-01' } },
    { record_id: 'r3', fields: { 知识点: 'GROUP BY', 科目: '数据分析', 掌握度: '未学', 错次: 0, 下次复习: '2026-11-02' } },
  ],
  practice: [
    { fields: { 时间: '2026-11-02T08:00:00+08:00', 知识点: '〜わけだ', 科目: '日语', 结果: '错' } },
    { fields: { 时间: '2026-11-01T08:00:00+08:00', 知识点: 'て形', 科目: '日语', 结果: '对' } },
    { fields: { 时间: '2026-10-01T08:00:00+08:00', 知识点: 'て形', 科目: '日语', 结果: '对' } },
  ],
};

test('progress summary counts per subject, due points, last 7 days and weak points', () => {
  const md = progressMarkdown(ledger, '2026-11-03');
  assert.match(md, /## 日语\n\n- 知识点 2 个：掌握 1，模糊 1，未学 0\n- 今天到期复习：1 个\n- 最近 7 天练习：2 题，答对 1 题（50%）/u);
  assert.match(md, /- 〜わけだ：错 3 次，和 はず 混/u);
  assert.match(md, /## 数据分析[\s\S]*今天到期复习：1 个[\s\S]*最近 7 天练习：0 题，答对 0 题\n/u);
  assert.doesNotMatch(md, /GROUP BY：错/u);
  assert.match(progressMarkdown({ records: [] }, '2026-11-03'), /账本里还没有知识点/u);
});

test('notes merge keeps titles, links and bodies', () => {
  const md = notesMarkdown([{ title: 'N3 语法', url: 'https://x.feishu.cn/docx/a', document: { content: '内容A' } }, { title: '空', document: {} }], 'T');
  assert.match(md, /共 2 篇/u);
  assert.match(md, /# N3 语法\n\n原文：https:\/\/x\.feishu\.cn\/docx\/a\n\n内容A/u);
  assert.match(md, /# 空\n\n（空）/u);
});

test('export writes exactly three files and refuses an output inside the study directory', async () => {
  const root = await mkdtemp(path.join(tmpdir(), 'export-gemini-'));
  try {
    const study = path.join(root, 'study'), out = path.join(root, 'drive', '学习同步');
    await mkdir(path.join(study, 'state'), { recursive: true });
    await writeFile(path.join(study, 'today.md'), '﻿# 学习单 2026-11-03 日语\n', 'utf8');
    await writeFile(path.join(study, 'state', 'sources.json'), JSON.stringify({ pulled_at: 'T', sources: [] }));
    await writeFile(path.join(study, 'state', 'ledger.json'), JSON.stringify(ledger));
    const lines = [];
    assert.equal(await run(['--study', study, '--out', out], s => lines.push(s)), 0);
    assert.deepEqual(lines, ['export_ok:3']);
    assert.deepEqual((await readdir(out)).sort(), Object.values(FILES).sort());
    assert.equal(await readFile(path.join(out, FILES.today), 'utf8'), '# 学习单 2026-11-03 日语\n');
    await assert.rejects(exportGemini({ study, out: path.join(study, 'x') }), /export_out_inside_study/u);
    await assert.rejects(exportGemini({ study: path.join(root, 'none'), out }), /export_input_missing/u);
    await assert.rejects(run(['--study', study]), /usage_invalid/u);
  } finally { await rm(root, { recursive: true, force: true }); }
});

test('local day follows Asia/Shanghai', () => {
  assert.equal(localToday(new Date('2026-11-02T17:00:00Z')), '2026-11-03');
});
