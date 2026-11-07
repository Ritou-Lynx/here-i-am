// Writes three Markdown files for Gemini into a Google Drive for desktop folder:
// today's study sheet, the pulled Feishu notes, and a progress summary.
// An Apps Script in the user's Google account copies them into fixed Google Docs,
// which Gemini Notebook keeps in sync. Local only: no network, no Feishu calls.
// Usage: node export_gemini.mjs --study <学习目录> --out <Drive 同步文件夹>
import { readFile, writeFile, rename, mkdir } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

export const FILES = Object.freeze({ today: '今日学习单.md', notes: '学习笔记合集.md', progress: '学习进度.md' });
const MAX_BYTES = 900_000; // Apps Script / Docs stay comfortable well under this.

async function readJson(file) {
  try { return JSON.parse((await readFile(file, 'utf8')).replace(/^﻿/u, '')); } catch { return null; }
}
async function readText(file) {
  try { return (await readFile(file, 'utf8')).replace(/^﻿/u, ''); } catch { return null; }
}
const clip = text => Buffer.byteLength(text) <= MAX_BYTES ? text
  : `${Buffer.from(text).subarray(0, MAX_BYTES).toString('utf8').replace(/�$/u, '')}\n\n（内容过长，已截断）\n`;

export function notesMarkdown(sources, pulledAt) {
  const list = Array.isArray(sources) ? sources : [];
  const parts = [`# 学习笔记合集\n\n来自飞书，最近同步：${pulledAt ?? '未知'}。共 ${list.length} 篇。\n`];
  for (const s of list) {
    if (!s || typeof s.title !== 'string') continue;
    const body = typeof s.document?.content === 'string' ? s.document.content.trim() : '';
    parts.push(`\n---\n\n# ${s.title}\n${s.url ? `\n原文：${s.url}\n` : ''}\n${body || '（空）'}\n`);
  }
  return parts.join('');
}

function addDays(date, n) {
  const d = new Date(`${date}T00:00:00Z`); d.setUTCDate(d.getUTCDate() + n); return d.toISOString().slice(0, 10);
}

export function progressMarkdown(ledger, today) {
  const rows = (ledger?.records ?? []).map(r => r?.fields).filter(f => f && typeof f.知识点 === 'string');
  const practice = (ledger?.practice ?? []).map(r => r?.fields).filter(Boolean);
  const subjects = [...new Set(rows.map(f => f.科目).filter(Boolean))];
  const weekStart = addDays(today, -6);
  const out = [`# 学习进度\n\n统计日：${today}。数据来自飞书学习账本，最近同步：${ledger?.pulled_at ?? '未知'}。\n`];
  for (const subject of subjects) {
    const mine = rows.filter(f => f.科目 === subject);
    const count = v => mine.filter(f => f.掌握度 === v).length;
    const due = mine.filter(f => typeof f.下次复习 === 'string' && f.下次复习 <= today).length;
    const week = practice.filter(p => p.科目 === subject && typeof p.时间 === 'string' && p.时间.slice(0, 10) >= weekStart);
    const right = week.filter(p => p.结果 === '对').length;
    const weak = mine.filter(f => Number(f.错次) > 0).sort((a, b) => Number(b.错次) - Number(a.错次)).slice(0, 10);
    out.push(`\n## ${subject}\n\n- 知识点 ${mine.length} 个：掌握 ${count('掌握')}，模糊 ${count('模糊')}，未学 ${count('未学')}\n- 今天到期复习：${due} 个\n- 最近 7 天练习：${week.length} 题，答对 ${right} 题${week.length ? `（${Math.round(right * 100 / week.length)}%）` : ''}\n`);
    if (weak.length) {
      out.push('\n薄弱点（错次最多）：\n\n');
      for (const f of weak) out.push(`- ${f.知识点}：错 ${f.错次} 次${f.备注 ? `，${String(f.备注).replace(/\s+/gu, ' ').slice(0, 80)}` : ''}\n`);
    }
  }
  if (!subjects.length) out.push('\n账本里还没有知识点。\n');
  return out.join('');
}

async function writeAtomic(dir, name, text) {
  const file = path.join(dir, name), tmp = path.join(dir, `.${name}.tmp`);
  await writeFile(tmp, clip(text), 'utf8');
  await rename(tmp, file);
}

export async function exportGemini({ study, out, today = localToday() }) {
  if (!study || !out) throw new Error('usage_invalid');
  const studyAbs = path.resolve(study), outAbs = path.resolve(out);
  const rel = path.relative(studyAbs, outAbs);
  if (rel === '' || (!rel.startsWith('..') && !path.isAbsolute(rel))) throw new Error('export_out_inside_study');
  await mkdir(outAbs, { recursive: true });
  const sheet = await readText(path.join(studyAbs, 'today.md'));
  const sources = await readJson(path.join(studyAbs, 'state', 'sources.json'));
  const ledger = await readJson(path.join(studyAbs, 'state', 'ledger.json'));
  if (sheet === null || sources === null || ledger === null) throw new Error('export_input_missing');
  await writeAtomic(outAbs, FILES.today, sheet);
  await writeAtomic(outAbs, FILES.notes, notesMarkdown(sources.sources, sources.pulled_at));
  await writeAtomic(outAbs, FILES.progress, progressMarkdown(ledger, today));
  return Object.values(FILES);
}

export function localToday(now = new Date(), timeZone = 'Asia/Shanghai') {
  return new Intl.DateTimeFormat('en-CA', { timeZone, year: 'numeric', month: '2-digit', day: '2-digit' }).format(now);
}

export async function run(argv, output = console.log) {
  const args = {};
  for (let i = 0; i < argv.length; i += 2) {
    if (!['--study', '--out'].includes(argv[i]) || !argv[i + 1] || args[argv[i]]) throw new Error('usage_invalid');
    args[argv[i]] = argv[i + 1];
  }
  const written = await exportGemini({ study: args['--study'], out: args['--out'] });
  output(`export_ok:${written.length}`);
  return 0;
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try { process.exitCode = await run(process.argv.slice(2)); }
  catch (error) { console.error(/^[a-z_]+$/u.test(error.message) ? error.message : 'export_error'); process.exitCode = 1; }
}
