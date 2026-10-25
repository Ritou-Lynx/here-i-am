import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:memex/data/personal_data_hub/food_models.dart';
import 'package:memex/data/personal_data_hub/food_service.dart';
import 'package:memex/ui/food/widgets/food_screen.dart';

final _today = DateTime(2026, 10, 24, 12);

class _FakeFoodReader implements FoodReader {
  final events = StreamController<void>.broadcast();
  bool empty = false;

  @override
  Stream<void> get changes => events.stream;

  @override
  Future<FoodDaySnapshot> read(DateTime date) async {
    final key = foodDateKey(date);
    if (empty || key != '2026-10-24') return FoodDaySnapshot(date: key);
    return FoodDaySnapshot(
      date: key,
      entries: [_entry],
      totals: _entry.totals,
    );
  }
}

const _item = FoodItem(
  name: '合成面条',
  foodSource: 'model',
  foodId: null,
  grams: 200,
  gramsLow: 180,
  gramsHigh: 220,
  kcal: 300,
  proteinG: 15,
  fatG: 10,
  carbG: 40,
  basis: 'model_guess',
  confidence: 'low',
);

final _entry = FoodEntry(
  id: 'entry-1',
  eatenAt: DateTime.parse('2026-10-24T12:00:00+08:00'),
  localDate: '2026-10-24',
  meal: 'lunch',
  title: '合成午餐',
  note: '以虚构餐盘作参照',
  inputKind: 'photo',
  items: const [_item],
  totals: const FoodTotals(
    kcal: 300,
    kcalLow: 270,
    kcalHigh: 330,
    proteinG: 15,
    fatG: 10,
    carbG: 40,
  ),
  userCorrected: false,
  voided: false,
  originDeviceId: 'frontend:chatgpt_web',
);

void main() {
  late _FakeFoodReader reader;

  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    reader = _FakeFoodReader();
  });

  tearDown(() => reader.events.close());

  Future<void> show(WidgetTester tester, {DateTime Function()? clock}) async {
    await tester.binding.setSurfaceSize(const Size(430, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: FoodScreen(service: reader, clock: clock ?? () => _today),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows total range, macro bars and meal card', (tester) async {
    await show(tester);
    expect(find.text('约 300 千卡（270–330）'), findsOneWidget);
    expect(find.text('蛋白 15 克 · 20%'), findsOneWidget);
    expect(find.text('脂肪 10 克 · 30%'), findsOneWidget);
    expect(find.text('碳水 40 克 · 53%'), findsOneWidget);
    expect(find.byKey(const ValueKey('food-macro-蛋白')), findsOneWidget);
    expect(find.textContaining('合成午餐'), findsOneWidget);
    expect(find.textContaining('ChatGPT'), findsOneWidget);
    expect(find.byKey(const ValueKey('food-confidence-low')), findsOneWidget);
  });

  testWidgets('expands a card into item grams, source and confidence',
      (tester) async {
    await show(tester);
    await tester.tap(find.byKey(const ValueKey('food-entry-entry-1')));
    await tester.pumpAndSettle();
    expect(find.text('置信度：低'), findsOneWidget);
    expect(find.text('以虚构餐盘作参照'), findsOneWidget);
    expect(
      find.text('合成面条 · 200 克（180–220） · 模型估 · 低'),
      findsOneWidget,
    );
  });

  testWidgets('empty day and date switching stay read only', (tester) async {
    reader.empty = true;
    await show(tester);
    expect(find.text('这一天还没有饮食记录。'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('food-previous-day')));
    await tester.pumpAndSettle();
    expect(find.text('2026-10-23'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(find.byType(FloatingActionButton), findsNothing);
  });

  testWidgets('stream changes refresh the selected day', (tester) async {
    await show(tester);
    reader.empty = true;
    reader.events.add(null);
    await tester.pumpAndSettle();
    expect(find.text('这一天还没有饮食记录。'), findsOneWidget);
  });

  testWidgets('before 04:00 starts on the previous business day',
      (tester) async {
    await show(tester, clock: () => DateTime(2026, 10, 24, 3, 59));
    expect(find.text('今天 · 2026-10-23'), findsOneWidget);
    expect(find.text('这一天还没有饮食记录。'), findsOneWidget);
  });
}
