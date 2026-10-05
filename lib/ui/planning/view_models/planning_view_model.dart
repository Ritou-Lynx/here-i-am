import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:memex/data/personal_data_hub/planning_models.dart';
import 'package:memex/data/personal_data_hub/planning_reminders.dart';
import 'package:memex/data/personal_data_hub/planning_service.dart';
import 'package:memex/utils/command.dart';
import 'package:memex/utils/result.dart';

class PlanningViewModel extends ChangeNotifier {
  PlanningViewModel(
      {required PlanningReader service,
      this.reminders,
      DateTime Function()? clock})
      : _service = service,
        clock = clock ?? DateTime.now {
    load = Command0<void>(() => runResultVoid(_refresh));
    synchronize = Command0<void>(() => runResultVoid(() async {
          final result = await runResultVoid(_service.synchronize);
          await _refresh();
          result.valueOrThrow;
        }));
    complete =
        Command1<void, String>((id) => _set(id, PlanningStatusAction.complete));
    abandon =
        Command1<void, String>((id) => _set(id, PlanningStatusAction.abandon));
    _subscription =
        _service.changes.listen((_) => _queueRefresh(), onError: (Object _) {
      if (_disposed) return;
      streamWarning = '变更连接中断，保留上次副本；可下拉重新同步';
      notifyListeners();
    });
  }
  final PlanningReader _service;
  final PlanningReminderSink? reminders;
  final DateTime Function() clock;
  late final Command0<void> load, synchronize;
  late final Command1<void, String> complete, abandon;
  late final StreamSubscription<void> _subscription;
  PlanningSnapshot snapshot = const PlanningSnapshot();
  String? selectedArea, streamWarning, reminderWarning;
  bool _disposed = false, _refreshing = false, _refreshAgain = false;
  Future<void>? _refreshFuture;

  List<String> get areas => {
        ...snapshot.items.values.map((item) => item.area),
        for (final quota in snapshot.week?.quotas ?? [])
          quota['area'] as String,
        for (final debt in snapshot.week?.debt ?? []) debt['area'] as String,
        if (selectedArea != null) selectedArea!,
      }.toList()
        ..sort();
  bool matches(PlanningItem item) =>
      selectedArea == null || item.area == selectedArea;
  void filterArea(String? area) {
    selectedArea = area;
    notifyListeners();
  }

  List<String> queue(String name) =>
      snapshot.day?.queue(name).where((id) {
        final item = snapshot.items[id];
        return item == null ? selectedArea == null : matches(item);
      }).toList() ??
      [];
  List<PlanningItem> get unqueued {
    final queued = {
      for (final queue in planningQueues.keys) ...?snapshot.day?.queue(queue)
    };
    return snapshot.items.values
        .where((item) =>
            !queued.contains(item.id) && !item.terminal && matches(item))
        .toList();
  }

  bool canAct(PlanningItem item) =>
      snapshot.statusWritable &&
      item.canChangeStatus &&
      snapshot.operations[item.id]?.blocksAction != true;

  Future<Result<void>> _set(String id, PlanningStatusAction action) =>
      runResultVoid(() async {
        await _service.setStatus(id, action);
        await _refresh();
      });

  void _queueRefresh() {
    if (_disposed) return;
    unawaited(runResultVoid(_refresh).then((result) {
      if (_disposed || result is! Error<void>) return;
      streamWarning = '读取更新失败，保留上次副本';
      notifyListeners();
    }));
  }

  Future<void> _refresh() {
    if (_disposed) return Future.value();
    if (_refreshing) {
      _refreshAgain = true;
      return _refreshFuture!;
    }
    _refreshing = true;
    return _refreshFuture = _readUntilCurrent().whenComplete(() {
      _refreshing = false;
    });
  }

  Future<void> _readUntilCurrent() async {
    do {
      _refreshAgain = false;
      final next = await _service.read(clock());
      if (_disposed) return;
      snapshot = next;
      streamWarning = null;
      if (reminders != null) {
        final result = await runResultVoid(() => reminders!.reconcile(
            next.domainErrors.containsKey('plan_items')
                ? const []
                : next.items.values));
        reminderWarning = result.isError ? '本机提醒尚未全部更新，稍后重试' : null;
      }
      if (!_disposed) notifyListeners();
    } while (_refreshAgain && !_disposed);
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_subscription.cancel());
    load.dispose();
    synchronize.dispose();
    complete.dispose();
    abandon.dispose();
    super.dispose();
  }
}
