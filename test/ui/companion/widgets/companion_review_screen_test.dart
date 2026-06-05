import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/services/shared_life_memory_service.dart';
import 'package:memex/domain/models/system_card_constants.dart';
import 'package:memex/domain/models/timeline_card_model.dart';
import 'package:memex/ui/companion/widgets/companion_review_screen.dart';

void main() {
  test('review feed hides the schedule briefing card', () {
    final cards = [
      _card(scheduleBriefingCardId),
      _card('regular-card'),
    ];

    expect(
      companionReviewCards(cards).map((card) => card.id),
      ['regular-card'],
    );
  });

  test('review feed interleaves legacy cards and shared life entities', () {
    final items = companionReviewFeedItems(
      [
        _card('older-card', DateTime(2026, 5, 31)),
        _card('newest-card', DateTime(2026, 6, 2)),
      ],
      const [
        SharedLifeEntitySnapshot(
          id: 'middle-shared-life',
          entityType: 'task',
          title: 'Buy train tickets',
          status: 'active',
          state: {},
          updatedAt: 1780272000000000,
        ),
      ],
    );

    // Entities are now converted to standard cards with "entity:" prefix.
    expect(
      items.map((card) => card.id),
      ['newest-card', 'entity:middle-shared-life', 'older-card'],
    );
  });
}

TimelineCardModel _card(String id, [DateTime? timestamp]) {
  return TimelineCardModel(
    id: id,
    timestamp: timestamp ?? DateTime(2026, 5, 31),
    tags: const [],
    status: 'completed',
    uiConfigs: const [],
  );
}
