/**
 * 小说文本 AI 处理：角色提取 + 章节摘要
 *
 * 读取 data/books/<id>/ 下所有章节 .txt 文件，
 * 调用 Ollama 文本模型生成:
 *   1. 角色名册 — 全书角色、别名、描述
 *   2. 章节摘要 — 每章 2-3 句剧情摘要 + 关键事件
 *
 * 用法: node generate_book_summary.mjs <book-id> [--model qwen2.5:14b]
 *
 * 输出:
 *   data/books/<id>/summaries.json — 角色名册 + 章节摘要
 */

import { readdirSync, readFileSync, writeFileSync, existsSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const dataDir = join(__dirname, 'data');
const booksDir = join(dataDir, 'books');

const bookId = process.argv[2];
if (!bookId) {
  console.error('Usage: node generate_book_summary.mjs <book-id> [--model <model>]');
  process.exit(1);
}

const modelIdx = process.argv.indexOf('--model');
const model = modelIdx >= 0 ? process.argv[modelIdx + 1] : 'qwen3:8b';

const bookDir = join(booksDir, bookId);
const metaPath = join(bookDir, 'meta.json');
const chaptersDir = join(bookDir, 'chapters');
const summariesPath = join(bookDir, 'summaries.json');

if (!existsSync(metaPath)) {
  console.error(`Book not found: ${bookId}`);
  process.exit(1);
}

const meta = JSON.parse(readFileSync(metaPath, 'utf8'));

// ── Load chapters ────────────────────────────────────────────────────────────

function loadChapters() {
  const files = readdirSync(chaptersDir)
    .filter(f => f.endsWith('.txt'))
    .sort();
  const chapters = [];
  for (const f of files) {
    const num = parseInt(f.replace('.txt', ''), 10);
    const content = readFileSync(join(chaptersDir, f), 'utf8');
    const info = meta.chapters.find(c => c.number === num);
    chapters.push({
      number: num,
      title: info?.title || `第${num}章`,
      chars: info?.chars || content.length,
      content,
    });
  }
  return chapters;
}

// ── Call Ollama ──────────────────────────────────────────────────────────────

async function callOllama(prompt, opts = {}) {
  const body = {
    model,
    prompt,
    stream: false,
    format: 'json',
    options: {
      num_ctx: opts.numCtx || 8192,
      temperature: opts.temperature ?? 0.3,
    },
    keep_alive: '30m',
  };
  const resp = await fetch('http://127.0.0.1:11434/api/generate', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  });
  if (!resp.ok) throw new Error(`Ollama HTTP ${resp.status}`);
  const data = await resp.json();
  let raw = data.response || '';
  // Try parse as JSON
  try { return JSON.parse(raw); }
  catch {
    const m = raw.match(/\{[\s\S]*\}/);
    if (m) { try { return JSON.parse(m[0]); } catch {} }
    return { raw, _parseError: true };
  }
}

// ── Phase 1: Character extraction from all chapters ──────────────────────────

async function extractCharacters(chapters) {
  console.log('=== 阶段 1：角色提取 ===');

  // Build a compact sample: first 800 chars of each chapter
  const samples = chapters.map(ch => {
    const preview = ch.content.length > 800
      ? ch.content.substring(0, 800) + '…'
      : ch.content;
    return `【${ch.title}】\n${preview}`;
  });

  // For books with many chapters, sample strategically
  let input;
  if (chapters.length <= 20) {
    input = samples.join('\n\n---\n\n');
  } else {
    // first 10 + spaced samples from rest
    const selected = samples.slice(0, 10);
    const interval = Math.max(1, Math.floor((chapters.length - 10) / 10));
    for (let i = 10; i < chapters.length; i += interval) {
      selected.push(samples[i]);
    }
    input = selected.join('\n\n---\n\n');
  }

  console.log(`  输入：${chapters.length} 章，采样 ${input.length} 字符`);
  console.log('  调用 Ollama...');

  const prompt = `你是一个小说分析助手。以下是小说《${meta.title}》各章节开头的摘录。请从中识别所有角色，生成角色名册。

要求：
1. 提取所有出现过的角色名，包括全名、昵称、称呼
2. 如果同一个人有不同称呼（如"小明""明哥""李明"），合并为一条，列出所有别名
3. 简要描述每个角色的身份和特征
4. 标注角色首次出现的大致章节（从摘录判断）

输出纯 JSON（不要在 JSON 外写其他文字）：
{
  "characters": [
    {
      "name": "主要称呼",
      "aliases": ["别名1", "别名2"],
      "description": "身份和外貌描述",
      "first_seen_chapter": 3
    }
  ]
}

以下是各章摘录：

${input}`;

  const result = await callOllama(prompt);
  const characters = result.characters || [];
  console.log(`  ✓ 提取 ${characters.length} 个角色`);
  return characters;
}

