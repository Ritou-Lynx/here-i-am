/// Memory V3 Lab - Sagas (long-term arcs) browser page.
///
/// Lists recent sagas; tap edits title/description, long-press changes
/// status (hidden / deleted). Includes a "clear all".
library;

import 'dart:async';

import 'package:drift/drift.dart' as drift;
import 'package:flutter/material.dart';
import 'package:memex/data/memory_v3/services/dreaming_orchestrator_service.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/ui/core/themes/spring_rain_ui_tokens.dart';
import 'package:memex/ui/memory/widgets/lab/lab_shared.dart';
import 'package:memex/utils/logger.dart';

final _logger = getLogger('LabSagasPage');

class LabSagasPage extends StatefulWidget {
  const LabSagasPage({super.key});

  @override
  State<LabSagasPage> createState() => _LabSagasPageState();
}

class _LabSagasPageState extends State<LabSagasPage> {
  List<MemorySaga> _items = const [];
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
    final rows = await (db.select(db.memorySagas)
          ..orderBy([(t) => drift.OrderingTerm.desc(t.updatedAt)])
          ..limit(20))
        .get();
    if (!mounted) return;
    setState(() {
      _items = rows;
      _loading = false;
    });
  }

  Future<void> _editSaga(MemorySaga saga) async {
    final t = context.springRainUi;
    final titleController = TextEditingController(text: saga.title);
    final descController = TextEditingController(text: saga.description);

    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (ctx) {
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
                Text('编辑 Saga',
                    style: Theme.of(ctx).textTheme.titleMedium),
                SizedBox(height: t.space12),
                TextField(
                  controller: titleController,
                  maxLength: 30,
                  maxLines: 1,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'Title'),
                ),
                SizedBox(height: t.space12),
                TextField(
                  controller: descController,
                  maxLines: 6,
                  minLines: 3,
                  decoration: const InputDecoration(labelText: 'Description'),
                ),
                SizedBox(height: t.space16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('取消'),
                    ),
                    SizedBox(width: t.space8),
                    FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
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
    if (result != true) return;

    setState(() {
      _busy = true;
      _lastError = null;
      _lastSuccess = null;
    });
    try {
      await DreamingOrchestratorServiceV3.instance.updateSaga(
        saga.id,
        title: titleController.text.trim() != saga.title
            ? titleController.text.trim()
            : null,
        description: descController.text.trim() != saga.description
            ? descController.text.trim()
            : null,
      );
      await _load();
      if (!mounted) return;
      setState(() => _lastSuccess = 'Saga 已修正');
    } catch (e, st) {
      _logger.warning('updateSaga failed', e, st);
      if (!mounted) return;
      setState(() => _lastError = '修正失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sagaActions(MemorySaga saga) async {
    final t = context.springRainUi;
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('编辑 Title / Description'),
              onTap: () => Navigator.pop(ctx, 'edit'),
            ),
            ListTile(
              leading: const Icon(Icons.visibility_off_outlined),
              title: const Text('标记 hidden'),
              subtitle: const Text('Companion 不再注入这条'),
              enabled: saga.status != 'hidden',
              onTap: () => Navigator.pop(ctx, 'hidden'),
            ),
            ListTile(
              leading: Icon(
                saga.status == 'deleted'
                    ? Icons.restore_from_trash_outlined
                    : Icons.delete_outline,
                color: t.error,
              ),
              title: Text(
                saga.status == 'deleted' ? '恢复为 active' : '标记 deleted',
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
          await _editSaga(saga);
          return;
        case 'hidden':
          await DreamingOrchestratorServiceV3.instance.updateSaga(
            saga.id,
            status: 'hidden',
          );
          break;
        case 'toggle_deleted':
          await DreamingOrchestratorServiceV3.instance.updateSaga(
            saga.id,
            status: saga.status == 'deleted' ? 'active' : 'deleted',
          );
          break;
      }
      await _load();
      if (!mounted) return;
      setState(() => _lastSuccess = '状态已更新');
    } catch (e, st) {
      _logger.warning('saga action failed', e, st);
      if (!mounted) return;
      setState(() => _lastError = '操作失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _clearAll() async {
    final confirmed = await showLabConfirmDialog(
      context,
      title: '清空所有 Saga？',
      content: '这会删除所有 saga 及其历史快照。不能撤销。',
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
      await DreamingOrchestratorServiceV3.instance.clearAllSagas();
      await _load();
      if (!mounted) return;
      setState(() => _lastSuccess = '已清空所有 saga');
    } catch (e, st) {
      _logger.warning('clearAllSagas failed', e, st);
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
        title: const Text('长期弧线'),
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
                      children: const [LabEmptyState(message: '（暂无 saga）')],
                    )
                  : ListView.separated(
                      itemCount: _items.length,
                      separatorBuilder: (_, __) =>
                          Divider(height: 1, indent: t.space16, color: t.divider),
                      itemBuilder: (ctx, i) => _SagaTile(
                        saga: _items[i],
                        onTap: () => _editSaga(_items[i]),
                        onLongPress: () => _sagaActions(_items[i]),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SagaTile extends StatelessWidget {
  const _SagaTile({
    required this.saga,
    required this.onTap,
    required this.onLongPress,
  });

  final MemorySaga saga;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final t = context.springRainUi;
    final updatedAt =
        DateTime.fromMillisecondsSinceEpoch(saga.updatedAt).toString();
    final corrected = saga.userCorrected ? ' · 已修正' : '';
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
            Icon(Icons.auto_stories_outlined, size: 18, color: t.info),
            SizedBox(width: t.space12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    saga.title,
                    style: TextStyle(
                      color: t.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(height: t.space4),
                  Text(
                    saga.description,
                    style: TextStyle(fontSize: 12, color: t.textSecondary),
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                  ),
                  SizedBox(height: t.space4),
                  Text(
                    '${saga.status} · $updatedAt$corrected',
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
