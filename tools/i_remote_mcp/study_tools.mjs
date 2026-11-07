// ST1 study tools. Self-contained (node: imports only) so the legacy candidate can inline this file verbatim.
// Reads only today.md, state/sources.json and state/ledger.json under the configured study directory;
// writes only new files in its inbox/. Never deletes, overwrites, follows links or creates directories.
import * as studyFs from 'node:fs';
import * as studyPath from 'node:path';

export class StudyInputError extends Error {}
const studyFail = code => { throw new StudyInputError(code); };
const studyObject = value => value !== null && typeof value === 'object' && !Array.isArray(value);
export const STUDY_FRONTENDS = Object.freeze({claude_web:'claude', chatgpt_web:'chatgpt', gemini_web:'gemini'});
const STUDY_TIME_ZONE = 'Asia/Shanghai';
const STUDY_LIMITS = Object.freeze({today:1024*1024, sources:32*1024*1024, ledger:16*1024*1024, sourceChars:20000, resultChars:8000});
const STUDY_HINT = '出题方式：先调 study_today 取当天要点（可传 subject 只取一科），必要时用 study_source 读原笔记；用互动题一题一题练，每次只问一个问题，等用户回答再讲评。用户说结束或学习单做完时，按 TUTOR_RULES 的【学习结果】格式整理（知识点名照抄学习单，结果只能是 对/错/不会），调用一次 study_result 写回；写回成功后告诉用户明早入账。';
const studyReadOnly = {readOnlyHint:true,destructiveHint:false,idempotentHint:true,openWorldHint:false};
export const STUDY_TOOLS = Object.freeze([
  {name:'study_today',requiredScope:'i.read',description:'读取今天的学习单（家里电脑每天 06:30 生成）。返回学习单日期、是否是今天、科目列表，以及指定科目那一节或整份。is_today 为 false 时如实告诉用户学习单还没更新，不要假装是今天的。'+STUDY_HINT,
    inputSchema:{type:'object',properties:{subject:{type:'string',minLength:1,maxLength:50,description:'科目名，与学习单二级标题一致，如 日语、英语、数据分析；不传返回整份。'}},additionalProperties:false},annotations:studyReadOnly},
  {name:'study_source',requiredScope:'i.read',description:'按标题读取一篇学习笔记（飞书文档快照）正文，单次最多 20000 字，超出时用 offset 续读；不传 title 时返回笔记标题列表。以笔记为准出题，不编造出处。',
    inputSchema:{type:'object',properties:{title:{type:'string',minLength:1,maxLength:200},offset:{type:'integer',minimum:0}},additionalProperties:false},annotations:studyReadOnly},
  {name:'study_progress',requiredScope:'i.read',description:'读取学习进度：各科知识点数、掌握/模糊/未学、今天到期复习数、最近 7 天正确率、错次前 10 的薄弱点。数据是家里账本的最近一次快照（见 pulled_at）。',
    inputSchema:{type:'object',properties:{subject:{type:'string',minLength:1,maxLength:50}},additionalProperties:false},annotations:studyReadOnly},
  {name:'study_result',requiredScope:'i.write',description:'练完把一段【学习结果】写回家里学习目录的收件箱，次日由学习导师入账。content 不超过 8000 字，第一行必须是“【学习结果】YYYY-MM-DD 科目”。每次练习只调用一次；只新建文件，不能修改或删除已写的结果。',
    inputSchema:{type:'object',properties:{content:{type:'string',minLength:1,maxLength:8000}},required:['content'],additionalProperties:false},
    annotations:{readOnlyHint:false,destructiveHint:false,idempotentHint:false,openWorldHint:false}},
]);

