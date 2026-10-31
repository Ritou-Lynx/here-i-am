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

// Script rounds: a committed PowerShell file, pinned by hash. write mode waits for the owner's 👍.
const RUNNER = /^<!-- relay:to-runner round=(\d+) script=(tools\/relay_scripts\/[A-Za-z0-9_-][A-Za-z0-9._-]*(?:\/[A-Za-z0-9_-][A-Za-z0-9._-]*)*\.ps1) sha256=([0-9a-f]{64}) mode=(read|write) -->[ \t]*$/;

export function parseRunnerInstruction(body) {
  if (typeof body !== 'string') return null;
  const match = RUNNER.exec(body.split(/\r?\n/, 1)[0]);
  if (!match || match[2].split('/').includes('..')) return null;
  const round = Number(match[1]);
  if (!Number.isSafeInteger(round) || round < 1) return null;
  return { round, script: match[2], sha256: match[3], mode: match[4] };
}

export function formatRunnerReply({ round, status, sha, script, exitCode, output, reason, summaryMaxChars = 6000, secrets = [] } = {}) {
  const head = `<!-- relay:to-claude round=${round} status=${status} sha=${sha || 'none'} kind=runner -->`;
  const lines = [`**[to-claude] 脚本第 ${round} 轮 · ${status}**`, '', `脚本：${script ?? ''}`];
  if (Number.isInteger(exitCode)) lines.push(`退出码：${exitCode}`);
  if (reason) lines.push(`原因：${redact(String(reason).split(/\r?\n/, 1)[0], Number.MAX_SAFE_INTEGER, secrets).text}`);
  const body = redact(String(output ?? ''), summaryMaxChars, secrets);
  lines.push('', '```text', body.text.replace(/```/g, "'''"), '```');
  return head + '\n' + redact(lines.join('\n'), Number.MAX_SAFE_INTEGER, secrets).text + (body.redacted || body.truncated ? '\n\n部分内容已隐藏或截断，全文见本机日志' : '');
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

export function redact(text, maxChars = 6000, secrets = []) {
  let value = String(text ?? '');
  let redacted = false;
  for (const secret of [...secrets].filter(x => typeof x === 'string' && x).sort((a, b) => b.length - a.length)) {
    if (value.includes(secret)) { value = value.split(secret).join('[已隐藏]'); redacted = true; }
  }
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

export function parseNotification(body) {
  if (typeof body !== 'string') return null;
  const match = /^<!-- relay:(done|to-human) -->[ \t]*$/.exec(body.split(/\r?\n/, 1)[0]);
  return match ? { kind: match[1] } : null;
}

export function formatNotification({ kind, pr, round, title = '', url = '', body = '' }, secrets = []) {
  const suffix = kind === 'done' ? '完成，等你验收' : kind === 'to-human' ? '需要你决定' : kind === 'approval' ? '有改动型脚本等你点 👍' : `第 ${round} 轮失败`;
  const excerpt = redact(String(body).replace(/^.*?(?:\r?\n|$)/, ''), 300, secrets).text;
  return {
    title: redact(`接力 PR #${pr}：${suffix}`, Number.MAX_SAFE_INTEGER, secrets).text,
    content: redact(`${title}\n${url}\n${excerpt}`, Number.MAX_SAFE_INTEGER, secrets).text,
    url: redact(url, Number.MAX_SAFE_INTEGER, secrets).text,
  };
}

export function formatReply({ round, status, sha, startSha, commitCount, files, summary, reason, details, summaryMaxChars = 6000, secrets = [] } = {}) {
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
  const rawSummary = redact(String(summary ?? ''), Number.MAX_SAFE_INTEGER, secrets);
  const rawReason = redact(String(reason ?? ''), Number.MAX_SAFE_INTEGER, secrets);
  const diagnosticText = ok ? '' : String(details ?? '');
  const rawDetails = redact(diagnosticText, Number.MAX_SAFE_INTEGER, secrets);
  const detailLines = rawDetails.text.split(/\r?\n/).slice(0, 29);
  const droppedLines = (reason ? String(reason).split(/\r?\n/).length > 1 : false) || diagnosticText.split(/\r?\n/).length > 29;
  // Redact complete diagnostics before clipping, so a multiline key cannot be cut before its END marker.
  const combined = [rawSummary.text, ...detailLines].filter(Boolean).join('\n');
  const reasonLines = reason ? [`原因：${rawReason.text.split(/\r?\n/)[0]}`] : [];
  const payload = redact([...reasonLines, combined].filter(Boolean).join('\n'), summaryMaxChars, secrets);
  const fixed = ok ? lines.slice() : lines.slice(0, 2);
  lines.length = 0;
  lines.push(...fixed);
  lines.push(payload.text);
  const publicBody = redact(lines.join('\n'), Number.MAX_SAFE_INTEGER, secrets);
  const result = publicBody.text;
  const anyRedacted = rawSummary.redacted || rawReason.redacted || rawDetails.redacted || publicBody.redacted || payload.redacted;
  return head + '\n' + result + ((anyRedacted || payload.truncated || droppedLines) ? '\n\n部分内容已隐藏，全文见本机日志' : '');
}
