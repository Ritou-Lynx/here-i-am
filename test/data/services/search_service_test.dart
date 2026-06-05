import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/services/search_service.dart';
import 'package:memex/domain/models/system_event.dart';

void main() {
  final searchService = SearchService.instance;

  group('SearchService FTS enqueue filtering', () {
    test('skips card updates that only change non-indexed fields', () {
      final record = DataChangeRecord(
        op: DataChangeOp.update,
        ns: DataChangeNs.card,
        documentKey: 'card-1',
        before: const {
          'title': 'Title',
          'tags': ['one'],
          'content': 'Body',
          'insight': {'text': 'Summary'},
          'comments': [],
        },
        after: const {
          'title': 'Title',
          'tags': ['one'],
          'content': 'Body',
          'insight': {'text': 'Summary'},
          'comments': [
            {'text': 'A new comment'},
          ],
        },
      );

      expect(
        searchService.shouldEnqueueFtsIndexUpdateForTesting(record),
        isFalse,
      );
    });

    test('enqueues card updates when indexed fields change', () {
      final record = DataChangeRecord(
        op: DataChangeOp.update,
        ns: DataChangeNs.card,
        documentKey: 'card-1',
        before: const {'title': 'Old title'},
        after: const {'title': 'New title'},
      );

      expect(
        searchService.shouldEnqueueFtsIndexUpdateForTesting(record),
        isTrue,
      );
    });

    test('always enqueues PKM file changes', () {
      final record = DataChangeRecord(
        op: DataChangeOp.update,
        ns: DataChangeNs.pkmFile,
        documentKey: 'notes/today.md',
      );

      expect(
        searchService.shouldEnqueueFtsIndexUpdateForTesting(record),
        isTrue,
      );
    });
  });
}
