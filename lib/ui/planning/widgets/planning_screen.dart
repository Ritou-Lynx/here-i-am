import 'package:flutter/material.dart';
import 'package:memex/data/personal_data_hub/planning_models.dart';
import 'package:memex/data/personal_data_hub/planning_reminders.dart';
import 'package:memex/data/personal_data_hub/planning_service.dart';
import 'package:memex/ui/core/themes/spring_rain_ui_tokens.dart';
import '../view_models/planning_view_model.dart';

/// Inject the owner-configured service at the shell boundary. This screen does
/// not locate singletons, enable domains, initialize a second queue or edit plans.
class PlanningScreen extends StatefulWidget {
  const PlanningScreen(
      {super.key, required this.service, this.reminders, this.clock});
  final PlanningReader service;
  final PlanningReminderSink? reminders;
  final DateTime Function()? clock;
  @override
  State<PlanningScreen> createState() => _PlanningScreenState();
}

class _PlanningScreenState extends State<PlanningScreen> {
  late PlanningViewModel vm;
  void _create() {
    vm = PlanningViewModel(
        service: widget.service,
        reminders: widget.reminders,
        clock: widget.clock);
    vm.load.execute();
  }

  @override
  void initState() {
    super.initState();
    _create();
  }

  @override
  void didUpdateWidget(covariant PlanningScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.service != widget.service ||
        oldWidget.reminders != widget.reminders) {
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
          child: DefaultTabController(
        length: 2,
        child: Scaffold(
            backgroundColor: Colors.transparent,
            body: Stack(children: [
              Positioned.fill(
                  child: Image.asset('assets/images/雨玻璃.jpg',
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const SizedBox.shrink())),
              SafeArea(
                  child: Column(children: [
                const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: TabBar(tabs: [Tab(text: '今天'), Tab(text: '本周')])),
                Expanded(
                    child: ListenableBuilder(
                        listenable: Listenable.merge([
                          vm,
                          vm.load,
                          vm.synchronize,
                          vm.complete,
                          vm.abandon
                        ]),
                        builder: (context, _) => TabBarView(children: [
                              _PlanningPage(vm: vm, weekly: false),
                              _PlanningPage(vm: vm, weekly: true),
                            ]))),
              ])),
            ])),
      ));
}

String _time(DateTime value) {
  final local = value.toLocal();
  return '${planningDateKey(local)} ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
}

String _quantity(Object? value) => value == null ? '未提供' : '$value';
String _capacity(Map<String, dynamic> data) =>
    '深块 ${_quantity(data['deep'])} · 长块 ${_quantity(data['long'])} · 语音块 ${_quantity(data['voice'])}';

