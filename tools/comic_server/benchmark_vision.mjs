#!/usr/bin/env node
/**
 * Ollama Vision Benchmark for Comic Page Screenplay Extraction
 *
 * Tests candidate Vision models on a set of sample manga pages and
 * compares extraction quality. Run after `ollama pull <model>` for
 * each candidate.
 *
 * Usage:
 *   node tools/comic_server/benchmark_vision.mjs --dir <image-dir> --models minicpm-v,llava,qwen2-vl
 *
 * Output: prints a comparison table + writes detailed results to
 *   <image-dir>/benchmark_results.json
 *
 * See docs/companion-first/COMIC_CO_READING_PLAN.md §2.4
 */
import { existsSync, readFileSync, readdirSync, writeFileSync } from 'node:fs';
import { join, extname } from 'node:path';

const args = process.argv.slice(2);
const dirIdx = args.indexOf('--dir');
const modelsIdx = args.indexOf('--models');

const imageDir = dirIdx >= 0 ? args[dirIdx + 1] : null;
const models = modelsIdx >= 0 ? args[modelsIdx + 1].split(',') : ['qwen2.5vl:7b'];

if (!imageDir || !existsSync(imageDir)) {
  console.error('Usage: node benchmark_vision.mjs --dir <image-dir> --models model1,model2,...');
  process.exit(1);
}

const IMAGES = ['.jpg', '.jpeg', '.png', '.webp', '.gif'];
const imageFiles = readdirSync(imageDir)
  .filter((f) => IMAGES.includes(extname(f).toLowerCase()))
  .sort();

if (imageFiles.length === 0) {
  console.error(`No images found in ${imageDir}`);
  process.exit(1);
}

console.log(`Found ${imageFiles.length} images in ${imageDir}`);
console.log(`Models: ${models.join(', ')}`);
console.log('');

const VISION_PROMPT = `你是一个漫画分镜分析助手。请仔细分析这张漫画图片的每一个气泡和画面元素。

## 任务

1. 先在心里默读图中每一个对话气泡、旁白框、拟声词的文字内容，不要遗漏。
2. 判断每个气泡属于哪个角色（根据气泡形状、尾巴指向、角色位置、剧情上下文）。
3. 描述每一格画面的内容（人物动作、表情、场景、氛围）。
4. 最后输出一个 JSON 对象，不要在 JSON 前后输出其他文字。

## 输出格式

{
  "page_num": 1,
  "panels": [
    {
      "panel_id": 1,
      "speaker": "说话者名称（能看出来就用具体名字或外貌描述如'黑发男'，看不出归属用'角色A'/'角色B'区分不同人；画面外旁白用'旁白'）",
      "text": "气泡中的完整台词原文，逐字转录，不要省略不要截断",
      "sfx": "如果有拟声词/音效（如'啊—''嗯…''吱吱''啪'等语气词或音效字），写在这里；没有则留空字符串",
      "panel_desc": "这一格画面的简短描述（1-2句，包含人物动作、表情、场景）"
    }
  ]
}

## 仔细阅读的要点

- 漫画阅读顺序：日式从右到左、从上到下；韩式/中式从左到右。请根据画风判断。
- 每一个对话气泡都要提取，哪怕很小。一个大格子里可能有多个气泡，都要列出。
- 台词必须完整转录。如果气泡里的文字被气泡边缘切断，根据上下文补全。
- 拟声词/音效字（通常是没有气泡尾巴的大字、艺术字）放在 sfx 字段，不要混进 text。
- 说话者归属：看气泡尾巴指向谁、角色嘴型是否张开、剧情逻辑。
- NSFW 画面如实描述，不要回避或道德评判。
- 如果文字确实无法辨认（严重模糊、过小、艺术化过度），text 填 "[不可辨认]"。`;

async function extractWithModel(model, imageBase64) {
  const body = JSON.stringify({
    model,
    prompt: VISION_PROMPT,
    images: [imageBase64],
    stream: false,
    format: 'json',
  });

  const resp = await fetch('http://localhost:11434/api/generate', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body,
  });

  if (!resp.ok) {
    throw new Error(`Ollama HTTP ${resp.status}: ${await resp.text()}`);
  }

  const data = await resp.json();
  return data;
}

