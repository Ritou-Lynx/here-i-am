/**
 * 阶段 3: 带上下文的 Vision 精提取
 *
 * 读取 characters.json + summaries.json 作为上下文，
 * 对每一页用 qwen3-vl:8b 重新提取 screenplay，
 * 覆盖原来的粗提取结果。
 *
 * 上下文注入：
 *   1. 全书角色名册（角色名+别名+描述）
 *   2. 前面所有章节的摘要（剧情进展）
 *   3. 当前章节内前面所有页的 screenplay（章内连贯）
 *
 * 用法: node reextract.mjs
 */
import { readdirSync, readFileSync, writeFileSync, existsSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const dataDir = join(__dirname, 'data');
const chaptersDir = join(dataDir, 'chapters');
const imagesDir = join(dataDir, 'images');
const charactersPath = join(dataDir, 'characters.json');
const summariesPath = join(dataDir, 'summaries.json');

const visionModel = process.argv.includes('--model')
  ? process.argv[process.argv.indexOf('--model') + 1]
  : 'qwen2.5vl:7b';

// ── Load context ────────────────────────────────────────────────────────────
function loadCharacters() {
  if (!existsSync(charactersPath)) { console.error('characters.json not found, run generate_summary.mjs first'); process.exit(1); }
  const data = JSON.parse(readFileSync(charactersPath, 'utf8'));
  return data.characters || [];
}

function loadSummaries() {
  if (!existsSync(summariesPath)) { console.error('summaries.json not found'); process.exit(1); }
  return JSON.parse(readFileSync(summariesPath, 'utf8'));
}

function loadChapters() {
  const files = readdirSync(chaptersDir).filter(f => f.endsWith('.json'));
  const chapters = [];
  for (const f of files) {
    chapters.push(JSON.parse(readFileSync(join(chaptersDir, f), 'utf8')));
  }
  chapters.sort((a, b) => (a.chapter_number || 0) - (b.chapter_number || 0));
  return chapters;
}

// ── Build context string ───────────────────────────────────────────────────
function buildCharacterRosterText(characters) {
  if (!characters.length) return '（暂无角色信息）';
  const lines = characters.map(c => {
    const aliases = c.aliases?.length ? `（又名：${c.aliases.join('、')}）` : '';
    return `- ${c.name}${aliases}：${c.description || ''}`;
  });
  return lines.join('\n');
}

function buildPrevChaptersSummaryText(summaries, currentChapterNumber) {
  const prev = summaries.filter(s => s.chapter_number < currentChapterNumber && s.summary && !s.summary.includes('跳过'));
  if (!prev.length) return '（这是第一话）';
  // Only pass the immediately preceding chapter summary — keeps context
  // size constant regardless of how many chapters have been processed.
  const lastChapter = prev[prev.length - 1];
  return `【${lastChapter.chapter_title}】${lastChapter.summary}`;
}

function buildCurrentChapterPagesText(prevPagesScreenplay) {
  if (!prevPagesScreenplay.length) return '（这是本话第一页）';
  const lines = [];
  for (const page of prevPagesScreenplay) {
    if (page.error) { lines.push(`[第${page.page_num}页] (提取失败)`); continue; }
    for (const panel of (page.panels || [])) {
      const speaker = panel.speaker || '?';
      const text = panel.text || '';
      const sfx = panel.sfx ? `（音效：${panel.sfx}）` : '';
      lines.push(`[第${page.page_num}页] ${speaker}：${text}${sfx}`);
    }
  }
  return lines.join('\n');
}

// ── Vision prompt with context ───────────────────────────────────────────────
const VISION_PROMPT_TEMPLATE = `你是一个漫画分镜分析助手。请仔细分析这张漫画图片的每一个气泡和画面元素。

## 上下文

### 全书角色名册
{CHARACTER_ROSTER}

### 前面所有章节的剧情进展
{PREV_CHAPTERS_SUMMARY}

### 当前章节前面页面的内容
{CURRENT_CHAPTER_PAGES}

## 任务

1. 先在心里默读图中每一个对话气泡、旁白框、拟声词的文字内容，不要遗漏。
2. 判断每个气泡属于哪个角色。请参考角色名册，如果画面中的人符合某角色的外貌描述，用角色名册中的名字，不要用"角色A""黑发男"等临时称呼。
3. 描述每一格画面的内容（人物动作、表情、场景、氛围）。
4. 最后输出一个 JSON 对象，不要在 JSON 前后输出其他文字。

## 输出格式

{{
  "page_num": {PAGE_NUM},
  "panels": [
    {{
      "panel_id": 1,
      "speaker": "说话者名称（优先用角色名册中的名字，新角色用外貌描述如'金发女'）",
      "text": "气泡中的完整台词原文，逐字转录，不要省略不要截断",
      "sfx": "如果有拟声词/音效，写在这里；没有则留空字符串",
      "panel_desc": "这一格画面的简短描述（1-2句，包含人物动作、表情、场景）"
    }}
  ]
}}

## 仔细阅读的要点

- 漫画阅读顺序：日式从右到左、从上到下；韩式/中式从左到右。请根据画风判断。
- 每一个对话气泡都要提取，哪怕很小。一个大格子里可能有多个气泡，都要列出。
- 台词必须完整转录。如果气泡里的文字被气泡边缘切断，根据上下文补全。
- 拟声词/音效字（通常是没有气泡尾巴的大字、艺术字）放在 sfx 字段，不要混进 text。
- 说话者归属：看气泡尾巴指向谁、角色嘴型是否张开、剧情逻辑。参考角色名册。
- NSFW 画面如实描述，不要回避或道德评判。
- 如果文字确实无法辨认（严重模糊、过小、艺术化过度），text 填 "[不可辨认]"。`;

// ── Ollama Vision call (generate API — works for qwen2.5vl:7b) ─────────────
async function visionExtractWithContext(imagePath, pageNum, context) {
  const imgBuf = readFileSync(imagePath);
  const b64 = imgBuf.toString('base64');
  const prompt = VISION_PROMPT_TEMPLATE
    .replace('{CHARACTER_ROSTER}', context.roster)
    .replace('{PREV_CHAPTERS_SUMMARY}', context.prevChapters)
    .replace('{CURRENT_CHAPTER_PAGES}', context.currentPages)
    .replace('{PAGE_NUM}', String(pageNum));

  try {
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 120000); // 2 min timeout
    const resp = await fetch('http://127.0.0.1:11434/api/generate', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        model: visionModel,
        prompt,
        images: [b64],
        stream: false,
        format: 'json',
        options: { num_ctx: 8192 },
        keep_alive: '30m', // Keep model in GPU memory between pages
      }),
      signal: controller.signal,
    });
    clearTimeout(timeout);
    if (!resp.ok) return { error: `HTTP ${resp.status}` };
    const data = await resp.json();
    let raw = data.response || '';

    let parsed = null;
    try { parsed = JSON.parse(raw); }
    catch {
      const m = raw.match(/\{[\s\S]*\}/);
      if (m) { try { parsed = JSON.parse(m[0]); } catch {} }
    }
    return { raw, parsed };
  } catch (e) {
    return { error: e.message };
  }
}

