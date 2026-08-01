/**
 * Generate character roster + chapter summaries for an imported book.
 *
 * Reads data/books/<id>/chapters/*.txt and meta.json, calls Ollama to
 * produce summaries.json in the same book directory. The comic_server
 * /v1/book/books/:id/summaries endpoint serves this file directly.
 *
 * Usage:
 *   node generate_book_summary.mjs <bookId> [--model qwen2.5:7b] [--max-chapters 50]
 *   node generate_book_summary.mjs --all [--model qwen2.5:7b]
 */
import { existsSync, readFileSync, readdirSync, writeFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const dataDir = process.env.COMIC_SERVER_DATA_DIR || join(__dirname, 'data');
const booksDir = join(dataDir, 'books');

const modelIdx = process.argv.indexOf('--model');
const model = modelIdx >= 0 ? process.argv[modelIdx + 1] : 'qwen2.5:7b';
const maxChIdx = process.argv.indexOf('--max-chapters');
const maxChapters = maxChIdx >= 0 ? parseInt(process.argv[maxChIdx + 1], 10) : 80;

// ── Ollama ──────────────────────────────────────────────────────────────────

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
  const raw = data.response || '';
  try { return JSON.parse(raw); } catch {
    const m = raw.match(/\{[\s\S]*\}/);
    if (m) { try { return JSON.parse(m[0]); } catch {} }
    return { raw, _parseError: true };
  }
}

// ── Load book ───────────────────────────────────────────────────────────────

function loadBook(bookId) {
  const bDir = join(booksDir, bookId);
  const metaPath = join(bDir, 'meta.json');
  if (!existsSync(metaPath)) return null;
  const meta = JSON.parse(readFileSync(metaPath, 'utf8'));
  const chDir = join(bDir, 'chapters');
  const chapters = [];
  for (const ch of (meta.chapters || [])) {
    const fp = join(chDir, ch.file);
    if (!existsSync(fp)) continue;
    chapters.push({
      number: ch.number,
      title: ch.title,
      chars: ch.chars,
      content: readFileSync(fp, 'utf8'),
    });
  }
  chapters.sort((a, b) => a.number - b.number);
  return { meta, bDir, chapters };
}

function listBookIds() {
  if (!existsSync(booksDir)) return [];
  return readdirSync(booksDir, { withFileTypes: true })
    .filter((d) => d.isDirectory())
    .map((d) => d.name);
}

// ── Truncate chapter for context window ─────────────────────────────────────

function truncate(text, maxChars = 6000) {
  if (text.length <= maxChars) return text;
  const head = text.substring(0, Math.floor(maxChars * 0.7));
  const tail = text.substring(text.length - Math.floor(maxChars * 0.2));
  return `${head}\n\n……（中间省略）……\n\n${tail}`;
}

// ── Generate character roster ───────────────────────────────────────────────

async function generateRoster(book) {
  console.log('=== 生成角色名册 ===');
  const sample = book.chapters.slice(0, Math.min(5, book.chapters.length));
  const text = sample.map((ch) => `【${ch.title}】\n${truncate(ch.content, 3000)}`).join('\n\n---\n\n');

  const prompt = `你是一个小说分析助手。只输出JSON，不要输出其他文字。

以下是小说《${book.meta.title}》前几章的内容。请从中识别主要角色，生成角色名册。

要求：
1. 提取所有重要角色（主角、配角、反派）
2. 如果同一个人有不同称呼，合并为一条，列出别名
3. 简要描述每个角色的身份和特征

输出 JSON 格式：
{
  "characters": [
    {"name": "主要称呼", "aliases": ["别名1"], "description": "身份和特征描述"}
  ]
}

以下是小说内容：

${text}`;

  console.log(`  采样 ${sample.length} 章，${text.length} 字符`);
  const parsed = await callOllama(prompt, { numCtx: 16384 });
  const characters = parsed.characters || [];
  console.log(`  ✓ ${characters.length} 个角色`);
  return { characters };
}

// ── Generate chapter summaries ──────────────────────────────────────────────

async function generateSummaries(book, roster) {
  console.log('\n=== 生成章节摘要 ===');
  const rosterText = (roster.characters || [])
    .map((c) => `- ${c.name}${c.aliases?.length ? `（${c.aliases.join('、')}）` : ''}：${c.description || ''}`)
    .join('\n');

  const chapters = book.chapters.slice(0, maxChapters);
  const summaries = [];

  for (let i = 0; i < chapters.length; i++) {
    const ch = chapters[i];
    const prevSummary = i > 0 ? summaries[i - 1].summary : '（第一章，无前文）';
    const chText = truncate(ch.content, 5000);

    const prompt = `你是一个小说分析助手。只输出JSON，不要输出其他文字。

小说：《${book.meta.title}》
当前章节：${ch.title}（第 ${ch.number} 章）

已知角色：
${rosterText || '（未知）'}

前一章摘要：${prevSummary}

请总结本章剧情。要求：
1. 用角色名册中的称呼
2. 3-5句话概括本章发生了什么
3. 标注重要转折或新角色登场

输出 JSON：
{"summary": "3-5句话摘要", "key_events": ["事件1", "事件2"]}

本章内容：

${chText}`;

    process.stdout.write(`  [${i + 1}/${chapters.length}] ${ch.title}...`);
    try {
      const parsed = await callOllama(prompt);
      summaries.push({
        number: ch.number,
        title: ch.title,
        summary: parsed.summary || '',
        key_events: parsed.key_events || [],
      });
      console.log(' ✓');
    } catch (e) {
      console.log(` ✗ (${e.message.substring(0, 60)})`);
      summaries.push({ number: ch.number, title: ch.title, summary: '', key_events: [], error: e.message.substring(0, 200) });
    }
  }
  return summaries;
}

// ── Main ────────────────────────────────────────────────────────────────────

async function processBook(bookId) {
  const book = loadBook(bookId);
  if (!book) { console.error(`Book ${bookId} not found`); return; }

  const outPath = join(book.bDir, 'summaries.json');
  if (existsSync(outPath)) {
    console.log(`[${book.meta.title}] summaries.json already exists, skipping. Delete it to regenerate.`);
    return;
  }

  console.log(`\n《${book.meta.title}》 ${book.chapters.length} 章 · ${book.meta.total_chars} 字\n`);

  const roster = await generateRoster(book);
  const chapterSummaries = await generateSummaries(book, roster);

  const output = {
    book_id: bookId,
    title: book.meta.title,
    characters: roster.characters,
    chapter_summaries: chapterSummaries,
    generated_at: new Date().toISOString(),
    model,
  };
  writeFileSync(outPath, JSON.stringify(output, null, 2), 'utf8');
  console.log(`\n✓ 保存到 ${outPath}`);
  console.log(`  角色：${roster.characters.length} · 摘要：${chapterSummaries.length} 章`);
}

async function main() {
  console.log(`小说摘要生成器 · Ollama ${model}\n`);

  const allIdx = process.argv.indexOf('--all');
  let ids;
  if (allIdx >= 0) {
    ids = listBookIds();
    console.log(`找到 ${ids.length} 本书\n`);
  } else {
    const bookId = process.argv[2];
    if (!bookId || bookId.startsWith('--')) {
      console.error('Usage: node generate_book_summary.mjs <bookId> [--model qwen2.5:7b]');
      console.error('       node generate_book_summary.mjs --all');
      process.exit(1);
    }
    ids = [bookId];
  }

  for (const id of ids) {
    await processBook(id);
  }
}

main().catch((e) => { console.error('Error:', e); process.exit(1); });
