import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/memory_v3/retrieval/intent_classifier.dart';
import 'package:memex/data/memory_v3/retrieval/query_expander.dart';

void main() {
  test('expands finance wording for spending recall', () {
    final plan = QueryExpander.expand(
      '我上次花钱买了什么',
      intent: QueryIntent.factLookup,
    );

    final expanded = plan.variants.firstWhere(
      (v) => v.strategy == QueryExpansionStrategy.expanded,
    );

    expect(expanded.query, contains('消费'));
    expect(expanded.query, contains('支出'));
    expect(expanded.query, contains('购买'));
  });

  test('adds beverage terms for coffee recall', () {
    final plan = QueryExpander.expand('咖啡');
    final expanded = plan.variants.firstWhere(
      (v) => v.strategy == QueryExpansionStrategy.expanded,
    );

    expect(expanded.query, contains('拿铁'));
    expect(expanded.query, contains('饮料'));
  });

  test('creates a relaxed variant from distinctive terms', () {
    final plan = QueryExpander.expand('你还记得我有没有买咖啡吗');
    final relaxed = plan.variants.firstWhere(
      (v) => v.strategy == QueryExpansionStrategy.relaxed,
    );

    expect(relaxed.query, contains('买'));
    expect(relaxed.query, contains('咖啡'));
    expect(relaxed.query, isNot(contains('有没有')));
  });
}
