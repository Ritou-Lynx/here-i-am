const MARKER = /^<!-- relay:to-codex round=(\d+) -->[ \t]*$/;

export function parseInstruction(body) {
  if (typeof body !== 'string') return null;
  const first = body.split(/\r?\n/, 1)[0];
  const match = MARKER.exec(first);
  if (!match) return null;
  const round = Number(match[1]);
  if (!Number.isSafeInteger(round) || round < 1) return null;
  return { round, instruction: body.replace(/^.*?(?:\r?\n|$)/, '') };
}

export function isEligiblePr(pr, config = {}) {
  if (!pr || pr.state && pr.state !== 'OPEN' && pr.state !== 'open') return false;
  const labels = (pr.labels || []).map(x => typeof x === 'string' ? x : x?.name).filter(Boolean);
  const repo = config.repo ?? 'Ritou-Lynx/here-i-am';
  if (repo !== 'Ritou-Lynx/here-i-am' || pr.repo && pr.repo !== repo) return false;
  if (pr.baseRefName !== (config.baseBranch ?? 'v3-lab')) return false;
  if (pr.isCrossRepository !== false) return false;
  const prefixes = config.headPrefixes ?? ['claude/', 'codex/'];
  if (typeof pr.headRefName !== 'string' || /\.\.|[:\\\s\x00-\x1f\x7f]/.test(pr.headRefName) || /(^|\/)\-/.test(pr.headRefName) || !prefixes.some(p => pr.headRefName.startsWith(p))) return false;
  if (!labels.includes('agent-relay') || labels.includes('relay-paused') || labels.includes('relay-needs-human')) return false;
  return true;
}

export function renderPrompt(template, values = {}) {
  if (typeof template !== 'string') return '';
  const start = template.match(/^---[ \t]*\r?\n/m);
  if (!start) return template;
  const from = start.index + start[0].length;
  const endMatch = template.slice(from).match(/^---[ \t]*\r?\n?/m);
  if (!endMatch) return template;
  const text = template.slice(from, from + endMatch.index);
  return text.replace(/\{\{(pr_number|branch|round|contract|instruction)\}\}/g, (_, name) => String(values[name] ?? ''));
}

const secretPatterns = [
  /gh[pousr]_[A-Za-z0-9]{20,}/g,
  /github_pat_[A-Za-z0-9_]{20,}/g,
  /sk-[A-Za-z0-9_-]{20,}/g,
  /Bearer\s+[A-Za-z0-9._~+\/-]{16,}/gi,
  /-----BEGIN ([A-Z ]*PRIVATE KEY)-----[\s\S]*?-----END \1-----/g,
];
const userPath = /(?<![A-Za-z0-9])[A-Za-z]:(?!\/\/)[\\/]Users[\\/][^\s]+/g;
const absolutePath = /(?<![A-Za-z0-9])[A-Za-z]:(?!\/\/)[\\/](?!Users[\\/])[^\s\r\n]+/g;

export function redact(text, maxChars = 6000) {
  let value = String(text ?? '');
  let redacted = false;
  for (const pattern of secretPatterns) {
    value = value.replace(pattern, () => { redacted = true; return '[已隐藏]'; });
  }
  value = value.replace(userPath, () => { redacted = true; return '%USERPROFILE%'; });
  value = value.replace(absolutePath, () => { redacted = true; return '[已隐藏]'; });
  const limit = Number.isSafeInteger(maxChars) && maxChars >= 0 ? maxChars : 6000;
  const truncated = value.length > limit;
  if (truncated) value = value.slice(0, limit);
  return { text: value, redacted, truncated };
}

export function formatReply({ round, status, sha, startSha, commitCount, files, summary, reason, details, summaryMaxChars = 6000 } = {}) {
  const ok = ['done', 'blocked'].includes(status);
  const safeSha = ok ? (sha || 'none') : 'none';
  const head = `<!-- relay:to-claude round=${round} status=${status} sha=${safeSha} -->`;
  const title = `**[to-claude] 第 ${round} 轮 · ${status}**`;
  const lines = [title, ''];
  if (ok) {
    lines.push(`提交：${safeSha}${startSha ? `（${startSha}…${safeSha}，共 ${commitCount ?? 0} 个）` : ''}`);
    lines.push('改动文件：');
    for (const file of (files || [])) lines.push(`- ${file}`);
    lines.push('');
  } else if (reason) {
    lines.push(`原因：${reason}`, '');
  }
  const rawSummary = redact(String(summary ?? ''), Number.MAX_SAFE_INTEGER);
  const rawReason = redact(String(reason ?? ''), Number.MAX_SAFE_INTEGER);
  const diagnosticText = ok ? '' : String(details ?? '');
  const rawDetails = redact(diagnosticText, Number.MAX_SAFE_INTEGER);
  const detailLines = rawDetails.text.split(/\r?\n/).slice(0, 29);
  const droppedLines = (reason ? String(reason).split(/\r?\n/).length > 1 : false) || diagnosticText.split(/\r?\n/).length > 29;
  // Redact complete diagnostics before clipping, so a multiline key cannot be cut before its END marker.
  const combined = [rawSummary.text, ...detailLines].filter(Boolean).join('\n');
  const reasonLines = reason ? [`原因：${rawReason.text.split(/\r?\n/)[0]}`] : [];
  const payload = redact([...reasonLines, combined].filter(Boolean).join('\n'), summaryMaxChars);
  const fixed = ok ? lines.slice() : lines.slice(0, 2);
  lines.length = 0;
  lines.push(...fixed);
  lines.push(payload.text);
  const publicBody = redact(lines.join('\n'), Number.MAX_SAFE_INTEGER);
  const result = publicBody.text;
  const anyRedacted = rawSummary.redacted || rawReason.redacted || rawDetails.redacted || publicBody.redacted || payload.redacted;
  return head + '\n' + result + ((anyRedacted || payload.truncated || droppedLines) ? '\n\n部分内容已隐藏，全文见本机日志' : '');
}
