import { fail } from './cli.mjs';

const text = 'text', select = 'select', number = 'number', date = 'datetime';
export const SCHEMA = Object.freeze({
  ledger: { 知识点: text, 科目: select, 来源: text, 掌握度: select, 最近结果: select,
    连对: number, 错次: number, 上次练习: date, 下次复习: date, 备注: text },
  practice: { 时间: date, 知识点: text, 科目: select, 结果: select, 纠正: text, 渠道: select, 学习单日期: date },
  inbox: { 内容: text, 渠道: select, 状态: select, 入账日期: date },
});
export const OPTIONS = Object.freeze({
  掌握度: ['未学', '模糊', '掌握'], 最近结果: ['对', '错', '不会'], 结果: ['对', '错', '不会'],
  渠道: ['Codex', 'dot', 'Gemini', '手动'], 状态: ['待入账', '已入账'],
});
export function object(value) { return value !== null && typeof value === 'object' && !Array.isArray(value); }
export function validDate(value) {
  return typeof value === 'string' && /^\d{4}-\d{2}-\d{2}$/u.test(value) &&
    Number(value.slice(0, 4)) >= 1900 && Number(value.slice(0, 4)) <= 9999 &&
    Number.isFinite(Date.parse(value)) && new Date(value).toISOString().slice(0, 10) === value;
}
export function validateConfig(config) {
  if (!object(config) || typeof config.base_token !== 'string' || !config.base_token ||
      !Array.isArray(config.subjects) || !config.subjects.length ||
      config.subjects.some(v => typeof v !== 'string' || !v.trim()) || !object(config.tables)) fail('config_invalid');
  for (const [table, schema] of Object.entries(SCHEMA)) {
    const conf = config.tables[table];
    if (!object(conf) || typeof conf.name !== 'string' || !conf.name || !object(conf.fields) ||
        Object.keys(conf.fields).length !== Object.keys(schema).length ||
        Object.keys(schema).some(k => typeof conf.fields[k] !== 'string' || !conf.fields[k]) ||
        new Set(Object.values(conf.fields)).size !== Object.keys(schema).length) fail('config_invalid');
  }
  if (new Set(Object.values(config.tables).map(t => t.name)).size !== 3) fail('config_invalid');
}
export function validateFields(fields, table, config, required = []) {
  if (!object(fields) || !Object.keys(fields).length) fail('outbox_invalid_field');
  for (const [key, value] of Object.entries(fields)) {
    if (!Object.hasOwn(SCHEMA[table], key)) fail('outbox_invalid_field');
    const kind = SCHEMA[table][key];
    if (kind === 'number') {
      if (!Number.isSafeInteger(value) || value < 0) fail('outbox_invalid_number');
    } else if (kind === 'datetime') {
      if (key === '时间') {
        if (typeof value !== 'string' || !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{3})?(?:Z|[+-]\d{2}:\d{2})$/u.test(value) ||
            !validDate(value.slice(0, 10)) || !Number.isFinite(Date.parse(value)) ||
            Number(value.slice(11, 13)) > 23 || Number(value.slice(14, 16)) > 59 || Number(value.slice(17, 19)) > 59) fail('outbox_invalid_date');
      } else if (!validDate(value)) fail('outbox_invalid_date');
    } else if (kind === 'select') {
      const allowed = key === '科目' ? config.subjects : OPTIONS[key];
      if (!allowed.includes(value)) fail('outbox_invalid_option');
    } else if (typeof value !== 'string' || !value.trim() || value.includes('\0')) fail('outbox_invalid_text');
    if (key === '来源') {
      const match = /^\[([^\]\r\n]+)\]\((https:\/\/[^\s)]+)\)$/u.exec(value);
      if (!match) fail('outbox_invalid_source');
      try { const url = new URL(match[2]); if (url.username || url.password || !/^\/(docx|wiki)\//u.test(url.pathname)) fail('outbox_invalid_source'); }
      catch { fail('outbox_invalid_source'); }
    }
  }
  if (required.some(key => !Object.hasOwn(fields, key))) fail('outbox_missing_field');
}
export function encodeFields(fields, table, config) {
  return Object.fromEntries(Object.entries(fields).map(([key, value]) => [config.tables[table].fields[key],
    SCHEMA[table][key] === 'select' ? [value] : SCHEMA[table][key] === 'datetime' && key !== '时间' ? `${value} 00:00` : value]));
}
export function decodeRow(row, table, config) {
  const fields = {}, snapshot = {};
  for (const [key, remote] of Object.entries(config.tables[table].fields)) {
    const value = row[remote] ?? null;
    snapshot[key] = value;
    fields[key] = SCHEMA[table][key] === 'select' && Array.isArray(value) ? value[0] ?? null :
      SCHEMA[table][key] === 'datetime' && key !== '时间' && typeof value === 'string' ? value.slice(0, 10) : value;
  }
  return { record_id: row.record_id, fields, snapshot };
}
