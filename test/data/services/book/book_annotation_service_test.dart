import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/services/book/book_annotation_service.dart';
import 'package:memex/db/app_database.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final fts5Available = _checkFts5();

  late AppDatabase db;
  late BookAnnotationService service;

  setUp(() {
    if (!fts5Available) return;
    db = AppDatabase.forTesting(NativeDatabase.memory());
    service = BookAnnotationService(db: db);
  });

  tearDown(() async {
    if (!fts5Available) return;
    await db.close();
  });

  test('creates a stable quote anchor with surrounding context', () async {
    if (!fts5Available) return;
    const content = '开头的一段文字。她在雨里停下来，看见树叶发亮。结尾。';
    final start = content.indexOf('她在雨里');
    final end = start + '她在雨里停下来'.length;

    final annotation = await service.create(
      bookId: 'book-1',
      chapterNumber: 2,
      chapterContent: content,
      startOffset: start,
      endOffset: end,
      note: '这里的停顿让我觉得她终于开始自己选择。',
    );

    expect(annotation.quote, '她在雨里停下来');
    expect(annotation.note, '这里的停顿让我觉得她终于开始自己选择。');
    expect(annotation.prefixContext, contains('开头的一段文字'));
    expect(annotation.suffixContext, contains('看见树叶发亮'));
    expect(annotation.contentFingerprint, hasLength(64));
  });

  test('rejects overlapping highlights in the same chapter', () async {
    if (!fts5Available) return;
    const content = '一二三四五六七八九十';
    await service.create(
      bookId: 'book-1',
      chapterNumber: 1,
      chapterContent: content,
      startOffset: 2,
      endOffset: 6,
    );

    expect(
      () => service.create(
        bookId: 'book-1',
        chapterNumber: 1,
        chapterContent: content,
        startOffset: 5,
        endOffset: 8,
      ),
      throwsA(isA<BookAnnotationOverlapException>()),
    );
  });

  test('updates notes and soft-deletes without returning deleted rows',
      () async {
    if (!fts5Available) return;
    const content = '值得留下的一句话。';
    final annotation = await service.create(
      bookId: 'book-1',
      chapterNumber: 1,
      chapterContent: content,
      startOffset: 0,
      endOffset: 6,
    );

    await service.updateNote(annotation.id, '后来补上的想法');
    var rows = await service.listForBook('book-1');
    expect(rows.single.note, '后来补上的想法');

    await service.delete(annotation.id);
    rows = await service.listForBook('book-1');
    expect(rows, isEmpty);
  });
}

bool _checkFts5() {
  try {
    final db = sqlite3.sqlite3.openInMemory();
    db.execute('CREATE VIRTUAL TABLE fts_probe USING fts5(content)');
    db.dispose();
    return true;
  } catch (_) {
    return false;
  }
}
