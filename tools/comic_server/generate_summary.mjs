/**
 * 阶段 2: 从粗提取结果生成角色名册 + 全书章节摘要
 *
 * 读取 data/chapters/*.json 的 screenplay 字段，拼接后发给 Ollama，
 * 生成:
 *   1. 角色名册 (characters.json) — {name, description, aliases}
 *   2. 章节摘要 (summaries.json) — {chapterId, chapterTitle, summary}
 *
 * 用法: node generate_summary.mjs [--model qwen3:8b]
 */
import { readdirSync, readFileSync, writeFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const dataDir = join(__dirname, 'data');
const chaptersDir = join(dataDir, 'chapters');

const modelIdx = process.argv.indexOf('--model');
const model = modelIdx >= 0 ? process.argv[modelIdx + 1] : 'qwen3:8b';

// ── Load all chapters ─────────────────────────────────────────────────────
function loadChapters() {
  const files = readdirSync(chaptersDir).filter(f => f.endsWith('.json'));
  const chapters = [];
  for (const f of files) {
    const raw = JSON.parse(readFileSync(join(chaptersDir, f), 'utf8'));
    if (!raw.screenplay || raw.screenplay.length === 0) continue;
    chapters.push({
      id: raw.id,
      chapterNumber: raw.chapter_number,
      chapterTitle: raw.chapter_title,
      screenplay: raw.screenplay,
    });
  }
  chapters.sort((a, b) => a.chapterNumber - b.chapterNumber);
  return chapters;
}

// ── Flatten screenplay to readable text ───────────────────────────────────
function screenplayToText(chapter) {
  const lines = [];
  for (const page of chapter.screenplay) {
    if (page.error) {
      lines.push(`[第${page.page_num}页] (提取失败)`);
      continue;
    }
    for (const panel of (page.panels || [])) {
      const speaker = panel.speaker || '?';
      const text = panel.text || '';
      const sfx = panel.sfx ? `（音效：${panel.sfx}）` : '';
      const desc = panel.panel_desc ? `  画面：${panel.panel_desc}` : '';
      if (text || sfx || desc) {
        lines.push(`[第${page.page_num}页] ${speaker}：${text}${sfx}${desc}`);
      }
    }
  }
  return lines.join('\n');
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
  try { return JSON.parse(raw); }
  catch {
    const m = raw.match(/\{[\s\S]*\}/);
    if (m) { try { return JSON.parse(m[0]); } catch {} }
    return { raw, _parseError: true };
  }
}

// ── Generate character roster ───────────────────────────────────────────────
async function generateCharacterRoster(chapters) {
  console.log('=== 生成角色名册 ===');
  console.log(`  输入：${chapters.length} 章`);

  const allText = chapters.map(ch => {
    return `【${ch.chapterTitle}】\n${screenplayToText(ch)}`;
  }).join('\n\n---\n\n');

  const prompt = `你是一个漫画分析助手。只输出JSON，不要输出其他文字。

以下是整部漫画的分镜提取文本。请从中识别所有角色，生成角色名册。

要求：
1. 提取所有出现过的角色名（包括"角色A""黑发男"等临时称呼）
2. 如果同一个人有不同的称呼，合并为一条，列出所有别名
3. 如果能推断出角色的真名，标注出来
4. 简要描述每个角色的外貌特征

输出 JSON 格式：
{
  "characters": [
    {
      "name": "主要称呼（优先用真名，没有就用最常出现的称呼）",
      "aliases": ["角色A", "黑发男"],
      "description": "外貌和身份描述"
    }
  ]
}

以下是漫画内容：

${allText}`;

  console.log(`  内容长度：${allText.length} 字符`);
  console.log(`  调用 Ollama (${model})...`);

  const parsed = await callOllama(prompt, { numCtx: 16384 });
  const characters = parsed.characters || [];

  const outputPath = join(dataDir, 'characters.json');
  writeFileSync(outputPath, JSON.stringify(parsed, null, 2));
  console.log(`  ✓ 生成 ${characters.length} 个角色`);
  console.log(`  ✓ 保存到 ${outputPath}`);
  return parsed;
}

// ── Generate chapter summaries ────────────────────────────────────────────
async function generateChapterSummaries(chapters, roster) {
  console.log('\n=== 生成章节摘要 ===');

  const rosterText = roster.characters?.map(c => {
    return `- ${c.name}${c.aliases?.length ? `（又名：${c.aliases.join('、')}）` : ''}：${c.description || ''}`;
  }).join('\n') || '';

  const summaries = [];

  for (let i = 0; i < chapters.length; i++) {
    const ch = chapters[i];
    const prevSummary = i > 0 ? summaries[i - 1].summary : '无';
    const chText = screenplayToText(ch);

    const prompt = `你是一个漫画分析助手。只输出JSON，不要输出其他文字。

以下是漫画"${ch.chapterTitle}"的分镜提取文本。

已知角色名册：
${rosterText}

前一话摘要：${prevSummary}

请基于以上信息，总结这一话的剧情。要求：
1. 用角色名册中的主要称呼（不用"角色A"等临时称呼）
2. 2-3句话概括这一话发生了什么
3. 标注重要情节转折

输出 JSON 格式：
{
  "chapter_id": "${ch.id}",
  "chapter_title": "${ch.chapterTitle}",
  "summary": "2-3句话的剧情摘要",
  "key_events": ["关键事件1", "关键事件2"]
}

以下是本话内容：

${chText}`;

    process.stdout.write(`  [${i + 1}/${chapters.length}] ${ch.chapterTitle}...`);
    try {
      const parsed = await callOllama(prompt);

      summaries.push({
        chapter_id: ch.id,
        chapter_title: ch.chapterTitle,
        chapter_number: ch.chapterNumber,
        summary: parsed.summary || '',
        key_events: parsed.key_events || [],
      });
      console.log(' ✓');
    } catch (e) {
      console.log(` ✗ (${e.message.substring(0, 60)})`);
      summaries.push({
        chapter_id: ch.id,
        chapter_title: ch.chapterTitle,
        chapter_number: ch.chapterNumber,
        summary: '',
        key_events: [],
        error: e.message.substring(0, 200),
      });
    }
  }

  const outputPath = join(dataDir, 'summaries.json');
  writeFileSync(outputPath, JSON.stringify(summaries, null, 2));
  console.log(`  ✓ 保存到 ${outputPath}`);
  return summaries;
}

// ── Main ────────────────────────────────────────────────────────────────────
async function main() {
  console.log(`漫画摘要生成器 · Ollama ${model}\n`);

  const chapters = loadChapters();
  console.log(`加载 ${chapters.length} 章\n`);

  const roster = await generateCharacterRoster(chapters);
  const summaries = await generateChapterSummaries(chapters, roster);

  console.log('\n=== 完成 ===');
  console.log(`角色名册：${roster.characters?.length || 0} 个角色`);
  console.log(`章节摘要：${summaries.length} 章`);
}

main().catch(e => { console.error('Error:', e); process.exit(1); });
