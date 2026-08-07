/// Memory V3 Lab - Dreaming fragments browser page.
///
/// Lists recent fragments; tap edits content + emotional weight, long-press
/// changes status (ignored / deleted). Includes a "clear all" action.
library;

import 'dart:async';

import 'package:drift/drift.dart' as drift;
import 'package:flutter/material.dart';
import 'package:memex/data/memory_v3/services/dreaming_orchestrator_service.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/ui/core/themes/spring_rain_ui_tokens.dart';
import 'package:memex/ui/memory/widgets/lab/lab_shared.dart';
import 'package:memex/utils/logger.dart';

final _logger = getLogger('LabFragmentsPage');

class LabFragmentsPage extends StatefulWidget {
  const LabFragmentsPage({super.key});

  @override
  State<LabFragmentsPage> createState() => _LabFragmentsPageState();
}

class _LabFragmentsPageState extends State<LabFragmentsPage> {
  List<MemoryFragment> _items = const [];
  bool _loading = true;
  bool _busy = false;
  String? _lastError;
  String? _lastSuccess;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    if (!DreamingOrchestratorServiceV3.isInitialized) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _items = const [];
      });
      return;
    }
    final db = AppDatabase.instance;
    final rows = await (db.select(db.memoryFragments)
          ..orderBy([(t) => drift.OrderingTerm.desc(t.createdAt)])
          ..limit(30))
        .get();
    if (!mounted) return;
    setState(() {
      _items = rows;
      _loading = false;
    });
  }

  Future<void> _editFragment(MemoryFragment fragment) async {
    final controller = TextEditingController(text: fragment.content);
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (ctx) {
        final t = ctx.springRainUi;
        final keyboardInset = MediaQuery.of(ctx).viewInsets.bottom;
        return Padding(
          padding: EdgeInsets.fromLTRB(
            t.space16,
            t.space8,
            t.space16,
            t.space16 + keyboardInset,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('编辑 Fragment',
                    style: Theme.of(ctx).textTheme.titleMedium),
                SizedBox(height: t.space8),
                Text('原始抽取: ${fragment.content}',
                    style: TextStyle(fontSize: 11, color: t.textTertiary)),
                SizedBox(height: t.space4),
                Text(
                  fragment.userCorrected ? '状态: 已修正过' : '状态: 未修正',
                  style: TextStyle(fontSize: 11, color: t.textTertiary),
                ),
                SizedBox(height: t.space12),
                TextField(
                  controller: controller,
                  maxLength: 80,
                  maxLines: 2,
                  minLines: 1,
                  autofocus: true,
                  textInputAction: TextInputAction.newline,
                  decoration: const InputDecoration(
                    labelText: '新内容',
                    helperText: '≤ 80 字；过短信息会丢失',
                  ),
                ),
                SizedBox(height: t.space8),
                EmotionalWeightSlider(initial: fragment.emotionalWeight),
                SizedBox(height: t.space16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('取消'),
                    ),
                    SizedBox(width: t.space8),
                    FilledButton(
                      onPressed: () =>
                          Navigator.pop(ctx, controller.text.trim()),
                      child: const Text('保存'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
    if (result == null || result.isEmpty || result == fragment.content) return;

    setState(() {
      _busy = true;
      _lastError = null;
      _lastSuccess = null;
    });
    try {
      final newWeight =
          EmotionalWeightSlider.lastPicked ?? fragment.emotionalWeight;
      await DreamingOrchestratorServiceV3.instance.updateFragment(
        fragment.id,
        content: result,
        emotionalWeight:
            newWeight != fragment.emotionalWeight ? newWeight : null,
        sourceKind: 'lab_edit',
      );
      await _load();
      if (!mounted) return;
      setState(() => _lastSuccess = 'Fragment 已修正');
    } catch (e, st) {
      _logger.warning('updateFragment failed', e, st);
      if (!mounted) return;
      setState(() => _lastError = '修正失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _fragmentActions(MemoryFragment fragment) async {
    final t = context.springRainUi;
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('编辑内容'),
              subtitle: const Text('修改文字或情感权重'),
              onTap: () => Navigator.pop(ctx, 'edit'),
            ),
            ListTile(
              leading: const Icon(Icons.flag_outlined),
              title: const Text('标记 ignored'),
              subtitle: const Text('Dreaming 不再合并这条'),
              enabled: fragment.status != 'ignored',
              onTap: () => Navigator.pop(ctx, 'ignored'),
            ),
            ListTile(
              leading: Icon(
                fragment.status == 'deleted'
                    ? Icons.restore_from_trash_outlined
                    : Icons.delete_outline,
                color: t.error,
              ),
              title: Text(
                fragment.status == 'deleted' ? '恢复为 active' : '标记 deleted',
              ),
              subtitle: Text(
                fragment.status == 'deleted'
                    ? '从 FTS 移除 -> 恢复 -> 重新索引'
                    : '从 FTS 移除（保留行以备恢复）',
              ),
              onTap: () => Navigator.pop(ctx, 'toggle_deleted'),
            ),
          ],
        ),
      ),
    );
    if (action == null) return;

    setState(() {
      _busy = true;
      _lastError = null;
      _lastSuccess = null;
    });
    try {
      switch (action) {
        case 'edit':
          await _editFragment(fragment);
          return;
        case 'ignored':
          await DreamingOrchestratorServiceV3.instance.updateFragment(
            fragment.id,
            status: 'ignored',
            sourceKind: 'lab_edit',
          );
          break;
        case 'toggle_deleted':
          await DreamingOrchestratorServiceV3.instance.updateFragment(
            fragment.id,
            status: fragment.status == 'deleted' ? 'active' : 'deleted',
            sourceKind: 'lab_edit',
          );
          break;
      }
      await _load();
      if (!mounted) return;
      setState(() => _lastSuccess = '状态已更新');
    } catch (e, st) {
      _logger.warning('fragment action failed', e, st);
      if (!mounted) return;
      setState(() => _lastError = '操作失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _clearAll() async {
    final confirmed = await showLabConfirmDialog(
      context,
      title: '清空所有 Dreaming fragments？',
      content: '这会删除所有 fragment、关联的 entity links 和水印标记。不能撤销。',
      confirmLabel: '清空',
      danger: true,
    );
    if (!confirmed) return;

    setState(() {
      _busy = true;
      _lastError = null;
      _lastSuccess = null;
    });
    try {
      final count =
          await DreamingOrchestratorServiceV3.instance.clearAllFragments();
      await _load();
      if (!mounted) return;
      setState(() => _lastSuccess = '已清空 $count 条 fragment');
    } catch (e, st) {
      _logger.warning('clearAllFragments failed', e, st);
      if (!mounted) return;
      setState(() => _lastError = '清空失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.springRainUi;
    return Scaffold(
      appBar: AppBar(
        title: const Text('梦境碎片'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _load,
            tooltip: '刷新',
          ),
          IconButton(
            icon: Icon(Icons.delete_sweep_outlined, color: t.error),
            onPressed: _busy || _items.isEmpty ? null : _clearAll,
            tooltip: '清空全部',
          ),
        ],
      ),
      body: Column(
        children: [
          LabBusyLine(visible: _busy || _loading),
          if (_lastError != null)
            Padding(
              padding: EdgeInsets.all(t.space12),
              child: LabStatusBanner(
                  message: _lastError!, kind: LabStatusKind.error),
            ),
          if (_lastSuccess != null)
            Padding(
              padding: EdgeInsets.all(t.space12),
              child: LabStatusBanner(
                  message: _lastSuccess!, kind: LabStatusKind.success),
            ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: _items.isEmpty && !_loading
                  ? ListView(
                      children: const [LabEmptyState(message: '（暂无 fragments）')],
                    )
                  : ListView.separated(
                      itemCount: _items.length,
                      separatorBuilder: (_, __) =>
                          Divider(height: 1, indent: t.space16, color: t.divider),
                      itemBuilder: (ctx, i) => _FragmentTile(
                        fragment: _items[i],
                        onTap: () => _editFragment(_items[i]),
                        onLongPress: () => _fragmentActions(_items[i]),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FragmentTile extends StatelessWidget {
  const _FragmentTile({
    required this.fragment,
    required this.onTap,
    required this.onLongPress,
  });

  final MemoryFragment fragment;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final t = context.springRainUi;
    final createdAt =
        DateTime.fromMillisecondsSinceEpoch(fragment.createdAt).toString();
    final corrected = fragment.userCorrected ? ' · 已修正' : '';
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: t.space16,
          vertical: t.space12,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              fragment.isUserTruthCandidate
                  ? Icons.new_releases_outlined
                  : Icons.auto_awesome_outlined,
              size: 18,
              color: fragment.isUserTruthCandidate
                  ? t.warning
                  : t.iconMuted,
            ),
            SizedBox(width: t.space12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    fragment.content,
                    style: TextStyle(
                      color: t.textPrimary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  SizedBox(height: t.space4),
                  Text(
                    '${fragment.status} · weight ${fragment.emotionalWeight.toStringAsFixed(2)} · $createdAt$corrected',
                    style: TextStyle(fontSize: 10, color: t.textTertiary),
                  ),
                ],
              ),
            ),
            Icon(Icons.edit_outlined, size: 16, color: t.iconMuted),
          ],
        ),
      ),
    );
  }
}
