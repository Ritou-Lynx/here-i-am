/**
 * 只重跑失败页 — 不重新跑成功的页
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
const visionModel = 'qwen2.5vl:7b';

function loadCharacters() {
  return JSON.parse(readFileSync(charactersPath, 'utf8')).characters || [];
}
function loadSummaries() {
  return JSON.parse(readFileSync(summariesPath, 'utf8'));
}
function loadChapters() {
  const files = readdirSync(chaptersDir).filter(f => f.endsWith('.json'));
  const chapters = [];
  for (const f of files) chapters.push(JSON.parse(readFileSync(join(chaptersDir, f), 'utf8')));
  chapters.sort((a, b) => (a.chapter_number || 0) - (b.chapter_number || 0));
  return chapters;
}
function buildCharacterRosterText(characters) {
  if (!characters.length) return '（暂无角色信息）';
  return characters.map(c => {
    const aliases = c.aliases?.length ? `（又名：${c.aliases.join('、')}）` : '';
    return `- ${c.name}${aliases}：${c.description || ''}`;
  }).join('\n');
}
function buildPrevChaptersSummaryText(summaries, currentChapterNumber) {
  const prev = summaries.filter(s => s.chapter_number < currentChapterNumber && s.summary && !s.summary.includes('跳过'));
  if (!prev.length) return '（这是第一话）';
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
      "speaker": "说话者名称（优先用角色名册中的名字）",
      "text": "气泡中的完整台词原文",
      "sfx": "拟声词/音效，没有则空字符串",
      "panel_desc": "这一格画面的简短描述"
    }}
  ]
}}

## 要点
- 漫画阅读顺序：日式从右到左、从上到下；韩式/中式从左到右。
- 每一个对话气泡都要提取。
- 台词必须完整转录。
- 拟声词放 sfx 字段。
- 说话者归属：看气泡尾巴指向谁、角色嘴型。
- NSFW 画面如实描述。
- 如果文字确实无法辨认，text 填 "[不可辨认]"。`;

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
    const timeout = setTimeout(() => controller.abort(), 60000); // 60s timeout
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
        keep_alive: '30m',
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

async function main() {
  console.log('重跑失败页 · 模型 ' + visionModel + ' · 3分钟超时\n');

  const characters = loadCharacters();
  const summaries = loadSummaries();
  const chapters = loadChapters();
  const rosterText = buildCharacterRosterText(characters);

  let totalFixed = 0;
  let totalStillFail = 0;

  for (const chapter of chapters) {
    const chImgDir = join(imagesDir, chapter.id);
    if (!existsSync(chImgDir)) continue;

    const imgFiles = readdirSync(chImgDir)
      .filter(f => f.endsWith('.png') || f.endsWith('.jpg'))
      .sort();

    const sp = chapter.screenplay || [];
    const failedPages = [];
    for (let i = 0; i < imgFiles.length; i++) {
      const pageNum = i + 1;
      const page = sp.find(s => s.page_num === pageNum);
      if (page && page.error) {
        failedPages.push({ pageNum, file: imgFiles[i] });
      }
    }

    if (failedPages.length === 0) continue;

    console.log('\n═══ ' + chapter.chapter_title + ' — ' + failedPages.length + ' 页需重跑 ═══');

    for (const { pageNum, file } of failedPages) {
      const imgPath = join(chImgDir, file);
      // Build context from successful pages before this one
      const prevPages = sp.filter(s => s.page_num < pageNum && !s.error).slice(-5);
      const currentPagesText = buildCurrentChapterPagesText(prevPages);
      const prevChaptersText = buildPrevChaptersSummaryText(summaries, chapter.chapter_number || 0);

      process.stdout.write('  页 ' + pageNum + '/' + imgFiles.length + '...');
      const vr = await visionExtractWithContext(imgPath, pageNum, {
        roster: rosterText,
        prevChapters: prevChaptersText,
        currentPages: currentPagesText,
      });

      if (vr.parsed) {
        // Update in place
        const idx = sp.findIndex(s => s.page_num === pageNum);
        if (idx >= 0) sp[idx] = vr.parsed;
        else sp.push(vr.parsed);
        const panelCount = vr.parsed.panels?.length || 0;
        process.stdout.write(' ✓ ' + panelCount + ' panels\n');
        totalFixed++;
      } else {
        process.stdout.write(' ✗ ' + (vr.error || '').substring(0, 60) + '\n');
        totalStillFail++;
      }
    }

    // Sort screenplay by page_num
    sp.sort((a, b) => (a.page_num || 0) - (b.page_num || 0));
    chapter.screenplay = sp;
    chapter.updated_at = Math.floor(Date.now() / 1000);
    writeFileSync(join(chaptersDir, chapter.id + '.json'), JSON.stringify(chapter, null, 2));
    console.log('  ✓ ' + chapter.chapter_title + ' 保存完成');
  }

  console.log('\n=== 完成 ===');
  console.log('修复: ' + totalFixed + ' | 仍失败: ' + totalStillFail);
}

main().catch(e => { console.error('Error:', e); process.exit(1); });