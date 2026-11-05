// Google Apps Script（在你自己的 Google 账号里运行，不需要任何密钥）。
// 把 Google Drive 文件夹「here-i-am 学习同步」里的 .md 文件，逐个覆盖写进同名的 Google 文档。
// Gemini Notebook 会自动同步 Google 文档类资料，所以 Notebook 里看到的总是最新内容。
// 用法见 tools/feishu_tutor/README.md“Gemini 同步”。只读写这一个文件夹，不删除任何文件。
// 写入走 Drive 的 Markdown 导入（同一个文档 ID 原地覆盖），不用 DocumentApp：
// 大段文本用 DocumentApp 写入时会报“文档服务发生了错误”。

var FOLDER_NAME = 'here-i-am 学习同步';
var DOC_MIME = 'application/vnd.google-apps.document';
var MAX_CHARS = 900000;

function syncStudyDocs() {
  var folders = DriveApp.getFoldersByName(FOLDER_NAME);
  if (!folders.hasNext()) throw new Error('找不到文件夹：' + FOLDER_NAME);
  var folder = folders.next();
  var props = PropertiesService.getScriptProperties();
  var files = folder.getFiles();
  var done = [], failed = [];
  while (files.hasNext()) {
    var file = files.next();
    var name = file.getName();
    if (!/\.md$/i.test(name) || name.charAt(0) === '.') continue;
    var title = name.replace(/\.md$/i, '');
    var stamp = String(file.getLastUpdated().getTime());
    var key = 'doc:' + title;
    var info = {};
    try { info = JSON.parse(props.getProperty(key) || '{}'); } catch (e) { info = {}; }
    var docId = docExists(info.id) ? info.id : findDoc(folder, title);
    if (docId && docId === info.id && info.stamp === stamp) continue;
    var text = cleanText(file.getBlob().getDataAsString('UTF-8'));
    try {
      docId = writeDoc(docId, title, folder.getId(), text);
      props.setProperty(key, JSON.stringify({ id: docId, stamp: stamp }));
      done.push(title);
    } catch (e) {
      failed.push(title + '（' + e.message + '）');
    }
  }
  Logger.log('已更新：' + (done.length ? done.join('、') : '无变化'));
  if (failed.length) throw new Error('没同步成功：' + failed.join('；'));
}

function cleanText(text) {
  text = text.replace(/^\uFEFF/, '').replace(/[\u0000-\u0008\u000B\u000C\u000E-\u001F\uFFFE\uFFFF]/g, '');
  if (text.length > MAX_CHARS) text = text.slice(0, MAX_CHARS) + '\n\n（内容过长，已截断）\n';
  return text;
}

// 有 docId 就原地覆盖（ID 不变，Notebook 里的来源不用重加）；没有就在文件夹里新建。
// 先按 Markdown 导入；万一 Markdown 转换被拒，退回纯文本。
function writeDoc(docId, title, folderId, text) {
  var lastError = '';
  var types = ['text/markdown', 'text/plain'];
  for (var i = 0; i < types.length; i++) {
    var boundary = 'hereiam' + Date.now() + i;
    var meta = docId ? {} : { name: title, mimeType: DOC_MIME, parents: [folderId] };
    var body = '--' + boundary + '\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n' +
      JSON.stringify(meta) + '\r\n--' + boundary + '\r\nContent-Type: ' + types[i] + '; charset=UTF-8\r\n\r\n' +
      text + '\r\n--' + boundary + '--\r\n';
    var url = 'https://www.googleapis.com/upload/drive/v3/files' + (docId ? '/' + docId : '') +
      '?uploadType=multipart&fields=id';
    var res = UrlFetchApp.fetch(url, {
      method: docId ? 'patch' : 'post',
      contentType: 'multipart/related; boundary=' + boundary,
      payload: Utilities.newBlob(body).getBytes(),
      headers: { Authorization: 'Bearer ' + ScriptApp.getOAuthToken() },
      muteHttpExceptions: true
    });
    var code = res.getResponseCode();
    if (code < 300) return JSON.parse(res.getContentText()).id;
    lastError = 'Drive ' + code + ' ' + res.getContentText().slice(0, 200);
  }
  throw new Error(lastError);
}

// 上次中途失败时可能已经建了同名空文档，找到就复用，不重复新建。
function findDoc(folder, title) {
  var it = folder.getFilesByName(title);
  while (it.hasNext()) {
    var f = it.next();
    if (f.getMimeType() === DOC_MIME && !f.isTrashed()) return f.getId();
  }
  return null;
}

function docExists(id) {
  if (!id) return false;
  try { return !DriveApp.getFileById(id).isTrashed(); } catch (e) { return false; }
}

// 运行一次即可：每小时自动同步一次。重复运行不会重复建触发器。
function installHourlyTrigger() {
  var triggers = ScriptApp.getProjectTriggers();
  for (var i = 0; i < triggers.length; i++) {
    if (triggers[i].getHandlerFunction() === 'syncStudyDocs') return;
  }
  ScriptApp.newTrigger('syncStudyDocs').timeBased().everyHours(1).create();
}
