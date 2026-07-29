/**
 * 自动循环补跑 — 检测失败页，重跑，循环直到全部成功或连续两轮无进展
 *
 * 用法: node auto_retry.mjs
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
  const last = prev[prev.length - 1];
  return `【${last.chapter_title}】${last.summary}`;
}
function buildCurrentChapterPagesText(prevPagesScreenplay) {
  if (!prevPagesScreenplay.length) return '（这是本话第一页）';
  const lines = [];
  for (const page of prevPagesScreenplay) {
    if (page.error) { lines.push(`[第${page.page_num}页] (提取失败)`); continue; }
    for (const panel of (page.panels || [])) {
      lines.push(`[第${page.page_num}页] ${panel.speaker || '?'}：${panel.text || ''}${panel.sfx ? '（音效：' + panel.sfx + '）' : ''}`);
    }
  }
  return lines.join('\n');
}

const VISION_PROMPT = `你是一个漫画分镜分析助手。请仔细分析这张漫画图片的每一个气泡和画面元素。

## 上下文

### 全书角色名册
{ROSTER}

### 前一章摘要
{PREV}

### 当前章节前面页面的内容
{CURRENT}

## 任务
1. 默读每个对话气泡、旁白框、拟声词。
2. 判断气泡归属角色，参考角色名册用真名。
3. 描述每格画面。
4. 输出 JSON，不要输出其他文字。

## 输出格式
{{
  "page_num": {PN},
  "panels": [
    {{"panel_id":1,"speaker":"名字","text":"台词","sfx":"","panel_desc":"画面描述"}}
  ]
}}

## 要点
- 阅读顺序按画风判断。每个气泡都要提取。台词完整转录。拟声词放 sfx。
- NSFW 如实描述。无法辨认填 [不可辨认]。`;

async function visionExtract(imagePath, pageNum, roster, prev, current) {
  const imgBuf = readFileSync(imagePath);
  const b64 = imgBuf.toString('base64');
  const prompt = VISION_PROMPT
    .replace('{ROSTER}', roster)
    .replace('{PREV}', prev)
    .replace('{CURRENT}', current)
    .replace('{PN}', String(pageNum));
  try {
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 60000);
    const resp = await fetch('http://127.0.0.1:11434/api/generate', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ model: visionModel, prompt, images: [b64], stream: false, format: 'json', options: { num_ctx: 8192 }, keep_alive: '30m' }),
      signal: controller.signal,
    });
    clearTimeout(timeout);
    if (!resp.ok) return { error: `HTTP ${resp.status}` };
    const data = await resp.json();
    let raw = data.response || '';
    let parsed = null;
    try { parsed = JSON.parse(raw); }
    catch { const m = raw.match(/\{[\s\S]*\}/); if (m) { try { parsed = JSON.parse(m[0]); } catch {} } }
    return { raw, parsed };
  } catch (e) {
    return { error: e.message };
  }
}

function countFailed() {
  let total = 0;
  for (const f of readdirSync(chaptersDir).filter(f => f.endsWith('.json'))) {
    const d = JSON.parse(readFileSync(join(chaptersDir, f), 'utf8'));
    for (const s of (d.screenplay || [])) {
      if (s.error) total++;
    }
  }
  return total;
}

async function main() {
  console.log('自动循环补跑 · ' + visionModel + ' · 60秒超时\n');

  const characters = loadCharacters();
  const summaries = loadSummaries();
  const roster = buildCharacterRosterText(characters);

  let round = 0;
  let prevFailed = -1;

  while (true) {
    const failed = countFailed();
    if (failed === 0) {
      console.log('\n=== 全部完成！0 页失败 ===');
      break;
    }
    if (failed === prevFailed) {
      console.log('\n=== 连续两轮无进展（' + failed + ' 页），停止 ===');
      console.log('这些页可能需要更长超时或不同参数。');
      break;
    }
    prevFailed = failed;
    round++;
    console.log('\n========== 第 ' + round + ' 轮 · 剩余 ' + failed + ' 页 ==========\n');

    let fixed = 0;
    let stillFail = 0;

    const files = readdirSync(chaptersDir).filter(f => f.endsWith('.json'));
    for (const f of files) {
      const chapter = JSON.parse(readFileSync(join(chaptersDir, f), 'utf8'));
      const chImgDir = join(imagesDir, chapter.id);
      if (!existsSync(chImgDir)) continue;

      const imgFiles = readdirSync(chImgDir).filter(f => f.endsWith('.png') || f.endsWith('.jpg')).sort();
      const sp = chapter.screenplay || [];
      let modified = false;

      for (let i = 0; i < imgFiles.length; i++) {
        const pageNum = i + 1;
        const idx = sp.findIndex(s => s.page_num === pageNum);
        if (idx >= 0 && !sp[idx].error) continue; // already OK, skip
        if (idx < 0) continue; // no entry, skip

        const prevPages = sp.filter(s => s.page_num < pageNum && !s.error).slice(-5);
        const current = buildCurrentChapterPagesText(prevPages);
        const prev = buildPrevChaptersSummaryText(summaries, chapter.chapter_number || 0);

        process.stdout.write('  ch' + (chapter.chapter_number || '?') + ' p' + pageNum + '...');
        const vr = await visionExtract(join(chImgDir, imgFiles[i]), pageNum, roster, prev, current);

        if (vr.parsed) {
          sp[idx] = vr.parsed;
          modified = true;
          fixed++;
          process.stdout.write(' ✓ ' + (vr.parsed.panels?.length || 0) + ' panels\n');
        } else {
          stillFail++;
          process.stdout.write(' ✗ ' + (vr.error || '').substring(0, 50) + '\n');
        }
      }

      if (modified) {
        sp.sort((a, b) => (a.page_num || 0) - (b.page_num || 0));
        chapter.screenplay = sp;
        chapter.updated_at = Math.floor(Date.now() / 1000);
        writeFileSync(join(chaptersDir, f), JSON.stringify(chapter, null, 2));
      }
    }

    console.log('\n第 ' + round + ' 轮完成: 修复 ' + fixed + ' | 仍失败 ' + stillFail);
  }

  console.log('\n请重新运行 generate_summary.mjs + fix_summaries_local.mjs 更新摘要');
}

main().catch(e => { console.error('Error:', e); process.exit(1); });