class _PlanningPage extends StatelessWidget {
  const _PlanningPage({required this.vm, required this.weekly});
  final PlanningViewModel vm;
  final bool weekly;
  @override
  Widget build(BuildContext context) {
    final snapshot = vm.snapshot, day = snapshot.day, week = snapshot.week;
    final domainLabels = {
      'plan_days': '今日单',
      'plan_weeks': '本周账',
      'plan_items': '事项'
    };
    return RefreshIndicator(
        onRefresh: vm.synchronize.execute,
        child: ListView(
          key: PageStorageKey(weekly ? 'planning-week' : 'planning-today'),
          padding: const EdgeInsets.all(16),
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            if (vm.load.running) const LinearProgressIndicator(),
            if (vm.load.error)
              const _Panel(title: '读取失败', children: [Text('下拉重试。')]),
            if (vm.synchronize.error)
              const _Panel(
                  title: '暂时无法同步', children: [Text('保留最后一版，状态请求仍在待发队列。')]),
            if (vm.complete.error || vm.abandon.error)
              const _Panel(
                  title: '本次状态未保存',
                  children: [Text('事项或连接已变更，请刷新后查看；已有待处理请求需在电脑端解决。')]),
            if (vm.streamWarning != null)
              _Panel(children: [Text(vm.streamWarning!)]),
            if (vm.reminderWarning != null)
              _Panel(children: [Text(vm.reminderWarning!)]),
            for (final entry in snapshot.domainErrors.entries)
              _Panel(children: [
                Text('${domainLabels[entry.key]}：${entry.value}')
              ]),
            if (snapshot.connection != PlanningConnection.online)
              _Panel(children: [
                Text(snapshot.connection == PlanningConnection.offline
                    ? '电脑离线；${day == null ? '尚无今日单副本' : '今日单生成于 ${_time(day.generatedAt)}'}；新记的事等电脑上线后安排'
                    : '连接尚未确认，当前显示本机副本')
              ]),
            if (!snapshot.statusWritable)
              const _Panel(children: [Text('当前只读，尚未开放状态修改。')]),
            _Panel(children: [
              Wrap(spacing: 8, runSpacing: 4, children: [
                ChoiceChip(
                    label: const Text('全部主线'),
                    selected: vm.selectedArea == null,
                    onSelected: (_) => vm.filterArea(null)),
                for (final area in vm.areas)
                  ChoiceChip(
                      label: Text(area),
                      selected: vm.selectedArea == area,
                      onSelected: (_) => vm.filterArea(area)),
              ])
            ]),
            if (weekly) ...[
              if (week == null)
                const _Panel(title: '尚无本周账', children: [Text('等电脑上线后安排。')])
              else
                ..._week(week),
            ] else ...[
              if (day == null)
                const _Panel(title: '尚无今日单', children: [Text('新记的事等电脑上线后安排。')])
              else ...[
                _Panel(
                    title:
                        '${day.date == planningDateKey(vm.clock()) ? '今日单' : '最近一版 ${day.date}'} · 第 ${day.version} 版',
                    children: [
                      Text('生成于 ${_time(day.generatedAt)}'),
                      Text('容量：${_capacity(day.capacity)}')
                    ]),
                if (day.decisions.isNotEmpty)
                  _Panel(title: '待拍板', children: [
                    for (final decision in day.decisions)
                      Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(
                              '${vm.snapshot.items[decision['item_id']]?.title ?? '需要决定'}\n${decision['reason']}\n建议：${decision['suggestion']}')),
                  ]),
                _Panel(title: '这次改了什么', children: [
                  Text(day.changes.isEmpty ? '没有补充说明' : day.changes)
                ]),
                for (final entry in planningQueues.entries)
                  if (vm.queue(entry.key).isNotEmpty)
                    _Panel(title: entry.value, children: [
                      for (final id in vm.queue(entry.key))
                        if (snapshot.items[id] case final item?)
                          _Item(vm: vm, item: item)
                        else
                          Text('事项暂不可用，等待同步（$id）'),
                    ]),
                if (day.noted.isNotEmpty)
                  _Panel(title: '记下了', children: [
                    for (final note in day.noted) Text(note['text'] as String)
                  ]),
              ],
              if (vm.unqueued.isNotEmpty)
                _Panel(title: '队列之外', children: [
                  const Text('保留原有主线；安排由电脑端更新。'),
                  for (final item in vm.unqueued) _Item(vm: vm, item: item),
                ]),
              _Panel(title: '今晚关灯', children: [
                Text(day?.lightsOut == null ? '尚未提供时间' : _time(day!.lightsOut!))
              ]),
            ],
          ],
        ));
  }

  List<Widget> _week(PlanningWeek week) => [
        _Panel(title: week.key, children: [
          Text('预计容量：${_capacity(week.expected)}'),
          Text('实际容量：${_capacity(week.actual)}'),
        ]),
        for (final quota in week.quotas.where(
            (row) => vm.selectedArea == null || row['area'] == vm.selectedArea))
          _Panel(title: '${quota['area']} · ${quota['block_kind']}', children: [
            Text(
                '下限 ${_quantity(quota['minimum'])} · 目标 ${_quantity(quota['target'])} · 上限 ${_quantity(quota['maximum'])}'),
            Text(
                '已完成 ${_quantity(quota['completed'])} · 本周还排了 ${_quantity(quota['remaining_scheduled'])}'),
            if (quota['completed'] is num &&
                quota['target'] is num &&
                (quota['target'] as num) > 0)
              LinearProgressIndicator(
                  value:
                      ((quota['completed'] as num) / (quota['target'] as num))
                          .clamp(0.0, 1.0)),
            Text(quota['status'] as String? ?? '进度状态未提供'),
          ]),
        _Panel(title: '欠账', children: [
          if (week.debt.isEmpty) const Text('没有欠账'),
          for (final debt in week.debt.where((row) =>
              vm.selectedArea == null || row['area'] == vm.selectedArea))
            Text(
                '${debt['area']} · ${debt['block_kind']} ${_quantity(debt['amount'])} 块 · 来自 ${debt['from_week']} · 已滚 ${debt['rolled_weeks']} 周'),
        ]),
        if (week.days.isNotEmpty)
          _Panel(title: '逐日容量', children: [
            for (final day in week.days)
              Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                      '${day['date']}\n预计：${_capacity(Map<String, dynamic>.from(day['expected']))}\n实际：${_capacity(Map<String, dynamic>.from(day['actual']))}'))
          ]),
      ];
}

class _Panel extends StatelessWidget {
  const _Panel({this.title, required this.children});
  final String? title;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: context.springRainUi.surface.withValues(alpha: .94),
          borderRadius: BorderRadius.circular(context.springRainUi.radius18)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (title != null)
          Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child:
                  Text(title!, style: Theme.of(context).textTheme.titleMedium)),
        ...children,
      ]));
}

class _Item extends StatelessWidget {
  const _Item({required this.vm, required this.item});
  final PlanningViewModel vm;
  final PlanningItem item;
  @override
  Widget build(BuildContext context) {
    final operation = vm.snapshot.operations[item.id];
    final enabled =
        vm.canAct(item) && !vm.complete.running && !vm.abandon.running;
    return Padding(
        key: ValueKey('plan-item-${item.id}'),
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(item.title, style: Theme.of(context).textTheme.titleSmall),
          Text(
              '${item.area} · ${item.status}${item.blockKind == null ? '' : ' · ${item.blockKind} ${_quantity(item.blocks)} 块'}'),
          if (item.scheduledAt != null) Text('定时：${_time(item.scheduledAt!)}'),
          if (item.dueDate != null) Text('截止：${item.dueDate}'),
          if (item.note.isNotEmpty) Text(item.note),
          if (item.pending || operation != null)
            Text(operation?.label ?? '待同步',
                key: ValueKey('plan-status-${item.id}')),
          if (operation?.reason != null && operation!.blocksAction)
            Text(switch (operation.reason) {
              'user_conflict' => '电脑与手机上的选择不同，需要确认一次。',
              'actor_not_authorized' || 'scope_forbidden' => '此连接暂不能修改状态。',
              'stale_base' || 'binding_changed' => '数据或连接已更新，请在电脑端核对。',
              _ => '请在电脑端查看并处理这次请求。',
            }),
          Wrap(spacing: 12, children: [
            TextButton(
                key: ValueKey('plan-complete-${item.id}'),
                onPressed: enabled ? () => vm.complete.execute(item.id) : null,
                child: const Text('完成')),
            TextButton(
                key: ValueKey('plan-abandon-${item.id}'),
                onPressed: enabled ? () => vm.abandon.execute(item.id) : null,
                child: const Text('不做了')),
          ]),
        ]));
  }
}
