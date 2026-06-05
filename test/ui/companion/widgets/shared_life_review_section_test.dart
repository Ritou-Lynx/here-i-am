import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/services/shared_life_memory_service.dart';
import 'package:memex/ui/companion/widgets/shared_life_review_section.dart';
import 'package:memex/utils/user_storage.dart';

void main() {
  setUpAll(UserStorage.initL10n);

  testWidgets('shared life review card shows extracted title and card details',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SharedLifeReviewCard(
            entity: SharedLifeEntitySnapshot(
              id: 'entity-1',
              entityType: 'task',
              title: 'Buy train tickets',
              status: 'active',
              state: {
                'time': 'Friday',
                'place': 'Shanghai',
                'tags': ['travel', 'Shanghai'],
              },
              updatedAt: 1,
            ),
          ),
        ),
      ),
    );

    expect(find.text('Buy train tickets'), findsOneWidget);
    expect(find.text(UserStorage.l10n.companionLifeTask), findsWidgets);
    expect(find.text(UserStorage.l10n.companionLifeActive), findsOneWidget);
    expect(find.text('Friday'), findsOneWidget);
    expect(find.text('Shanghai'), findsOneWidget);
    expect(find.text('#travel'), findsOneWidget);
  });
}
