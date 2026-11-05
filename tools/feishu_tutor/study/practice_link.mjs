// Turns a practice prompt (UTF-8 text file) into a ChatGPT link that opens a
// new chat with the prompt filled in. Copied into the study directory; the
// tutor runs it offline: `node practice_link.mjs practice\<科目>.txt`.
// No network, no writes. Prints the link on stdout, or one error code on stderr.
import { readFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

export const BASE = 'https://chatgpt.com/?q=';
export const MAX_LINK = 7000;

export function practiceLink(prompt) {
  if (typeof prompt !== 'string') throw new Error('prompt_missing');
  const text = prompt.replace(/^﻿/u, '').replace(/\r\n?/gu, '\n').trim();
  if (!text || text.includes('\0')) throw new Error('prompt_missing');
  const link = BASE + encodeURIComponent(text);
  if (link.length > MAX_LINK) throw new Error('prompt_too_long');
  return link;
}

export async function run(argv, output = console.log) {
  if (argv.length !== 1) throw new Error('usage_invalid');
  let prompt;
  try { prompt = await readFile(argv[0], 'utf8'); } catch { throw new Error('prompt_missing'); }
  output(practiceLink(prompt));
  return 0;
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try { process.exitCode = await run(process.argv.slice(2)); }
  catch (error) { console.error(/^[a-z_]+$/u.test(error.message) ? error.message : 'practice_link_error'); process.exitCode = 1; }
}
