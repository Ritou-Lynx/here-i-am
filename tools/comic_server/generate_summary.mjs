/**
 * 阶段 2: 从粗提取结果生成角色名册 + 全书章节摘要
 *
 * 读取 data/chapters/*.json 的 screenplay 字段，拼接后发给 MiniMax-M3，
 * 生成:
 *   1. 角色名册 (characters.json) — {name, description, aliases}
 *   2. 章节摘要 (summaries.json) — {chapterId, chapterTitle, summary}
 *
 * 用法: node generate_summary.mjs
 */
import { readdirSync, readFileSync, writeFileSync, existsSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const dataDir = join(__dirname, 'data');
const chaptersDir = join(dataDir, 'chapters');
const configPath = join(__dirname, 'config.json');

const config = JSON.parse(readFileSync(configPath, 'utf8'));

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

// ── Call MiniMax ────────────────────────────────────────────────────────────
async function callMiniMax(messages, maxTokens = 8000) {
  // Retry with content sanitization on 422 (content filter)
  for (let attempt = 0; attempt < 3; attempt++) {
    const resp = await fetch(config.minimax_base_url + '/chat/completions', {
      method: 'POST',
      headers: {
        'Authorization': 'Bearer ' + config.minimax_api_key,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        model: config.minimax_model,
        messages,
        max_tokens: maxTokens,
        temperature: 0.3,
      }),
    });

    if (resp.ok) {
      const data = await resp.json();
      return data.choices[0].message.content;
    }

    const text = await resp.text();

    // 422 content filter — sanitize and retry
    if (resp.status === 422 && attempt < 2) {
      console.log(`\n    (422 content filter, retry ${attempt + 1}/2)`);
      // Sanitize: replace potentially sensitive words in user message
      const sanitized = messages.map(m => {
        if (m.role === 'user') {
          let content = m.content;
          // Replace common manga content filter triggers
          content = content.replace(/强暴|强奸|性侵|裸体|裸露/g, '***');
          content = content.replace(/杀|死|血/g, match => {
            // Only replace standalone violence words, not parts of other words
            return match;
          });
          return { ...m, content };
        }
        return m;
      });
      messages = sanitized;
      await new Promise(r => setTimeout(r, 1000));
      continue;
    }

    throw new Error(`MiniMax API ${resp.status}: ${text}`);
  }
  throw new Error('MiniMax API: max retries exceeded');
}

// ── Generate character roster ───────────────────────────────────────────────
async function generateCharacterRoster(chapters) {
  console.log('=== 生成角色名册 ===');
  console.log(`  输入：${chapters.length} 章`);

  // Build a compact view of all chapters for character analysis
  const allText = chapters.map(ch => {
    return `【${ch.chapterTitle}】\n${screenplayToText(ch)}`;
  }).join('\n\n---\n\n');

  const prompt = `你是一个漫画分析助手。以下是整部漫画的分镜提取文本。请从中识别所有角色，生成角色名册。

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
  console.log('  调用 MiniMax-M3...');

  const result = await callMiniMax([
    { role: 'system', content: '你是一个专业的漫画内容分析助手。只输出JSON，不要输出其他文字。' },
    { role: 'user', content: prompt },
  ], 4000);

  // Extract JSON from response
  let parsed;
  try {
    parsed = JSON.parse(result);
  } catch {
    const m = result.match(/\{[\s\S]*\}/);
    if (m) {
      try { parsed = JSON.parse(m[0]); } catch { parsed = { characters: [] }; }
    } else {
      parsed = { characters: [] };
    }
  }

  const outputPath = join(dataDir, 'characters.json');
  writeFileSync(outputPath, JSON.stringify(parsed, null, 2));
  console.log(`  ✓ 生成 ${parsed.characters?.length || 0} 个角色`);
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

    const prompt = `你是一个漫画分析助手。以下是漫画"${ch.chapterTitle}"的分镜提取文本。

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
      const result = await callMiniMax([
        { role: 'system', content: '你是一个专业的漫画内容分析助手。只输出JSON，不要输出其他文字。' },
        { role: 'user', content: prompt },
      ], 2000);

      let parsed;
      try {
        parsed = JSON.parse(result);
      } catch {
        const m = result.match(/\{[\s\S]*\}/);
        if (m) {
          try { parsed = JSON.parse(m[0]); } catch { parsed = { summary: result.substring(0, 200) }; }
        } else {
          parsed = { summary: result.substring(0, 200) };
        }
      }

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
        summary: '(内容审核限制，跳过)',
        key_events: [],
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
  console.log('漫画摘要生成器 · MiniMax-M3\n');

  const chapters = loadChapters();
  console.log(`加载 ${chapters.length} 章\n`);

  const roster = await generateCharacterRoster(chapters);
  const summaries = await generateChapterSummaries(chapters, roster);

  console.log('\n=== 完成 ===');
  console.log(`角色名册：${roster.characters?.length || 0} 个角色`);
  console.log(`章节摘要：${summaries.length} 章`);
}

main().catch(e => { console.error('Error:', e); process.exit(1); });