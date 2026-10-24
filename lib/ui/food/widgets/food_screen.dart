import 'dart:async';

import 'package:flutter/material.dart';
import 'package:memex/data/personal_data_hub/food_models.dart';
import 'package:memex/data/personal_data_hub/food_service.dart';
import 'package:memex/ui/character/widgets/chat_message_source_label.dart';
import 'package:memex/ui/core/themes/spring_rain_ui_tokens.dart';
import 'package:memex/utils/command.dart';
import 'package:memex/utils/result.dart';

class FoodScreen extends StatefulWidget {
  const FoodScreen({super.key, required this.service, this.clock});

  final FoodReader service;
  final DateTime Function()? clock;

  @override
  State<FoodScreen> createState() => _FoodScreenState();
}

class _FoodScreenState extends State<FoodScreen> {
  late _FoodViewModel vm;

  void _create() {
    vm = _FoodViewModel(service: widget.service, clock: widget.clock);
    vm.load.execute();
  }

  @override
  void initState() {
    super.initState();
    _create();
  }

  @override
  void didUpdateWidget(covariant FoodScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.service != widget.service) {
      vm.dispose();
      _create();
    }
  }

  @override
  void dispose() {
    vm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SpringRainUiScope(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(title: const Text('饮食')),
          body: Stack(
            children: [
              Positioned.fill(
                child: Image.asset(
                  'assets/images/雨玻璃.jpg',
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),
              ListenableBuilder(
                listenable: Listenable.merge([vm, vm.load]),
                builder: (context, _) => _FoodDayView(vm: vm),
              ),
            ],
          ),
        ),
      );
}

class _FoodViewModel extends ChangeNotifier {
  _FoodViewModel({required FoodReader service, DateTime Function()? clock})
      : _service = service,
        clock = clock ?? DateTime.now {
    selectedDate = _businessDate(this.clock());
    snapshot = FoodDaySnapshot(date: foodDateKey(selectedDate));
    load = Command0<void>(() => runResultVoid(_read));
    _subscription = _service.changes.listen(
      (_) => _queueRead(),
      onError: (_) {
        if (_disposed) return;
        streamWarning = '变更连接中断，保留上次副本';
        notifyListeners();
      },
    );
  }

  final FoodReader _service;
  final DateTime Function() clock;
  late DateTime selectedDate;
  late FoodDaySnapshot snapshot;
  late final Command0<void> load;
  late final StreamSubscription<void> _subscription;
  String? streamWarning;
  bool _disposed = false, _readAgain = false;

  bool get isToday =>
      foodDateKey(selectedDate) == foodDateKey(_businessDate(clock()));

  void changeDay(int days) {
    selectedDate = DateTime(
      selectedDate.year,
      selectedDate.month,
      selectedDate.day + days,
    );
    snapshot = FoodDaySnapshot(date: foodDateKey(selectedDate));
    streamWarning = null;
    notifyListeners();
    _requestRead();
  }

  void _queueRead() {
    if (_disposed) return;
    _requestRead();
  }

  void _requestRead() {
    _readAgain = true;
    unawaited(load.execute());
  }

  Future<void> _read() async {
    do {
      _readAgain = false;
      final date = selectedDate;
      final next = await _service.read(date);
      if (_disposed) return;
      if (foodDateKey(date) == foodDateKey(selectedDate)) {
        snapshot = next;
        streamWarning = null;
        notifyListeners();
      }
    } while (_readAgain && !_disposed);
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_subscription.cancel());
    load.dispose();
    super.dispose();
  }
}

class _FoodDayView extends StatelessWidget {
  const _FoodDayView({required this.vm});

  final _FoodViewModel vm;

