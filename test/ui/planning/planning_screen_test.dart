import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:memex/data/personal_data_hub/planning_models.dart';
import 'package:memex/data/personal_data_hub/planning_service.dart';
import 'package:memex/ui/planning/widgets/planning_screen.dart';
import '../../data/personal_data_hub/planning_fixtures.dart';

class FakePlanningReader implements PlanningReader {
  final events = StreamController<void>.broadcast();
  int edition = 1;
  bool configured = true;
  PlanningConnection connection = PlanningConnection.offline;
  final statuses = <String, String>{};
  final operations = <String, PlanningOperation>{};
  final actions = <PlanningStatusAction>[];
  @override
  Stream<void> get changes => events.stream;
  @override
  Future<PlanningSnapshot> read(DateTime date) async => PlanningSnapshot(
      day: PlanningDay(planningDay(version: edition)),
      week: PlanningWeek(planningWeek()),
      items: {
        for (final id in ['a', 'b'])
          id: PlanningItem({
            ...planningItem(id,
                title: id == 'a' ? '事项甲' : '事项乙',
                area: id == 'a' ? '未归类' : '学习',
                status: statuses[id] ?? '待办'),
            if (operations[id]?.state == 'pending') 'sync_label': '未同步',
          })
      },
      operations: Map.of(operations),
      statusWritable: configured,
      connection: connection);
  @override
  Future<String> setStatus(String id, PlanningStatusAction action) async {
    actions.add(action);
    statuses[id] = action.value;
    operations[id] = PlanningOperation('op-$id', id, 'pending', null);
    events.add(null);
    return 'op-$id';
  }

  @override
  Future<void> synchronize() async {
    connection = PlanningConnection.online;
    for (final id in operations.keys.toList()) {
      operations[id] = PlanningOperation('op-$id', id, 'accepted', null);
    }
    events.add(null);
  }

  void reject(String id, String state) {
    statuses.remove(id);
    operations[id] = PlanningOperation('op-$id', id, state, 'user_conflict');
    events.add(null);
  }
}

void main() {
  late FakePlanningReader reader;
  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    reader = FakePlanningReader();
  });
  tearDown(() async {
    await reader.events.close();
  });

  Future<void> show(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 1500));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
        home: PlanningScreen(service: reader, clock: () => planningTestNow)));
    await tester.pumpAndSettle();
  }

  testWidgets(
      'today preserves queue order, generated time, decisions and lights out',
      (tester) async {
    await show(tester);
    expect(find.text('今日单 · 第 1 版'), findsOneWidget);
    expect(find.text('待拍板'), findsOneWidget);
    expect(find.text('这次改了什么'), findsOneWidget);
    expect(find.textContaining('电脑离线'), findsOneWidget);
    expect(find.textContaining('新记的事等电脑上线后安排'), findsOneWidget);
    final b = tester.getTopLeft(find.byKey(const ValueKey('plan-item-b')));
    final a = tester.getTopLeft(find.byKey(const ValueKey('plan-item-a')));
    expect(b.dy, lessThan(a.dy));
    await tester.scrollUntilVisible(find.text('今晚关灯'), 300,
        scrollable: find
            .descendant(
                of: find.byKey(const PageStorageKey('planning-today')),
                matching: find.byType(Scrollable))
            .first);
    expect(find.text('今晚关灯'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(find.byType(ReorderableListView), findsNothing);
  });

  testWidgets(
      'new stream edition updates automatically and unclassified filter persists',
      (tester) async {
    await show(tester);
    await tester.tap(find.widgetWithText(ChoiceChip, '未归类'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('plan-item-a')), findsOneWidget);
    expect(find.byKey(const ValueKey('plan-item-b')), findsNothing);
    reader.edition = 2;
    reader.events.add(null);
    await tester.pumpAndSettle();
    expect(find.text('今日单 · 第 2 版'), findsOneWidget);
    expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '未归类'))
            .selected,
        true);
  });

  testWidgets(
      'offline complete shows pending then accepted after connection recovery',
      (tester) async {
    await show(tester);
    final button = find.byKey(const ValueKey('plan-complete-b'));
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(reader.actions, [PlanningStatusAction.complete]);
    expect(find.text('待同步'), findsOneWidget);
    await reader.synchronize();
    await tester.pumpAndSettle();
    expect(find.text('已接受'), findsOneWidget);
    expect(find.text('待同步'), findsNothing);
  });

  testWidgets(
      'offline abandon shows the local choice then restores canonical status on conflict',
      (tester) async {
    await show(tester);
    final button = find.byKey(const ValueKey('plan-abandon-b'));
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(reader.actions, [PlanningStatusAction.abandon]);
    expect(find.text('学习 · 放弃 · 深块 1 块'), findsOneWidget);
    expect(find.text('待同步'), findsOneWidget);

    reader.reject('b', 'needs_resolution');
    await tester.pumpAndSettle();
    expect(find.text('学习 · 待办 · 深块 1 块'), findsOneWidget);
    expect(find.text('需要拍板，请在电脑端处理'), findsOneWidget);
  });

  for (final state in ['rejected', 'needs_resolution']) {
    testWidgets(
        '$state feedback restores canonical status and disables repeat action',
        (tester) async {
      await show(tester);
      reader.reject('b', state);
      await tester.pumpAndSettle();
      expect(find.text(state == 'rejected' ? '未接受，请在电脑端处理' : '需要拍板，请在电脑端处理'),
          findsOneWidget);
      expect(
          tester
              .widget<TextButton>(find.byKey(const ValueKey('plan-complete-b')))
              .onPressed,
          isNull);
      expect(find.text('学习 · 待办 · 深块 1 块'), findsOneWidget);
    });
  }

  testWidgets('week shows capacity, quota, completion, debt and unknown values',
      (tester) async {
    await show(tester);
    await tester.tap(find.text('本周'));
    await tester.pumpAndSettle();
    expect(find.text('2026-W41'), findsOneWidget);
    expect(find.textContaining('预计容量：深块 10'), findsOneWidget);
    expect(find.textContaining('实际容量：深块 2 · 长块 未提供'), findsOneWidget);
    expect(find.text('已完成 1 · 本周还排了 2'), findsOneWidget);
    expect(find.textContaining('来自 2026-W40'), findsOneWidget);
  });

  testWidgets('without owner authorization the page is read only',
      (tester) async {
    reader.configured = false;
    await show(tester);
    expect(find.textContaining('当前只读'), findsOneWidget);
    expect(
        tester
            .widget<TextButton>(find.byKey(const ValueKey('plan-complete-b')))
            .onPressed,
        isNull);
    expect(
        tester
            .widget<TextButton>(find.byKey(const ValueKey('plan-abandon-b')))
            .onPressed,
        isNull);
  });

  testWidgets('stream interruption preserves cache and next event recovers',
      (tester) async {
    await show(tester);
    reader.events.addError(StateError('synthetic connection loss'));
    await tester.pumpAndSettle();
    expect(find.textContaining('变更连接中断'), findsOneWidget);
    expect(find.text('今日单 · 第 1 版'), findsOneWidget);
    reader.edition = 3;
    reader.events.add(null);
    await tester.pumpAndSettle();
    expect(find.text('今日单 · 第 3 版'), findsOneWidget);
    expect(find.textContaining('变更连接中断'), findsNothing);
  });

  testWidgets('narrow phone viewport has no layout overflow', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
        home: PlanningScreen(service: reader, clock: () => planningTestNow)));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('本周'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
