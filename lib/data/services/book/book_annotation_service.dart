import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:memex/db/app_database.dart';
import 'package:uuid/uuid.dart';

/// Local-first storage for book highlights and user-authored notes.
///
/// The service only owns reader-domain data. It never promotes annotations to
/// Memory V3 on its own.
class BookAnnotationService {
  BookAnnotationService({required AppDatabase db}) : _db = db;

  final AppDatabase _db;
  final Uuid _uuid = const Uuid();

  Future<List<BookAnnotation>> listForChapter({
    required String bookId,
    required int chapterNumber,
  }) {
    return (_db.select(_db.bookAnnotations)
          ..where((row) =>
              row.bookId.equals(bookId) &
              row.chapterNumber.equals(chapterNumber) &
              row.deletedAt.isNull())
          ..orderBy([(row) => OrderingTerm.asc(row.startOffset)]))
        .get();
  }

  Future<List<BookAnnotation>> listForBook(String bookId) {
    return (_db.select(_db.bookAnnotations)
          ..where(
              (row) => row.bookId.equals(bookId) & row.deletedAt.isNull())
          ..orderBy([
            (row) => OrderingTerm.asc(row.chapterNumber),
            (row) => OrderingTerm.asc(row.startOffset),
          ]))
        .get();
  }

  Future<BookAnnotation?> findOverlap({
    required String bookId,
    required int chapterNumber,
    required int startOffset,
    required int endOffset,
  }) {
    return (_db.select(_db.bookAnnotations)
          ..where((row) =>
              row.bookId.equals(bookId) &
              row.chapterNumber.equals(chapterNumber) &
              row.deletedAt.isNull() &
              row.startOffset.isSmallerThanValue(endOffset) &
              row.endOffset.isBiggerThanValue(startOffset))
          ..limit(1))
        .getSingleOrNull();
  }

  Future<BookAnnotation> create({
    required String bookId,
    required int chapterNumber,
    required String chapterContent,
    required int startOffset,
    required int endOffset,
    String note = '',
    String style = 'spring_rain',
  }) async {
    final normalizedStart = math.max(0, math.min(startOffset, endOffset));
    final normalizedEnd =
        math.min(chapterContent.length, math.max(startOffset, endOffset));
    if (normalizedStart >= normalizedEnd) {
      throw ArgumentError('A book annotation requires a non-empty selection.');
    }

    final overlap = await findOverlap(
      bookId: bookId,
      chapterNumber: chapterNumber,
      startOffset: normalizedStart,
      endOffset: normalizedEnd,
    );
    if (overlap != null) {
      throw const BookAnnotationOverlapException();
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    final id = _uuid.v4();
    final prefixStart = math.max(0, normalizedStart - 32);
    final suffixEnd = math.min(chapterContent.length, normalizedEnd + 32);
    final fingerprint = sha256.convert(chapterContent.codeUnits).toString();

    await _db.into(_db.bookAnnotations).insert(
          BookAnnotationsCompanion.insert(
            id: id,
            bookId: bookId,
            chapterNumber: chapterNumber,
            startOffset: normalizedStart,
            endOffset: normalizedEnd,
            quote: chapterContent.substring(normalizedStart, normalizedEnd),
            prefixContext: Value(
              chapterContent.substring(prefixStart, normalizedStart),
            ),
            suffixContext: Value(
              chapterContent.substring(normalizedEnd, suffixEnd),
            ),
            contentFingerprint: Value(fingerprint),
            style: Value(style),
            note: Value(note.trim()),
            createdAt: now,
            updatedAt: now,
          ),
        );
    return (_db.select(_db.bookAnnotations)..where((row) => row.id.equals(id)))
        .getSingle();
  }

  Future<void> updateNote(String id, String note) {
    return (_db.update(_db.bookAnnotations)..where((row) => row.id.equals(id)))
        .write(BookAnnotationsCompanion(
      note: Value(note.trim()),
      updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
    ));
  }

  Future<void> delete(String id) {
    final now = DateTime.now().millisecondsSinceEpoch;
    return (_db.update(_db.bookAnnotations)..where((row) => row.id.equals(id)))
        .write(BookAnnotationsCompanion(
      deletedAt: Value(now),
      updatedAt: Value(now),
    ));
  }
}

class BookAnnotationOverlapException implements Exception {
  const BookAnnotationOverlapException();

  @override
  String toString() => 'The selected text already contains a highlight.';
}
