// Google Apps Script（在你自己的 Google 账号里运行，不需要任何密钥）。
// 把 Google Drive 文件夹「here-i-am 学习同步」里的 .md 文件，逐个覆盖写进同名的 Google 文档。
// Gemini Notebook 会自动同步 Google 文档类资料，所以 Notebook 里看到的总是最新内容。
// 用法见 tools/feishu_tutor/README.md“Gemini 同步”。只读写这一个文件夹，不删除任何文件。

var FOLDER_NAME = 'here-i-am 学习同步';
var MAX_CHARS = 900000;

function syncStudyDocs() {
  var folders = DriveApp.getFoldersByName(FOLDER_NAME);
  if (!folders.hasNext()) throw new Error('找不到文件夹：' + FOLDER_NAME);
  var folder = folders.next();
  var props = PropertiesService.getScriptProperties();
  var files = folder.getFiles();
  var done = [];
  while (files.hasNext()) {
    var file = files.next();
    var name = file.getName();
    if (!/\.md$/i.test(name) || name.charAt(0) === '.') continue;
    var title = name.replace(/\.md$/i, '');
    var stamp = String(file.getLastUpdated().getTime());
    var key = 'doc:' + title;
    var known = props.getProperty(key);
    var docId = known ? JSON.parse(known).id : null;
    if (known && JSON.parse(known).stamp === stamp && docExists(docId)) continue;
    var text = file.getBlob().getDataAsString('UTF-8').replace(/^﻿/, '');
    if (text.length > MAX_CHARS) text = text.slice(0, MAX_CHARS) + '\n\n（内容过长，已截断）';
    var doc;
    if (docId && docExists(docId)) {
      doc = DocumentApp.openById(docId);
    } else {
      doc = DocumentApp.create(title);
      var docFile = DriveApp.getFileById(doc.getId());
      docFile.moveTo(folder);
    }
    doc.getBody().setText(text);
    doc.saveAndClose();
    props.setProperty(key, JSON.stringify({ id: doc.getId(), stamp: stamp }));
    done.push(title);
  }
  Logger.log('已更新：' + (done.length ? done.join('、') : '无变化'));
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