function studySameRoot(a, b) {
  return process.platform === 'win32' ? a.toLowerCase() === b.toLowerCase() : a === b;
}
export function loadStudyConfig(stateDir) {
  let text;
  try { text = studyFs.readFileSync(studyPath.resolve(stateDir, 'study.json'), 'utf8'); }
  catch (error) { if (error.code === 'ENOENT') return null; throw new Error('study_config_invalid'); }
  try {
    const value = JSON.parse(text.replace(/^﻿/, ''));
    if (!studyObject(value) || Object.keys(value).length !== 2 || value.format !== 'study-v1' || typeof value.study_dir !== 'string'
      || !studyPath.isAbsolute(value.study_dir) || studyPath.resolve(value.study_dir) !== value.study_dir || value.study_dir.includes('\0')) throw new Error();
    return {format:value.format, study_dir:value.study_dir};
  } catch { throw new Error('study_config_invalid'); }
}

// Every component under the root must be a real entry, never a symlink or junction.
function studyRoot(root) {
  let stat;
  try { stat = studyFs.lstatSync(root); } catch { studyFail('study_dir_unavailable'); }
  if (stat.isSymbolicLink() || !stat.isDirectory()) studyFail('study_path_forbidden');
  let real;
  try { real = studyFs.realpathSync.native(root); } catch { studyFail('study_dir_unavailable'); }
  if (!studySameRoot(real, root)) studyFail('study_path_forbidden');
  return real;
}
function studyEntry(root, parts, kind) {
  const real = studyRoot(root);
  let current = root, stat;
  for (const part of parts) {
    current = studyPath.join(current, part);
    try { stat = studyFs.lstatSync(current); }
    catch (error) { studyFail(error.code === 'ENOENT' ? 'study_file_missing' : 'study_dir_unavailable'); }
    if (stat.isSymbolicLink()) studyFail('study_path_forbidden');
  }
  if (kind === 'dir' ? !stat.isDirectory() : !stat.isFile()) studyFail('study_path_forbidden');
  let resolved;
  try { resolved = studyFs.realpathSync.native(current); } catch { studyFail('study_dir_unavailable'); }
  if (!studySameRoot(resolved, studyPath.join(real, ...parts))) studyFail('study_path_forbidden');
  return current;
}
function studyRead(root, parts, limit) {
  const path = studyEntry(root, parts, 'file');
  let fd;
  try {
    fd = studyFs.openSync(path, 'r');
    const stat = studyFs.fstatSync(fd);
    if (!stat.isFile()) studyFail('study_path_forbidden');
    if (stat.size > limit) studyFail('study_file_too_large');
    const bytes = studyFs.readFileSync(fd);
    if (bytes.length > limit) studyFail('study_file_too_large');
    return bytes.toString('utf8').replace(/^﻿/, '');
  } catch (error) {
    if (error instanceof StudyInputError) throw error;
    studyFail('study_dir_unavailable');
  } finally { if (fd !== undefined) studyFs.closeSync(fd); }
}
function studyJson(root, name, limit) {
  try { const value = JSON.parse(studyRead(root, ['state', name], limit)); if (studyObject(value)) return value; }
  catch (error) { if (error instanceof StudyInputError) throw error; }
  studyFail('study_snapshot_invalid');
}
function studyArgs(args, allowed, required = []) {
  if (!studyObject(args) || Object.keys(args).some(key => !allowed.includes(key)) || required.some(key => !Object.hasOwn(args, key))) studyFail('invalid_request');
}
function studySubject(value) {
  if (value === undefined) return undefined;
  if (typeof value !== 'string' || !value.trim() || [...value].length > 50 || /[\0\r\n]/.test(value)) studyFail('invalid_study_subject');
  return value.trim();
}
const studyValidDate = value => typeof value === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(value)
  && Number.isFinite(Date.parse(value + 'T00:00:00Z')) && new Date(value + 'T00:00:00Z').toISOString().slice(0, 10) === value;
