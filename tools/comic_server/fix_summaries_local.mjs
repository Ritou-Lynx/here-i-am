/**
 * 补跑失败章节摘要 — 用本地 qwen2.5vl:7b (纯文本模式)
 *
 * 不带图片，只用文本 prompt，qwen2.5vl:7b 也能做摘要任务。
 * 无内容审查限制。
 */
import { readFileSync, writeFileSync, existsSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const dataDir = join(__dirname, 'data');
const chaptersDir = join(dataDir, 'chapters');
const summariesPath = join(dataDir, 'summaries.json');
const charactersPath = join(dataDir, 'characters.json');
const model = 'qwen2.5vl:7b';

function screenplayToText(chapter) {
  const lines = [];
  for (const page of chapter.screenplay) {
    if (page.error) { lines.push('[第' + page.page_num + '页] (提取失败)'); continue; }
    for (const panel of (page.panels || [])) {
      const speaker = panel.speaker || '?';
      const text = panel.text || '';
      const sfx = panel.sfx ? '（音效：' + panel.sfx + '）' : '';
      if (text || sfx) {
        lines.push('[第' + page.page_num + '页] ' + speaker + '：' + text + sfx);
      }
    }
  }
  return lines.join('\n');
}

async function callLocal(prompt) {
  const resp = await fetch('http://localhost:11434/api/generate', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ model, prompt, stream: false, format: 'json' }),
  });
  if (!resp.ok) throw new Error('HTTP ' + resp.status);
  const data = await resp.json();
  return data.response || '';
}

async function main() {
  console.log('补跑失败章节摘要 (本地 qwen2.5vl:7b)\n');

  const summaries = JSON.parse(readFileSync(summariesPath, 'utf8'));
  const characters = JSON.parse(readFileSync(charactersPath, 'utf8')).characters;
  const rosterText = characters.map(c => '- ' + c.name + '：' + (c.description || '').substring(0, 60)).join('\n');

  const failed = summaries.filter(s => !s.summary || s.summary.includes('跳过') || s.summary.includes('skip'));
  console.log('需要补跑：' + failed.length + ' 章\n');

  let success = 0;

  for (let i = 0; i < failed.length; i++) {
    const s = failed[i];
    console.log('[' + (i + 1) + '/' + failed.length + '] ' + s.chapter_title + '...');

    const chapterPath = join(chaptersDir, s.chapter_id + '.json');
    if (!existsSync(chapterPath)) {
      console.log('  ⚠ 文件不存在');
      continue;
    }
    const chapter = JSON.parse(readFileSync(chapterPath, 'utf8'));
    const chText = screenplayToText(chapter);

    const prevIdx = summaries.findIndex(x => x.chapter_id === s.chapter_id);
    const prevSummary = prevIdx > 0 && summaries[prevIdx - 1].summary && !summaries[prevIdx - 1].summary.includes('跳过')
      ? summaries[prevIdx - 1].summary : '无';

    const prompt = '你是漫画分析助手。以下是漫画"' + s.chapter_title + '"的分镜提取文本。\n\n' +
      '已知角色名册：\n' + rosterText + '\n\n' +
      '前一话摘要：' + prevSummary + '\n\n' +
      '请总结这一话的剧情，输出JSON：\n' +
      '{"summary": "2-3句话的剧情摘要", "key_events": ["关键事件1", "关键事件2"]}\n\n' +
      '本话内容：\n' + chText;

    try {
      const result = await callLocal(prompt);
      let parsed;
      try { parsed = JSON.parse(result); }
      catch {
        const m = result.match(/\{[\s\S]*\}/);
        if (m) { try { parsed = JSON.parse(m[0]); } catch { parsed = { summary: result.substring(0, 200) }; } }
        else { parsed = { summary: result.substring(0, 200) }; }
      }

      s.summary = parsed.summary || '';
      s.key_events = parsed.key_events || [];
      console.log('  ✓ ' + s.summary.substring(0, 60));
      success++;
    } catch (e) {
      console.log('  ✗ ' + e.message.substring(0, 60));
    }
  }

  writeFileSync(summariesPath, JSON.stringify(summaries, null, 2));
  console.log('\n=== 完成 ===');
  console.log('成功: ' + success + '/' + failed.length);
}

main().catch(e => { console.error('Error:', e); process.exit(1); });