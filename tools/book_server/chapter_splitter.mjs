/**
 * TXT 智能拆章引擎
 *
 * 策略（参考 Calibre / reading-nook / 静读天下）：
 *   1. 多模式竞争：准备 N 种正则，每种跑全文，统计命中行数
 *   2. 取命中数最多且 ≥ 2 的模式作为拆章依据
 *   3. 全部失败 → 按字数硬切（默认 8000 字/章）
 *
 * 额外处理：
 *   - 编码自动检测（UTF-8 / UTF-16LE / GBK / Big5）
 *   - 标题行长度过滤（> 40 字不算标题，防正文误判）
 *   - 短章合并（< 200 字的"章"并入下一章）
 *   - 序章/楔子/后记等特殊标记识别
 */

// ── 编码检测 ─────────────────────────────────────────────────────────────────

/**
 * Detect encoding from a Buffer. Returns [decodedString, encodingName].
 * Pure heuristic — no external deps.
 */
export function decodeBuffer(buf) {
  // BOM detection
  if (buf[0] === 0xFF && buf[1] === 0xFE) {
    return [buf.toString('utf16le', 2), 'utf-16le'];
  }
  if (buf[0] === 0xFE && buf[1] === 0xFF) {
    // UTF-16BE — swap bytes then decode as LE
    const swapped = Buffer.alloc(buf.length - 2);
    for (let i = 2; i < buf.length - 1; i += 2) {
      swapped[i - 2] = buf[i + 1];
      swapped[i - 1] = buf[i];
    }
    return [swapped.toString('utf16le'), 'utf-16be'];
  }
  if (buf[0] === 0xEF && buf[1] === 0xBB && buf[2] === 0xBF) {
    return [buf.toString('utf8', 3), 'utf-8'];
  }

  // Try UTF-8 strict decode — if no replacement chars, it's UTF-8
  const utf8 = buf.toString('utf8');
  if (!utf8.includes('\uFFFD')) {
    return [utf8, 'utf-8'];
  }

  // Heuristic: check for GBK high-byte pairs
  // GBK: first byte 0x81-0xFE, second byte 0x40-0xFE
  let gbkPairs = 0;
  for (let i = 0; i < Math.min(buf.length, 10000); i++) {
    if (buf[i] >= 0x81 && buf[i] <= 0xFE && i + 1 < buf.length) {
      if (buf[i + 1] >= 0x40 && buf[i + 1] <= 0xFE) {
        gbkPairs++;
        i++; // skip next byte
      }
    }
  }

  if (gbkPairs > 10) {
    // Use Node's TextDecoder for GBK (available in Node 18+)
    try {
      const decoder = new TextDecoder('gbk');
      return [decoder.decode(buf), 'gbk'];
    } catch (_) {
      // fallback to latin1 if GBK not supported
    }
  }

  // Last resort: latin1 (won't crash, user may see garbled text)
  return [buf.toString('latin1'), 'latin1'];
}

// ── 章节标题正则模式库 ─────────────────────────────────────────────────────────

const CN_NUM = '零〇一二三四五六七八九十百千万两';
const NUM = `\\d${CN_NUM}`;

/**
 * Each pattern: { name, regex, weight }
 * regex must have 'm' flag behavior (we use ^ with multiline).
 * weight is a tiebreaker multiplier (higher = more trustworthy format).
 */
const PATTERNS = [
  {
    name: '第X章',
    regex: new RegExp(`^\\s*第[${NUM}]{1,10}章[\\s:：·、—-]*.{0,40}$`, 'm'),
    global: new RegExp(`^\\s*第[${NUM}]{1,10}章[\\s:：·、—-]*.{0,40}$`, 'gm'),
    weight: 1.0,
  },
  {
    name: '第X回',
    regex: new RegExp(`^\\s*第[${NUM}]{1,10}回[\\s:：·、—-]*.{0,40}$`, 'm'),
    global: new RegExp(`^\\s*第[${NUM}]{1,10}回[\\s:：·、—-]*.{0,40}$`, 'gm'),
    weight: 1.0,
  },
  {
    name: '第X节',
    regex: new RegExp(`^\\s*第[${NUM}]{1,10}节[\\s:：·、—-]*.{0,40}$`, 'm'),
    global: new RegExp(`^\\s*第[${NUM}]{1,10}节[\\s:：·、—-]*.{0,40}$`, 'gm'),
    weight: 0.9,
  },
  {
    name: '第X卷/篇/部/集',
    regex: new RegExp(`^\\s*第[${NUM}]{1,10}[卷篇部集][\\s:：·、—-]*.{0,40}$`, 'm'),
    global: new RegExp(`^\\s*第[${NUM}]{1,10}[卷篇部集][\\s:：·、—-]*.{0,40}$`, 'gm'),
    weight: 0.85,
  },
  {
    name: 'Chapter N',
    regex: /^\s*[Cc]hapter\s+\d+[\s:.：—-]*.{0,40}$/m,
    global: /^\s*[Cc]hapter\s+\d+[\s:.：—-]*.{0,40}$/gm,
    weight: 0.95,
  },
  {
    name: '数字编号 (001 / 1. / 1、)',
    regex: /^\s*\d{1,4}[.、．]\s*\S.{0,36}$/m,
    global: /^\s*\d{1,4}[.、．]\s*\S.{0,36}$/gm,
    weight: 0.7,
  },
  {
    name: '纯数字标题行 (0001 标题)',
    regex: /^\s*\d{1,4}\s+\S.{2,36}$/m,
    global: /^\s*\d{1,4}\s+\S.{2,36}$/gm,
    weight: 0.6,
  },
  {
    name: '卷X / 篇X (无"第")',
    regex: new RegExp(`^\\s*[卷篇][${NUM}]{1,6}[\\s:：·、—-]*.{0,40}$`, 'm'),
    global: new RegExp(`^\\s*[卷篇][${NUM}]{1,6}[\\s:：·、—-]*.{0,40}$`, 'gm'),
    weight: 0.8,
  },
  {
    name: '【标题】/ [标题]',
    regex: /^\s*[【\[][^】\]\n]{1,30}[】\]]\s*$/m,
    global: /^\s*[【\[][^】\]\n]{1,30}[】\]]\s*$/gm,
    weight: 0.5,
  },
];

