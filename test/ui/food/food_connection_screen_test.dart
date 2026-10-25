import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:memex/data/personal_data_hub/food_models.dart';
import 'package:memex/data/personal_data_hub/food_service.dart';
import 'package:memex/ui/food/widgets/food_screen.dart';

class _Reader implements FoodReader {
  _Reader(this.snapshot);
  final FoodDaySnapshot snapshot;
  final events = StreamController<void>.broadcast();

  @override
  Stream<void> get changes => events.stream;

  @override
  Future<FoodDaySnapshot> read(DateTime date) async => snapshot;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('new attached reader appears without reopening the food page',
      (tester) async {
    final selected = ValueNotifier<FoodReader>(_Reader(
      const FoodDaySnapshot(date: '2026-10-25', error: '尚未连接林埃核心'),
    ));
    addTearDown(selected.dispose);
    await tester.pumpWidget(MaterialApp(
      home: ValueListenableBuilder<FoodReader>(
        valueListenable: selected,
        builder: (_, reader, __) => FoodScreen(
          service: reader,
          clock: () => DateTime(2026, 10, 25, 12),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('尚未连接林埃核心'), findsOneWidget);

    selected.value = _Reader(const FoodDaySnapshot(date: '2026-10-25'));
    await tester.pumpAndSettle();
    expect(find.text('尚未连接林埃核心'), findsNothing);
    expect(find.text('这一天还没有饮食记录。'), findsOneWidget);
  });

  testWidgets('pull to refresh invokes the supplied synchronizer',
      (tester) async {
    var syncs = 0;
    final reader = _Reader(const FoodDaySnapshot(date: '2026-10-25'));
    await tester.pumpWidget(MaterialApp(
      home: FoodScreen(
        service: reader,
        clock: () => DateTime(2026, 10, 25, 12),
        synchronize: () async => syncs++,
      ),
    ));
    await tester.pumpAndSettle();
    await tester.drag(
        find.byKey(const PageStorageKey('food-day')), const Offset(0, 400));
    await tester.pumpAndSettle();
    expect(syncs, 1);
  });
}