  @override
  Widget build(BuildContext context) {
    final snapshot = vm.snapshot;
    return ListView(
      key: const PageStorageKey('food-day'),
      padding: const EdgeInsets.all(16),
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        _Panel(
          child: Row(
            children: [
              IconButton(
                key: const ValueKey('food-previous-day'),
                tooltip: '前一天',
                onPressed: () => vm.changeDay(-1),
                icon: const Icon(Icons.chevron_left),
              ),
              Expanded(
                child: Text(
                  vm.isToday ? '今天 · ${snapshot.date}' : snapshot.date,
                  key: const ValueKey('food-selected-date'),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              IconButton(
                key: const ValueKey('food-next-day'),
                tooltip: '后一天',
                onPressed: () => vm.changeDay(1),
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
        ),
        if (vm.load.running) const LinearProgressIndicator(),
        if (vm.load.error)
          const _Panel(child: Text('读取失败，请稍后重试。')),
        if (vm.streamWarning != null) _Panel(child: Text(vm.streamWarning!)),
        if (snapshot.error != null) _Panel(child: Text(snapshot.error!)),
        if (snapshot.entries.isEmpty &&
            !vm.load.running &&
            (snapshot.error == null || snapshot.invalidRecords > 0))
          const _Panel(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(child: Text('这一天还没有饮食记录。')),
            ),
          )
        else if (snapshot.entries.isNotEmpty) ...[
          _TotalsPanel(totals: snapshot.totals),
          for (final entry in snapshot.entries) _EntryPanel(entry: entry),
        ],
      ],
    );
  }
}

class _TotalsPanel extends StatelessWidget {
  const _TotalsPanel({required this.totals});

  final FoodTotals totals;

  @override
  Widget build(BuildContext context) => _Panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '约 ${_number(totals.kcal)} 千卡（${_number(totals.kcalLow)}–${_number(totals.kcalHigh)}）',
              key: const ValueKey('food-day-kcal'),
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 16),
            _MacroBar(
              label: '蛋白',
              grams: totals.proteinG,
              caloriesPerGram: 4,
              totalKcal: totals.kcal,
            ),
            _MacroBar(
              label: '脂肪',
              grams: totals.fatG,
              caloriesPerGram: 9,
              totalKcal: totals.kcal,
            ),
            _MacroBar(
              label: '碳水',
              grams: totals.carbG,
              caloriesPerGram: 4,
              totalKcal: totals.kcal,
            ),
          ],
        ),
      );
}

class _MacroBar extends StatelessWidget {
  const _MacroBar({
    required this.label,
    required this.grams,
    required this.caloriesPerGram,
    required this.totalKcal,
  });

  final String label;
  final double grams, caloriesPerGram, totalKcal;

  @override
  Widget build(BuildContext context) {
    final ratio = totalKcal == 0 ? 0.0 : grams * caloriesPerGram / totalKcal;
    final percent = (ratio * 100).round();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$label ${_number(grams)} 克 · $percent%'),
          const SizedBox(height: 4),
          LinearProgressIndicator(
            key: ValueKey('food-macro-$label'),
            value: ratio.clamp(0.0, 1.0).toDouble(),
          ),
        ],
      ),
    );
  }
}

class _EntryPanel extends StatelessWidget {
  const _EntryPanel({required this.entry});

  final FoodEntry entry;

  @override
  Widget build(BuildContext context) {
    final source = foodSourceLabelFor(entry.originDeviceId);
    return _Panel(
      padding: EdgeInsets.zero,
      child: ExpansionTile(
        key: ValueKey('food-entry-${entry.id}'),
        leading: _ConfidenceDot(confidence: entry.confidence),
        title: Text('${_time(entry.eatenAt)} · ${entry.title}'),
        subtitle: Text(
          '${_meal(entry.meal)} · 约 ${_number(entry.totals.kcal)} 千卡（${_number(entry.totals.kcalLow)}–${_number(entry.totals.kcalHigh)}）'
          '${source == null ? '' : ' · $source'}',
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('置信度：${_confidence(entry.confidence)}'),
          if (entry.note.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(entry.note),
          ],
          const Divider(),
          for (final item in entry.items)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                '${item.name} · ${_number(item.grams)} 克'
                '（${_number(item.gramsLow)}–${_number(item.gramsHigh)}）'
                ' · ${_itemSource(item.foodSource)} · ${_confidence(item.confidence)}',
              ),
            ),
        ],
      ),
    );
  }
}

class _ConfidenceDot extends StatelessWidget {
  const _ConfidenceDot({required this.confidence});

  final String confidence;

  @override
  Widget build(BuildContext context) => Semantics(
        label: '${_confidence(confidence)}置信度',
        child: Container(
          key: ValueKey('food-confidence-$confidence'),
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: switch (confidence) {
              'high' => Colors.green,
              'medium' => Colors.orange,
              _ => Colors.red,
            },
          ),
        ),
      );
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child, this.padding = const EdgeInsets.all(16)});

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: padding,
        decoration: BoxDecoration(
          color: context.springRainUi.surface.withValues(alpha: .94),
          borderRadius: BorderRadius.circular(context.springRainUi.radius18),
        ),
        child: child,
      );
}

String _number(double value) => value == value.roundToDouble()
    ? value.toInt().toString()
    : value.toStringAsFixed(1);

DateTime _businessDate(DateTime value) {
  final local = value.toLocal();
  return DateTime(
    local.year,
    local.month,
    local.day - (local.hour < 4 ? 1 : 0),
  );
}

String _time(DateTime value) {
  final local = value.toLocal();
  return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
}

String _meal(String value) => switch (value) {
      'breakfast' => '早餐',
      'lunch' => '午餐',
      'dinner' => '晚餐',
      'snack' => '加餐',
      _ => '饮品',
    };

String _confidence(String value) => switch (value) {
      'high' => '高',
      'medium' => '中',
      _ => '低',
    };

String _itemSource(String value) => switch (value) {
      'label' => '标签',
      'personal' => '个人库',
      'usda' => 'USDA',
      _ => '模型估',
    };