// ── Phase 2: Chapter-by-chapter summaries ────────────────────────────────────

async function generateChapterSummaries(chapters, characters) {
  console.log('\n=== 阶段 2：章节摘要 ===');

  const rosterText = characters.map(c => {
    const aliases = c.aliases?.length ? `（又名：${c.aliases.join('、')}）` : '';
    return `- ${c.name}${aliases}：${c.description || ''}`;
  }).join('\n') || '（暂无角色信息）';

  const chapterSummaries = [];

  for (let i = 0; i < chapters.length; i++) {
    const ch = chapters[i];
    const prevSummary = i > 0 ? chapterSummaries[i - 1].summary : '无';
    // Only pass the immediately preceding chapter summary — keeps ctx constant
    const prevCtx = i > 0
      ? `前一章「${chapters[i - 1].title}」摘要：${chapterSummaries[i - 1].summary}`
      : '（这是第一章）';

    // Trim chapter content if it's very long
    const chText = ch.content.length > 6000
      ? ch.content.substring(0, 6000) + '\n…（后续内容省略）'
      : ch.content;

    const prompt = `你是一个小说分析助手。以下是小说《${meta.title}》第${ch.number}章「${ch.title}」的正文。

已知角色名册：
${rosterText}

${prevCtx}

请基于以上信息和本章正文，写一个简洁的章节摘要。要求：
1. 用 2-3 句话概括这一章的核心剧情
2. 如果本章引入了重要的新角色，在 new_characters 中列出
3. 列举 1-2 个本章关键事件
4. 标注主要出场的已知角色

输出纯 JSON（不要写其他文字）：
{
  "number": ${ch.number},
  "title": "${ch.title.replace(/"/g, '\\"')}",
  "summary": "2-3句话的剧情摘要",
  "key_events": ["关键事件"],
  "main_characters": ["本章出场的主要角色"],
  "new_characters": ["本章新出现的角色（没有则为空数组）"]
}

以下是本章正文：

${chText}`;

    process.stdout.write(`  [${i + 1}/${chapters.length}] ${ch.title}…`);
    try {
      const result = await callOllama(prompt);
      chapterSummaries.push({
        number: ch.number,
        title: ch.title,
        summary: result.summary || '',
        key_events: result.key_events || [],
        main_characters: result.main_characters || [],
        new_characters: result.new_characters || [],
      });
      console.log(' ✓');
    } catch (e) {
      console.log(` ✗ (${e.message.substring(0, 60)})`);
      chapterSummaries.push({
        number: ch.number,
        title: ch.title,
        summary: '',
        key_events: [],
        main_characters: [],
        new_characters: [],
        error: e.message.substring(0, 200),
      });
    }
  }

  return chapterSummaries;
}

// ── Main ────────────────────────────────────────────────────────────────────

async function main() {
  console.log(`小说摘要生成 · 模型 ${model}\n`);
  console.log(`书名：《${meta.title}》`);
  console.log(`章节：${meta.chapter_count} 章 · 总字数：${meta.total_chars.toLocaleString()}\n`);

  const chapters = loadChapters();
  console.log(`加载 ${chapters.length} 章\n`);

  const characters = await extractCharacters(chapters);
  const chapterSummaries = await generateChapterSummaries(chapters, characters);

  const output = {
    book_id: bookId,
    book_title: meta.title,
    generated_at: Math.floor(Date.now() / 1000),
    model,
    characters,
    chapter_summaries: chapterSummaries,
  };

  writeFileSync(summariesPath, JSON.stringify(output, null, 2), 'utf8');
  console.log(`\n=== 完成 ===`);
  console.log(`角色：${characters.length} 个`);
  console.log(`摘要：${chapterSummaries.filter(s => s.summary).length}/${chapterSummaries.length} 章`);
  console.log(`输出：${summariesPath}`);
}

main().catch(e => { console.error('Error:', e); process.exit(1); });
