import 'package:flutter_test/flutter_test.dart';
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
}

TimelineCardModel _card(String id) {
  return TimelineCardModel(
    id: id,
    timestamp: DateTime(2026, 5, 31),
    tags: const [],
    status: 'completed',
    uiConfigs: const [],
  );
}
