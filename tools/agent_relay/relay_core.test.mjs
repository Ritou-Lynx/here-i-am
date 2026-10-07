import test from 'node:test';
import assert from 'node:assert/strict';
import { parseInstruction, isEligiblePr, renderPrompt, redact, formatReply } from './relay_core.mjs';

test('parseInstruction requires exact first line and safe positive round', () => {
  assert.deepEqual(parseInstruction('<!-- relay:to-codex round=2 -->\nDo it'), { round: 2, instruction: 'Do it' });
  for (const body of ['x\n<!-- relay:to-codex round=2 -->', ' <!-- relay:to-codex round=2 -->\nx', '<!-- relay:to-codex round=0 -->\nx', '<!-- relay:to-codex round=x -->\nx', '<!-- relay:to-codex  round=2 -->\nx', '<!-- relay:to-claude round=2 -->\nx']) assert.equal(parseInstruction(body), null);
  assert.deepEqual(parseInstruction('<!-- relay:to-codex round=9007199254740991 -->\r\nX'), { round: 9007199254740991, instruction: 'X' });
});

test('isEligiblePr enforces protocol conditions', () => {
  const base = { repo: 'Ritou-Lynx/here-i-am', baseRefName: 'v3-lab', headRefName: 'claude/x', isCrossRepository: false, labels: ['agent-relay'] };
  assert.equal(isEligiblePr(base), true);
  for (const change of [{ labels: [] }, { labels: ['agent-relay', 'relay-paused'] }, { labels: ['agent-relay', 'relay-needs-human'] }, { isCrossRepository: true }, { isCrossRepository: undefined }, { baseRefName: 'main' }, { headRefName: 'feature/x' }, { headRefName: 'claude/../x' }, { headRefName: 'claude/x:y' }, { headRefName: 'claude/x y' }, { headRefName: 'claude/x\\y' }, { headRefName: 'claude/-x' }]) assert.equal(isEligiblePr({ ...base, ...change }), false);
});

test('renderPrompt extracts fenced body and substitutes once', () => {
  const t = 'intro\n---\nA {{round}} {{instruction}}\n---\nout';
  assert.equal(renderPrompt(t, { round: 3, instruction: '{{round}}' }), 'A 3 {{round}}\n');
});

test('redact covers token, key, bearer, path and truncation', () => {
  const patterns = ['ghp_12345678901234567890', 'gho_12345678901234567890', 'ghu_12345678901234567890', 'ghs_12345678901234567890', 'ghr_12345678901234567890', 'github_pat_12345678901234567890', 'sk-12345678901234567890', 'Bearer abcdefghijklmnop', '-----BEGIN PRIVATE KEY-----\nsecret\n-----END PRIVATE KEY-----', '-----BEGIN RSA PRIVATE KEY-----\nsecret\n-----END RSA PRIVATE KEY-----', '-----BEGIN EC PRIVATE KEY-----\nsecret\n-----END EC PRIVATE KEY-----', '-----BEGIN OPENSSH PRIVATE KEY-----\nsecret\n-----END OPENSSH PRIVATE KEY-----'];
  for (const pattern of patterns) { const r = redact(pattern, 1000); assert.equal(r.redacted, true, pattern); assert.match(r.text, /\[已隐藏\]/, pattern); assert.doesNotMatch(r.text, /secret|gh[pousr]_\d|github_pat_|sk-|Bearer/i, pattern); }
  for (const path of ['C:\\Users\\Lynx\\x', 'C:/Users/Lynx/x']) assert.equal(redact(path).text, '%USERPROFILE%');
  assert.equal(redact('C:\\HereIAm\\private\\log.txt').text, '[已隐藏]');
  const short = redact('abcdef', 3); assert.equal(short.truncated, true); assert.equal(short.text.length, 3);
});

test('formatReply has protocol header, failed sha none, sanitizes details and caps lines', () => {
  const out = formatReply({ round: 1, status: 'failed', sha: 'bad', reason: 'C:\\Users\\x\\a', details: Array.from({ length: 40 }, (_, i) => `${i} ghp_12345678901234567890`).join('\n') });
  assert.match(out, /^<!-- relay:to-claude round=1 status=failed sha=none -->/);
  assert.doesNotMatch(out, /ghp_/); assert.doesNotMatch(out, /C:\\Users\\/);
  assert.ok(out.split('\n').filter(x => /^\d+ /.test(x)).length <= 30);
});

test('formatReply bounds huge reason and reports summary-only redaction', () => {
  const hugeReason = Array.from({ length: 80 }, () => 'x'.repeat(1000)).join('\n');
  const failed = formatReply({ round: 2, status: 'failed', reason: hugeReason, summaryMaxChars: 120 });
  assert.match(failed, /sha=none/); assert.ok(failed.length < 500); assert.match(failed, /部分内容已隐藏/);
  const summary = formatReply({ round: 2, status: 'done', sha: 'abc', summary: 'ghp_12345678901234567890' });
  assert.match(summary, /\[已隐藏\]/); assert.match(summary, /部分内容已隐藏/);
});

test('formatReply preserves every file and reports path-only redaction', () => {
  const out = formatReply({ round: 3, status: 'done', sha: 'abcdef', files: ['src/a.mjs', 'src/b.mjs', 'C:\\Users\\Lynx\\secret.txt'], summary: 'ok' });
  assert.match(out, /src\/a\.mjs/); assert.match(out, /src\/b\.mjs/);
  assert.doesNotMatch(out, /C:\\Users\\/); assert.match(out, /部分内容已隐藏/);
});

test('formatReply does not truncate long file lists with summary limit', () => {
  const out = formatReply({ round: 4, status: 'done', sha: 'abcdef', files: ['a'.repeat(500), 'tail-file'], summary: 'ok', summaryMaxChars: 10 });
  assert.match(out, /tail-file/); assert.match(out, /sha=abcdef/);
});

test('formatReply redacts a PEM block before clipping diagnostics', () => {
  const pem = ['-----BEGIN PRIVATE KEY-----', 'SYNTHETIC_SECRET_MATERIAL', ...Array.from({ length: 40 }, () => 'padding'), '-----END PRIVATE KEY-----'].join('\n');
  const out = formatReply({ round: 5, status: 'failed', reason: 'check', details: pem, summaryMaxChars: 6000 });
  assert.doesNotMatch(out, /SYNTHETIC_SECRET_MATERIAL|-----BEGIN PRIVATE KEY-----|-----END PRIVATE KEY-----/);
  assert.match(out, /\[已隐藏\]/);
});
