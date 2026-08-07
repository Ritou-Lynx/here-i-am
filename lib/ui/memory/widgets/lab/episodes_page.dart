/// Memory V3 Lab - Dreaming episodes browser page.
///
/// Lists recent episodes; tap edits narrative/topic/confidence/scoring,
/// long-press changes status (hidden / deleted). Includes a "clear all".
library;

import 'dart:async';

import 'package:drift/drift.dart' as drift;
import 'package:flutter/material.dart';
import 'package:memex/data/memory_v3/services/dreaming_orchestrator_service.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/ui/core/themes/spring_rain_ui_tokens.dart';
import 'package:memex/ui/memory/widgets/lab/lab_shared.dart';
import 'package:memex/utils/logger.dart';

final _logger = getLogger('LabEpisodesPage');

class LabEpisodesPage extends StatefulWidget {
  const LabEpisodesPage({super.key});

  @override
  State<LabEpisodesPage> createState() => _LabEpisodesPageState();
}

class _LabEpisodesPageState extends State<LabEpisodesPage> {
  List<MemoryEpisode> _items = const [];
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
    final rows = await (db.select(db.memoryEpisodes)
          ..orderBy([(t) => drift.OrderingTerm.desc(t.createdAt)])
          ..limit(20))
        .get();
    if (!mounted) return;
    setState(() {
      _items = rows;
      _loading = false;
    });
  }

  Future<void> _editEpisode(MemoryEpisode episode) async {
    final t = context.springRainUi;
    final narrativeController =
        TextEditingController(text: episode.narrative);
    final topicController = TextEditingController(text: episode.topicId);
    final confidence = ValueNotifier<String>(episode.confidence);
    var significance = episode.significance;
    final valence = ValueNotifier<double>(episode.valence);
    final arousal = ValueNotifier<double>(episode.arousal);

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
                Text('编辑 Episode',
                    style: Theme.of(ctx).textTheme.titleMedium),
                SizedBox(height: t.space8),
                Text('原始: ${episode.narrative}',
                    style: TextStyle(fontSize: 11, color: t.textTertiary)),
                SizedBox(height: t.space4),
                Text(
                  episode.userCorrected ? '状态: 已修正过' : '状态: 未修正',
                  style: TextStyle(fontSize: 11, color: t.textTertiary),
                ),
                SizedBox(height: t.space12),
                TextField(
                  controller: narrativeController,
                  maxLines: 4,
                  minLines: 2,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Narrative (第一人称)',
                  ),
                ),
                SizedBox(height: t.space12),
                TextField(
                  controller: topicController,
                  decoration: const InputDecoration(
                    labelText: 'Topic',
                    hintText: 'e.g. relationship_care',
                  ),
                ),
                SizedBox(height: t.space12),
                ValueListenableBuilder<String>(
                  valueListenable: confidence,
                  builder: (_, value, __) => DropdownButtonFormField<String>(
                    initialValue: value,
                    decoration: const InputDecoration(labelText: 'Confidence'),
                    items: const [
                      DropdownMenuItem(value: 'high', child: Text('high')),
                      DropdownMenuItem(
                          value: 'medium', child: Text('medium')),
                      DropdownMenuItem(value: 'low', child: Text('low')),
                    ],
                    onChanged: (v) {
                      if (v != null) confidence.value = v;
                    },
                  ),
                ),
                SizedBox(height: t.space12),
                IntSliderField(
                  label: 'Significance',
                  min: 1,
                  max: 10,
                  value: significance,
                  onChanged: (v) => significance = v,
                ),
                SizedBox(height: t.space12),
                ValueListenableBuilder<double>(
                  valueListenable: valence,
                  builder: (_, v, __) => DoubleSliderField(
                    label: 'Valence (-1..1)',
                    value: v,
                    min: -1.0,
                    max: 1.0,
                    onChanged: (nv) => valence.value = nv,
                  ),
                ),
                SizedBox(height: t.space8),
                ValueListenableBuilder<double>(
                  valueListenable: arousal,
                  builder: (_, v, __) => DoubleSliderField(
                    label: 'Arousal (0..1)',
                    value: v,
                    min: 0.0,
                    max: 1.0,
                    onChanged: (nv) => arousal.value = nv,
                  ),
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
      final newNarrative = narrativeController.text.trim();
      await DreamingOrchestratorServiceV3.instance.updateEpisode(
        episode.id,
        narrative:
            newNarrative != episode.narrative ? newNarrative : null,
        topicId: topicController.text.trim() != episode.topicId
            ? topicController.text.trim()
            : null,
        confidence: confidence.value != episode.confidence
            ? confidence.value
            : null,
        significance:
            significance != episode.significance ? significance : null,
        valence: valence.value != episode.valence ? valence.value : null,
        arousal: arousal.value != episode.arousal ? arousal.value : null,
        sourceKind: 'lab_edit',
      );
      await _load();
      if (!mounted) return;
      setState(() => _lastSuccess = 'Episode 已修正');
    } catch (e, st) {
      _logger.warning('updateEpisode failed', e, st);
      if (!mounted) return;
      setState(() => _lastError = '修正失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _episodeActions(MemoryEpisode episode) async {
    final t = context.springRainUi;
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('编辑 Narrative / Topic / Confidence / 评分'),
              onTap: () => Navigator.pop(ctx, 'edit'),
            ),
            ListTile(
              leading: const Icon(Icons.visibility_off_outlined),
              title: const Text('标记 hidden'),
              subtitle: const Text('Dreaming context 不再注入'),
              enabled: episode.status != 'hidden',
              onTap: () => Navigator.pop(ctx, 'hidden'),
            ),
            ListTile(
              leading: Icon(
                episode.status == 'deleted'
                    ? Icons.restore_from_trash_outlined
                    : Icons.delete_outline,
                color: t.error,
              ),
              title: Text(
                episode.status == 'deleted' ? '恢复为 active' : '标记 deleted',
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
          await _editEpisode(episode);
          return;
        case 'hidden':
          await DreamingOrchestratorServiceV3.instance.updateEpisode(
            episode.id,
            status: 'hidden',
            sourceKind: 'lab_edit',
          );
          break;
        case 'toggle_deleted':
          await DreamingOrchestratorServiceV3.instance.updateEpisode(
            episode.id,
            status: episode.status == 'deleted' ? 'active' : 'deleted',
            sourceKind: 'lab_edit',
          );
          break;
      }
      await _load();
      if (!mounted) return;
      setState(() => _lastSuccess = '状态已更新');
    } catch (e, st) {
      _logger.warning('episode action failed', e, st);
      if (!mounted) return;
      setState(() => _lastError = '操作失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _clearAll() async {
    final confirmed = await showLabConfirmDialog(
      context,
      title: '清空所有 Dreaming episodes？',
      content: '这会删除所有生成的 episodes 及其 entity links。被这些 episode '
          '用过的 source fragments 会被重置回 active。',
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
          await DreamingOrchestratorServiceV3.instance.clearAllEpisodes();
      await _load();
      if (!mounted) return;
      setState(() => _lastSuccess = '已清空 $count 条 episode');
    } catch (e, st) {
      _logger.warning('clearAllEpisodes failed', e, st);
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
        title: const Text('情节片段'),
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
                      children: const [LabEmptyState(message: '（暂无 episodes）')],
                    )
                  : ListView.separated(
                      itemCount: _items.length,
                      separatorBuilder: (_, __) =>
                          Divider(height: 1, indent: t.space16, color: t.divider),
                      itemBuilder: (ctx, i) => _EpisodeTile(
                        episode: _items[i],
                        onTap: () => _editEpisode(_items[i]),
                        onLongPress: () => _episodeActions(_items[i]),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EpisodeTile extends StatelessWidget {
  const _EpisodeTile({
    required this.episode,
    required this.onTap,
    required this.onLongPress,
  });

  final MemoryEpisode episode;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final t = context.springRainUi;
    final createdAt =
        DateTime.fromMillisecondsSinceEpoch(episode.createdAt).toString();
    final corrected = episode.userCorrected ? ' · 已修正' : '';
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
            Icon(Icons.auto_awesome, size: 18, color: t.info),
            SizedBox(width: t.space12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    episode.narrative,
                    style: TextStyle(
                      color: t.textPrimary,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                  ),
                  SizedBox(height: t.space4),
                  Text(
                    'sig ${episode.significance} · ${episode.confidence} · '
                    '${episode.topicId} · '
                    'v ${episode.valence.toStringAsFixed(2)} '
                    'a ${episode.arousal.toStringAsFixed(2)} · '
                    '${episode.status} · $createdAt$corrected',
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