// Special markers that are always treated as chapter boundaries
const SPECIAL_MARKERS = new RegExp(
  '^[\\s]*(?:序[章言幕]?|前言|引[言子]|楔子|尾声|后记|终章|番外|彩蛋|附录|结语|终)[\\s:：]*.{0,20}$',
  'gm',
);

// ── 核心拆章逻辑 ─────────────────────────────────────────────────────────────

/**
 * Split text into chapters.
 * @param {string} text - decoded full text
 * @param {object} [opts]
 * @param {number} [opts.fallbackChunkSize=8000] - chars per chunk when no pattern matches
 * @param {number} [opts.minChapterChars=200] - merge chapters shorter than this
 * @returns {{ chapters: Array<{title: string, content: string}>, method: string, patternName: string|null }}
 */
export function splitChapters(text, opts = {}) {
  const fallbackSize = opts.fallbackChunkSize || 8000;
  const minChars = opts.minChapterChars || 200;

  // Normalize line endings
  text = text.replace(/\r\n/g, '\n').replace(/\r/g, '\n');

  // 1. Try each pattern, count matches
  let best = null;
  for (const pat of PATTERNS) {
    const matches = [...text.matchAll(pat.global)];
    const count = matches.length;
    if (count < 2) continue; // need at least 2 to form chapters
    const score = count * pat.weight;
    if (!best || score > best.score) {
      best = { pat, matches, score, count };
    }
  }

  // 2. Also collect special markers
  const specialMatches = [...text.matchAll(SPECIAL_MARKERS)];

  if (best) {
    // Merge special markers into the match list
    const allMatches = [...best.matches];
    for (const sm of specialMatches) {
      // Avoid duplicates at same position
      const pos = sm.index;
      if (!allMatches.some(m => Math.abs(m.index - pos) < 5)) {
        allMatches.push(sm);
      }
    }
    allMatches.sort((a, b) => a.index - b.index);

    const chapters = _buildChapters(text, allMatches);
    return {
      chapters: _mergeShort(chapters, minChars),
      method: 'pattern',
      patternName: best.pat.name,
    };
  }

  // 3. Special markers alone?
  if (specialMatches.length >= 2) {
    const chapters = _buildChapters(text, specialMatches);
    return {
      chapters: _mergeShort(chapters, minChars),
      method: 'special',
      patternName: '特殊标记',
    };
  }

  // 4. Fallback: split by size at paragraph boundaries
  return {
    chapters: _splitBySize(text, fallbackSize),
    method: 'size',
    patternName: null,
  };
}

// ── 内部工具 ─────────────────────────────────────────────────────────────────

function _buildChapters(text, matches) {
  const chapters = [];

  // Content before first match → "序" / prologue
  if (matches[0].index > 100) {
    const preface = text.slice(0, matches[0].index).trim();
    if (preface.length > 50) {
      chapters.push({ title: '序', content: preface });
    }
  }

  for (let i = 0; i < matches.length; i++) {
    const start = matches[i].index;
    const end = i + 1 < matches.length ? matches[i + 1].index : text.length;
    const raw = text.slice(start, end);

    // First line is the title
    const nlIdx = raw.indexOf('\n');
    const title = (nlIdx > 0 ? raw.slice(0, nlIdx) : raw.slice(0, 40)).trim();
    const content = raw.trim();

    chapters.push({ title, content });
  }

  return chapters;
}

function _mergeShort(chapters, minChars) {
  if (chapters.length <= 1) return chapters;
  const merged = [];
  for (const ch of chapters) {
    if (merged.length > 0 && ch.content.length < minChars) {
      // Append to previous chapter
      const prev = merged[merged.length - 1];
      prev.content += '\n\n' + ch.content;
    } else {
      merged.push({ ...ch });
    }
  }
  return merged;
}

function _splitBySize(text, size) {
  const paragraphs = text.split(/\n\s*\n/);
  const chapters = [];
  let buf = '';
  let idx = 1;

  for (const para of paragraphs) {
    if (buf.length + para.length > size && buf.length > 0) {
      chapters.push({
        title: `第 ${idx} 部分`,
        content: buf.trim(),
      });
      idx++;
      buf = '';
    }
    buf += (buf ? '\n\n' : '') + para;
  }
  if (buf.trim()) {
    chapters.push({ title: `第 ${idx} 部分`, content: buf.trim() });
  }
  return chapters;
}

// ── 编码检测 + 拆章一站式入口 ─────────────────────────────────────────────────

/**
 * Process a raw TXT buffer into chapters.
 * @param {Buffer} buf - raw file bytes
 * @param {object} [opts] - splitChapters options
 * @returns {{ encoding: string, chapters: Array, method: string, patternName: string|null, totalChars: number }}
 */
export function processTxt(buf, opts = {}) {
  const [text, encoding] = decodeBuffer(buf);
  const result = splitChapters(text, opts);
  return {
    encoding,
    totalChars: text.length,
    ...result,
  };
}