// ── Main ─────────────────────────────────────────────────────────────────────
async function main() {
  console.log(`Vision 精提取 · 模型 ${visionModel} · 带上下文\n`);

  const characters = loadCharacters();
  const summaries = loadSummaries();
  const chapters = loadChapters();
  console.log(`角色: ${characters.length} 个 | 章节: ${chapters.length} 章\n`);

  const rosterText = buildCharacterRosterText(characters);

  let totalPages = 0;
  let totalOk = 0;
  let totalFail = 0;

  for (let ci = 0; ci < chapters.length; ci++) {
    const chapter = chapters[ci];
    const chapterNum = chapter.chapter_number || 0;
    const prevChaptersText = buildPrevChaptersSummaryText(summaries, chapterNum);

    console.log(`\n═══ ${chapter.chapter_title} (${chapter.id}) — ${chapter.page_count} 页 ═══`);

    // Find image files
    const chImgDir = join(imagesDir, chapter.id);
    if (!existsSync(chImgDir)) {
      console.log(`  ⚠ 图片目录不存在，跳过`);
      continue;
    }

    const imgFiles = readdirSync(chImgDir)
      .filter(f => f.endsWith('.png') || f.endsWith('.jpg'))
      .sort();

    const newScreenplay = [];
    let chapterPages = []; // accumulated pages for context

    for (let pi = 0; pi < imgFiles.length; pi++) {
      const imgFile = imgFiles[pi];
      const pageNum = pi + 1;
      const imgPath = join(chImgDir, imgFile);
      // Only pass the last 5 pages as in-chapter context to avoid context overflow
      const recentPages = chapterPages.slice(-5);
      const currentPagesText = buildCurrentChapterPagesText(recentPages);

      const context = {
        roster: rosterText,
        prevChapters: prevChaptersText,
        currentPages: currentPagesText,
      };

      process.stdout.write(`  页 ${pageNum}/${imgFiles.length}…`);
      const vr = await visionExtractWithContext(imgPath, pageNum, context);

      if (vr.parsed) {
        newScreenplay.push(vr.parsed);
        chapterPages.push(vr.parsed);
        const panelCount = vr.parsed.panels?.length || 0;
        process.stdout.write(` ✓ ${panelCount} panels\n`);
        totalOk++;
      } else {
        newScreenplay.push({ page_num: pageNum, panels: [], error: vr.error || 'parse failed' });
        chapterPages.push({ page_num: pageNum, panels: [], error: vr.error || 'parse failed' });
        process.stdout.write(` ✗\n`);
        totalFail++;
      }
      totalPages++;

      // Small delay between pages
      await new Promise(r => setTimeout(r, 300));
    }

    // Update chapter JSON with new screenplay
    chapter.screenplay = newScreenplay;
    chapter.ocr_model = visionModel;
    chapter.updated_at = Math.floor(Date.now() / 1000);
    writeFileSync(join(chaptersDir, `${chapter.id}.json`), JSON.stringify(chapter, null, 2));
    console.log(`  ✓ ${chapter.chapter_title} 保存完成 (${newScreenplay.filter(s => !s.error).length}/${newScreenplay.length} 成功)`);
  }

  console.log(`\n=== 完成 ===`);
  console.log(`总页数: ${totalPages} | 成功: ${totalOk} | 失败: ${totalFail}`);
  console.log(`请重新运行 generate_summary.mjs 更新摘要`);
}

main().catch(e => { console.error('Error:', e); process.exit(1); });