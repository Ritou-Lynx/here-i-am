import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/memory_v3/services/query_log_service.dart';

void main() {
  group('QueryLogEntry', () {
    test('round-trips top card hits for bad-case inspection', () {
      const entry = QueryLogEntry(
        query: '我上次喝咖啡是什么时候',
        timestamp: 1720000000000,
        resultCount: 1,
        topStrategy: 'expanded',
        topCards: [
          QueryLogCardHit(
            id: 'card_1',
            title: '午后拿铁',
            dropletLabel: '喝了拿铁',
            type: 'event',
          ),
        ],
      );

      final decoded = QueryLogEntry.fromJson(entry.toJson());

      expect(decoded.query, entry.query);
      expect(decoded.resultCount, 1);
      expect(decoded.topStrategy, 'expanded');
      expect(decoded.topCards, hasLength(1));
      expect(decoded.topCards.single.id, 'card_1');
      expect(decoded.actualSummary, '喝了拿铁');
    });

    test('keeps old log entries readable when top cards are absent', () {
      final decoded = QueryLogEntry.fromJson({
        'query': '不存在的关键词',
        'timestamp': 1720000000000,
        'resultCount': 0,
        'topStrategy': 'none',
      });

      expect(decoded.topCards, isEmpty);
      expect(decoded.actualSummary, '无召回结果');
    });
  });
}