const studyDay = (date, delta) => { const d = new Date(date + 'T00:00:00Z'); d.setUTCDate(d.getUTCDate() + delta); return d.toISOString().slice(0, 10); };
function studyClock(time) {
  const parts = Object.fromEntries(new Intl.DateTimeFormat('en-CA', {timeZone:STUDY_TIME_ZONE, year:'numeric', month:'2-digit', day:'2-digit',
    hour:'2-digit', minute:'2-digit', second:'2-digit', hourCycle:'h23'}).formatToParts(new Date(time)).map(part => [part.type, part.value]));
  return {date:`${parts.year}-${parts.month}-${parts.day}`, stamp:`${parts.hour}${parts.minute}${parts.second}`};
}
// "## 日语（25 分钟）" → 日语
const studyHeading = line => line.slice(3).split(/[（(]/)[0].trim();
function studyTodayPayload(text, today, subject) {
  const lines = text.replace(/\r\n/g, '\n').split('\n');
  const match = /^# 学习单 (\d{4}-\d{2}-\d{2})(?:\s|$)/.exec(lines[0] ?? '');
  const date = match && studyValidDate(match[1]) ? match[1] : null;
  const sections = [];let header = [];
  for (const line of lines) {
    if (line.startsWith('## ')) sections.push({subject:studyHeading(line), lines:[line]});
    else if (sections.length) sections.at(-1).lines.push(line);
    else header.push(line);
  }
  const subjects = sections.map(section => section.subject);
  const base = {date, today, is_today:date === today, subjects};
  if (subject === undefined) return {...base, content:text.replace(/\r\n/g, '\n').trimEnd()};
  const section = sections.find(item => item.subject === subject);
  if (!section) studyFail('study_subject_not_found');
  return {...base, subject, header:header.join('\n').trimEnd(), content:section.lines.join('\n').trimEnd()};
}
function studyProgressPayload(ledger, today, subject) {
  if (!Array.isArray(ledger.records) || !Array.isArray(ledger.practice)) studyFail('study_snapshot_invalid');
  const fields = row => studyObject(row) && studyObject(row.fields) ? row.fields : {};
  const weekStart = studyDay(today, -6), bySubject = new Map();
  const entry = name => {
    if (!bySubject.has(name)) bySubject.set(name, {subject:name, total:0, mastery:{掌握:0, 模糊:0, 未学:0}, due_today:0,
      last_7_days:{answered:0, correct:0, accuracy:null}, weak_points:[]});
    return bySubject.get(name);
  };
  for (const row of ledger.records) {
    const f = fields(row);
    if (typeof f.科目 !== 'string' || subject !== undefined && f.科目 !== subject) continue;
    const item = entry(f.科目);item.total++;
    if (Object.hasOwn(item.mastery, f.掌握度)) item.mastery[f.掌握度]++;
    if (typeof f.下次复习 === 'string' && studyValidDate(f.下次复习.slice(0, 10)) && f.下次复习.slice(0, 10) <= today) item.due_today++;
    if (Number.isSafeInteger(f.错次) && f.错次 > 0 && typeof f.知识点 === 'string')
      item.weak_points.push({知识点:f.知识点, 错次:f.错次, 掌握度:f.掌握度 ?? null, 下次复习:typeof f.下次复习 === 'string' ? f.下次复习.slice(0, 10) : null});
  }
  for (const row of ledger.practice) {
    const f = fields(row);
    if (typeof f.科目 !== 'string' || subject !== undefined && f.科目 !== subject || typeof f.时间 !== 'string') continue;
    const time = Date.parse(f.时间);
    if (!Number.isFinite(time)) continue;
    const day = studyClock(time).date;
    if (day < weekStart || day > today || !['对', '错', '不会'].includes(f.结果)) continue;
    const item = entry(f.科目);item.last_7_days.answered++;if (f.结果 === '对') item.last_7_days.correct++;
  }
  const subjects = [...bySubject.values()].map(item => ({...item,
    last_7_days:{...item.last_7_days, accuracy:item.last_7_days.answered ? Math.round(item.last_7_days.correct / item.last_7_days.answered * 1000) / 1000 : null},
    weak_points:item.weak_points.sort((a, b) => b.错次 - a.错次 || a.知识点.localeCompare(b.知识点)).slice(0, 10)}));
  if (subject !== undefined && !subjects.length) studyFail('study_subject_not_found');
  return {pulled_at:typeof ledger.pulled_at === 'string' ? ledger.pulled_at : null, today, subjects};
}
function studyResultContent(value) {
  if (typeof value !== 'string' || /[\0-\x08\x0b\x0c\x0e-\x1f\x7f]/.test(value)) studyFail('invalid_study_result');
  const text = value.replace(/^﻿/, '').replace(/\r\n/g, '\n').trim();
  if (!text || [...text].length > STUDY_LIMITS.resultChars) studyFail('study_result_too_long');
  const match = /^【学习结果】(\d{4}-\d{2}-\d{2}) ([^\s][^\n]{0,49})$/.exec(text.split('\n')[0].trimEnd());
  if (!match || !studyValidDate(match[1])) studyFail('invalid_study_result_header');
  return text;
}

export function createStudyTools({studyDir, frontend, now = () => Date.now()}) {
  if (typeof studyDir !== 'string' || !studyPath.isAbsolute(studyDir) || !Object.hasOwn(STUDY_FRONTENDS, frontend)) throw new Error('invalid_study_configuration');
  const today = () => studyClock(now()).date;
  const handlers = {
    async study_today(args = {}) {
      studyArgs(args, ['subject']);
      return studyTodayPayload(studyRead(studyDir, ['today.md'], STUDY_LIMITS.today), today(), studySubject(args.subject));
    },
    async study_source(args = {}) {
      studyArgs(args, ['title', 'offset']);
      if (args.title === undefined && args.offset !== undefined) studyFail('invalid_request');
      if (args.title !== undefined && (typeof args.title !== 'string' || !args.title.trim() || [...args.title].length > 200)) studyFail('invalid_study_title');
      if (args.offset !== undefined && (!Number.isSafeInteger(args.offset) || args.offset < 0)) studyFail('invalid_study_offset');
      const snapshot = studyJson(studyDir, 'sources.json', STUDY_LIMITS.sources);
      if (!Array.isArray(snapshot.sources)) studyFail('study_snapshot_invalid');
      const sources = snapshot.sources.filter(item => studyObject(item) && typeof item.title === 'string' && typeof item.document?.content === 'string');
      const url = item => typeof item.url === 'string' ? item.url : null;
      if (args.title === undefined) return {pulled_at:snapshot.pulled_at ?? null, sources:sources.map(item => ({title:item.title, url:url(item), chars:[...item.document.content].length}))};
      const found = sources.find(item => item.title.trim() === args.title.trim());
      if (!found) studyFail('study_source_not_found');
      const chars = [...found.document.content], offset = args.offset ?? 0;
      if (offset > chars.length) studyFail('invalid_study_offset');
      const end = Math.min(chars.length, offset + STUDY_LIMITS.sourceChars);
      return {pulled_at:snapshot.pulled_at ?? null, title:found.title, url:url(found), total_chars:chars.length, offset,
        content:chars.slice(offset, end).join(''), next_offset:end < chars.length ? end : null};
    },
    async study_progress(args = {}) {
      studyArgs(args, ['subject']);
      return studyProgressPayload(studyJson(studyDir, 'ledger.json', STUDY_LIMITS.ledger), today(), studySubject(args.subject));
    },
    async study_result(args = {}) {
      studyArgs(args, ['content'], ['content']);
      const text = studyResultContent(args.content);
      const inbox = studyEntry(studyDir, ['inbox'], 'dir');
      const clock = studyClock(now()), name = `${clock.date}-${clock.stamp}-${STUDY_FRONTENDS[frontend]}.md`;
      if (!/^\d{4}-\d{2}-\d{2}-\d{6}-(?:claude|chatgpt|gemini)\.md$/.test(name)) studyFail('invalid_study_result');
      let fd;
      try { fd = studyFs.openSync(studyPath.join(inbox, name), 'wx', 0o600); }
      catch (error) { studyFail(error.code === 'EEXIST' ? 'study_result_exists' : 'study_dir_unavailable'); }
      try { studyFs.writeFileSync(fd, text + '\n', 'utf8'); }
      catch { studyFail('study_result_write_failed'); }
      finally { studyFs.closeSync(fd); }
      return {written:true, file:'inbox/' + name, chars:[...text].length};
    },
  };
  return {tools:STUDY_TOOLS, handlers};
}
