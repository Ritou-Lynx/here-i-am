/// Memory V3 Lab - query log page (promoted from bottom sheet).
///
/// Shows memory_card query log entries with strategy labels and zero-result
/// badge. Clear and refresh from the AppBar.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:memex/data/memory_v3/services/query_log_service.dart';
import 'package:memex/ui/core/themes/spring_rain_ui_tokens.dart';
import 'package:memex/ui/memory/widgets/lab/lab_shared.dart';

class LabQueryLogPage extends StatefulWidget {
  const LabQueryLogPage({super.key});

  @override
  State<LabQueryLogPage> createState() => _LabQueryLogPageState();
}

class _LabQueryLogPageState extends State<LabQueryLogPage> {
  List<QueryLogEntry> _entries = const [];
  int _zeroCount = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final entries = await QueryLogService.readAll();
    final zeros = await QueryLogService.zeroResultCount();
    if (!mounted) return;
    setState(() {
      _entries = entries;
      _zeroCount = zeros;
      _loading = false;
    });
  }

  Future<void> _clear() async {
    final confirmed = await showLabConfirmDialog(
      context,
      title: '清空查询日志？',
      content: '这会删除所有查询记录，包括零结果标记。',
      confirmLabel: '清空',
      danger: true,
    );
    if (!confirmed) return;
    await QueryLogService.clear();
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.springRainUi;
    return Scaffold(
      appBar: AppBar(
        title: const Text('查询日志'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _load,
            tooltip: '刷新',
          ),
          IconButton(
            icon: Icon(Icons.delete_outline, color: t.error),
            onPressed: _entries.isEmpty ? null : _clear,
            tooltip: '清空日志',
          ),
        ],
      ),
      body: Column(
        children: [
          LabBusyLine(visible: _loading),
          if (_zeroCount > 0)
            Padding(
              padding: EdgeInsets.fromLTRB(
                t.space16,
                t.space12,
                t.space16,
                t.space8,
              ),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Chip(
                  label: Text('$_zeroCount 条零结果'),
                  backgroundColor: t.warningSoft,
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: _entries.isEmpty && !_loading
                  ? ListView(
                      children: const [
                        LabEmptyState(message: '暂无查询记录'),
                      ],
                    )
                  : ListView.separated(
                      itemCount: _entries.length,
                      separatorBuilder: (_, __) =>
                          Divider(height: 1, indent: t.space16, color: t.divider),
                      itemBuilder: (ctx, i) =>
                          _QueryLogTile(entry: _entries[i]),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _QueryLogTile extends StatelessWidget {
  const _QueryLogTile({required this.entry});

  final QueryLogEntry entry;

  String get _strategyLabel {
    switch (entry.topStrategy) {
      case 'original':
        return '原文匹配';
      case 'expanded':
        return '同义词扩展';
      case 'relaxed':
        return '宽松兜底';
      default:
        return '无';
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.springRainUi;
    final isZero = entry.isZeroResult;
    final time = entry.dateTime;
    final timeStr =
        '${time.month}/${time.day} ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    return ListTile(
      leading: CircleAvatar(
        radius: 14,
        backgroundColor: isZero ? t.errorSoft : t.successSoft,
        child: Text(
          '${entry.resultCount}',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: isZero ? t.error : t.success,
          ),
        ),
      ),
      title: Text(
        entry.query,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: t.textPrimary, fontSize: 14),
      ),
      subtitle: Text(
        '$timeStr · $_strategyLabel · ${entry.actualSummary}',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 11, color: t.textTertiary),
      ),
    );
  }
}
