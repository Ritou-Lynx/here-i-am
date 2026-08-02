import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/memory_v3/models/memory_card_view_data.dart';

void main() {
  group('MemoryCardViewData.structuredEventTimeMs', () {
    MemoryCardViewData card({
      String? structuredFieldsType,
      String? structuredFieldsJson,
      int? recordedAt,
      required int createdAt,
    }) {
      return MemoryCardViewData(
        id: 'c1',
        type: 'plan',
        title: '想搜来看《上将的专属配发 Omega》',
        dropletLabel: '想搜来看',
        presentationModule: '',
        retrievalText: '这篇文看着好香，mark！有空搜来看',
        valence: 0.5,
        arousal: 0.5,
        status: 'active',
        rawInput: '这篇文看着好香，mark！有空搜来看',
        recordedAt: recordedAt,
        createdAt: createdAt,
        updatedAt: createdAt,
        structuredFieldsType: structuredFieldsType,
        structuredFieldsJson: structuredFieldsJson,
      );
    }

    test('null when the card has no structured fields (recordedAt must not leak in)', () {
      final c = card(
        recordedAt: DateTime(2026, 7, 15, 9, 38, 25).millisecondsSinceEpoch,
        createdAt: DateTime(2026, 7, 15, 9, 38, 30).millisecondsSinceEpoch,
      );
      expect(c.eventTimeMs, DateTime(2026, 7, 15, 9, 38, 25).millisecondsSinceEpoch,
          reason: 'fallback path keeps recording time for review sorting');
      expect(c.structuredEventTimeMs, isNull,
          reason: 'schedule panel must see no business time -> unscheduled');
    });

    test('uses the structured anchor when present', () {
      final startAt = DateTime(2026, 8, 1, 9).toIso8601String();
      final c = card(
        structuredFieldsType: 'plan',
        structuredFieldsJson: '{"startAt": "$startAt"}',
        recordedAt: DateTime(2026, 7, 15).millisecondsSinceEpoch,
        createdAt: DateTime(2026, 7, 15).millisecondsSinceEpoch,
      );
      expect(c.structuredEventTimeMs, DateTime(2026, 8, 1, 9).millisecondsSinceEpoch);
    });

    test('null when structured fields exist but carry no time anchor', () {
      final c = card(
        structuredFieldsType: 'plan',
        structuredFieldsJson: '{"notes": "no time"}',
        recordedAt: DateTime(2026, 7, 15).millisecondsSinceEpoch,
        createdAt: DateTime(2026, 7, 15).millisecondsSinceEpoch,
      );
      expect(c.structuredEventTimeMs, isNull);
    });
  });
}