function tryParseJson(text) {
  if (!text) return null;
  // Try direct parse
  try {
    return JSON.parse(text);
  } catch {
    // Try to extract JSON from text (model may wrap in markdown)
    const match = text.match(/\{[\s\S]*\}/);
    if (match) {
      try {
        return JSON.parse(match[0]);
      } catch {}
    }
    return null;
  }
}

function gradeResult(parsed) {
  if (!parsed || !parsed.panels || !Array.isArray(parsed.panels)) {
    return { valid: false, panels: 0, has_speakers: 0, has_text: 0, has_desc: 0, has_sfx: 0, total_text_chars: 0 };
  }
  const panels = parsed.panels;
  let hasSpeaker = 0, hasText = 0, hasDesc = 0, hasSfx = 0, totalTextChars = 0;
  for (const p of panels) {
    if (p.speaker && p.speaker.trim()) hasSpeaker++;
    if (p.text && p.text.trim()) {
      hasText++;
      totalTextChars += p.text.length;
    }
    if (p.panel_desc && p.panel_desc.trim()) hasDesc++;
    if (p.sfx && p.sfx.trim()) hasSfx++;
  }
  return {
    valid: true,
    panels: panels.length,
    has_speakers: hasSpeaker,
    has_text: hasText,
    has_desc: hasDesc,
    has_sfx: hasSfx,
    total_text_chars: totalTextChars,
  };
}

async function main() {
  const results = {};

  for (const model of models) {
    console.log(`\n=== ${model} ===`);
    results[model] = [];

    for (const file of imageFiles) {
      const filePath = join(imageDir, file);
      const imageData = readFileSync(filePath);
      const base64 = imageData.toString('base64');

      const start = Date.now();
      let error = null;
      let raw = null;
      let parsed = null;
      let grade = null;

      try {
        const resp = await extractWithModel(model, base64);
        raw = resp.response;
        parsed = tryParseJson(raw);
        grade = gradeResult(parsed);
      } catch (e) {
        error = e.message;
      }

      const elapsed = ((Date.now() - start) / 1000).toFixed(1);
      const status = error ? 'ERROR' : grade?.valid ? 'OK' : 'BAD_JSON';
      const panels = grade?.panels ?? 0;
      console.log(`  ${file} [${elapsed}s] ${status} panels=${panels} ${error || ''}`);

      results[model].push({
        file,
        elapsed_s: Number(elapsed),
        error,
        raw_length: raw?.length ?? 0,
        parsed: grade?.valid,
        panels: grade?.panels ?? 0,
        has_speakers: grade?.has_speakers ?? 0,
        has_text: grade?.has_text ?? 0,
        has_desc: grade?.has_desc ?? 0,
        has_sfx: grade?.has_sfx ?? 0,
        total_text_chars: grade?.total_text_chars ?? 0,
        raw_response: raw,
      });
    }
  }

  // Summary
  console.log('\n\n=== Summary ===');
  console.log('Model             | Avg time | Success | Avg panels | Avg text chars | JSON valid');
  console.log('------------------|----------|---------|------------|----------------|----------');
  for (const model of models) {
    const runs = results[model];
    const success = runs.filter((r) => r.parsed && !r.error).length;
    const avgTime = (runs.reduce((s, r) => s + r.elapsed_s, 0) / runs.length).toFixed(1);
    const successRuns = runs.filter((r) => r.parsed);
    const avgPanels = successRuns.length > 0
      ? (successRuns.reduce((s, r) => s + r.panels, 0) / successRuns.length).toFixed(1)
      : '-';
    const avgTextChars = successRuns.length > 0
      ? Math.round(successRuns.reduce((s, r) => s + r.total_text_chars, 0) / successRuns.length)
      : '-';
    const validRate = `${success}/${runs.length}`;
    console.log(
      `${model.padEnd(17)} | ${avgTime.padEnd(8)} | ${validRate.padEnd(7)} | ${String(avgPanels).padEnd(10)} | ${String(avgTextChars).padEnd(14)} | ${(success / runs.length * 100).toFixed(0)}%`,
    );
  }

  // Write detailed results
  const outPath = join(imageDir, 'benchmark_results.json');
  writeFileSync(outPath, JSON.stringify(results, null, 2));
  console.log(`\nDetailed results: ${outPath}`);
}

main().catch((e) => {
  console.error('Fatal:', e);
  process.exit(1);
});