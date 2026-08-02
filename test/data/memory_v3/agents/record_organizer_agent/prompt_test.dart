import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/memory_v3/agents/record_organizer_agent/prompt.dart';

void main() {
  group('recordOrganizerSystemPromptV3', () {
    test('enforces ONE TO-DO PER EVENT across split cards', () {
      final prompt = recordOrganizerSystemPromptV3();
      expect(prompt, contains('ONE TO-DO PER EVENT'));
      expect(prompt, contains('AT MOST ONE of them may be a to-do type'));
      expect(
        prompt,
        contains('the types shown in the Schedule panel'),
      );
      // Money facets must route to non-todo domains (Ledger), not more todos.
      expect(prompt, contains('expense_entry / shopping_order / income_entry'));
      expect(prompt, contains('background / detail / outcome facets'));
    });

    test('keeps the spider-man example that triggered the rule', () {
      final prompt = recordOrganizerSystemPromptV3();
      expect(prompt, contains('买了蜘蛛侠电影票 68.9 元'));
      expect(
        prompt,
        contains('schedule "周六看蜘蛛侠" + task "买爆米花" + task "买电影票"'),
      );
      expect(prompt, contains('the same event now appears 3 times'));
    });

    test('still contains dedupe and existing-card context sections', () {
      final prompt = recordOrganizerSystemPromptV3(
        relevantExistingCardSummaries: const ['「看蜘蛛侠电影」@ schedule'],
      );
      expect(prompt, contains('DEDUPE (task / schedule / plan)'));
      expect(prompt, contains('Existing Memory Cards that may overlap'));
      expect(prompt, contains('「看蜘蛛侠电影」@ schedule'));
    });
  });
}
