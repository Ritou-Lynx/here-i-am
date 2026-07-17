/// V3 Lab — dev / debug screen for the Memory V3 backend.
///
/// Lets you verify the Memory V3 / Dreaming backend, inspect recent
/// memory_cards written by real app entry points, and export debug data.
///
/// Intentionally minimal styling — this is a backend test rig, not the
/// production Memory Review surface. The production UI redesign lives in
/// MEMORY_V3_ROADMAP.md Phase 1.7 / 1.8.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' as drift;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:memex/data/memory_v3/services/dreaming_orchestrator_service.dart';
import 'package:memex/data/memory_v3/services/dreaming_recall_log_service.dart';
import 'package:memex/data/memory_v3/services/dreaming_scheduler_service.dart';
import 'package:memex/data/memory_v3/models/memory_card_view_data.dart';
import 'package:memex/data/memory_v3/services/memory_card_query_service.dart';
import 'package:memex/data/memory_v3/services/query_log_service.dart';
import 'package:memex/data/memory_v3/services/record_organizer_service.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/domain/models/agent_definitions.dart';
import 'package:memex/domain/models/llm_config.dart';
import 'package:memex/utils/logger.dart';
import 'package:memex/utils/user_storage.dart';
import 'package:path_provider/path_provider.dart';

import 'memory_card_detail_screen_v3.dart';
import 'memory_summary_card_v3.dart';

final _logger = getLogger('MemoryV3LabScreen');

class MemoryV3LabScreen extends StatefulWidget {
  const MemoryV3LabScreen({super.key});

  @override
  State<MemoryV3LabScreen> createState() => _MemoryV3LabScreenState();
}

class _MemoryV3LabScreenState extends State<MemoryV3LabScreen> {
  final _scrollController = ScrollController();
  bool _busy = false;
  String? _lastError;
  String? _lastSuccess;
  List<MemoryCard> _recent = const [];
  List<MemoryFragment> _recentFragments = const [];
  List<MemoryEpisode> _recentEpisodes = const [];
  List<QueryLogEntry> _queryLogEntries = const [];
  List<DreamingRecallLogEntry> _dreamingRecallLogEntries = const [];
  int _zeroResultCount = 0;
  int _zeroDreamingRecallCount = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_loadRecent());
    unawaited(_loadRecentFragments());
    unawaited(_loadRecentEpisodes());
    unawaited(_loadQueryLog());
    unawaited(_loadDreamingRecallLog());
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadRecent() async {
    if (!RecordOrganizerServiceV3.isInitialized) return;
    final db = AppDatabase.instance;
    final rows = await (db.select(db.memoryCards)
          ..orderBy([(t) => drift.OrderingTerm.desc(t.updatedAt)])
          ..limit(50))
        .get();
    if (!mounted) return;
    setState(() => _recent = rows);
  }

  Future<void> _loadRecentFragments() async {
    if (!DreamingOrchestratorServiceV3.isInitialized) return;
    final db = AppDatabase.instance;
    final rows = await (db.select(db.memoryFragments)
          ..orderBy([(t) => drift.OrderingTerm.desc(t.createdAt)])
          ..limit(30))
        .get();
    if (!mounted) return;
    setState(() => _recentFragments = rows);
  }

  Future<void> _loadRecentEpisodes() async {
    if (!DreamingOrchestratorServiceV3.isInitialized) return;
    final db = AppDatabase.instance;
    final rows = await (db.select(db.memoryEpisodes)
          ..orderBy([(t) => drift.OrderingTerm.desc(t.createdAt)])
          ..limit(20))
        .get();
    if (!mounted) return;
    setState(() => _recentEpisodes = rows);
  }

  Future<void> _loadQueryLog() async {
    final entries = await QueryLogService.readAll();
    final zeros = await QueryLogService.zeroResultCount();
    if (!mounted) return;
    setState(() {
      _queryLogEntries = entries;
      _zeroResultCount = zeros;
    });
  }

  Future<void> _loadDreamingRecallLog() async {
    final entries = await DreamingRecallLogService.readAll();
    final zeros = await DreamingRecallLogService.zeroResultCount();
    if (!mounted) return;
    setState(() {
      _dreamingRecallLogEntries = entries;
      _zeroDreamingRecallCount = zeros;
    });
  }

  void _showQueryLog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _QueryLogSheet(
        entries: _queryLogEntries,
        zeroCount: _zeroResultCount,
        onClear: () async {
          await QueryLogService.clear();
          await _loadQueryLog();
        },
        onRefresh: () async {
          await _loadQueryLog();
          // ignore: use_build_context_synchronously
          Navigator.pop(ctx);
          _showQueryLog();
        },
      ),
    );
  }

  void _showDreamingRecallLog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _DreamingRecallLogSheet(
        entries: _dreamingRecallLogEntries,
        zeroCount: _zeroDreamingRecallCount,
        onClear: () async {
          await DreamingRecallLogService.clear();
          await _loadDreamingRecallLog();
        },
        onRefresh: () async {
          await _loadDreamingRecallLog();
          // ignore: use_build_context_synchronously
          Navigator.pop(ctx);
          _showDreamingRecallLog();
        },
      ),
    );
  }

  Future<void> _runDreamingFragmentBatch() async {
    if (!DreamingOrchestratorServiceV3.isInitialized) {
      setState(() => _lastError = 'Dreaming service 未初始化');
      return;
    }

    setState(() {
      _busy = true;
      _lastError = null;
      _lastSuccess = null;
    });

    try {
      final characterId = await _latestChatCharacterId();
      if (characterId == null) {
        if (!mounted) return;
        setState(() {
          _busy = false;
          _lastError = '没有可处理的聊天消息';
        });
        return;
      }

      final resources = await UserStorage.getAgentLLMResources(
        AgentDefinitions.recordOrganizerAgent,
        defaultClientKey: LLMConfig.defaultClientKey,
      );

      final result =
          await DreamingOrchestratorServiceV3.instance.runDailyFragmentBatch(
        characterId: characterId,
        client: resources.client,
        modelConfig: resources.modelConfig,
      );
      await _loadRecentFragments();
      if (!mounted) return;
      setState(() {
        _lastSuccess = result.processedMessageCount == 0
            ? 'Dreaming 没有新消息可处理'
            : 'Dreaming 处理 ${result.processedMessageCount} 条消息，写入 ${result.fragmentIds.length} 个 fragment';
      });
    } catch (e, stack) {
      _logger.warning('runDreamingFragmentBatch failed', e, stack);
      if (!mounted) return;
      setState(() => _lastError = 'Dreaming 失败：$e');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _runDailyDreamingBatchNow() async {
    if (!DreamingOrchestratorServiceV3.isInitialized) {
      setState(() => _lastError = 'Dreaming service 未初始化');
      return;
    }

    setState(() {
      _busy = true;
      _lastError = null;
      _lastSuccess = null;
    });

    try {
      final characterId = await _latestChatCharacterId();
      if (characterId == null) {
        if (!mounted) return;
        setState(() {
          _busy = false;
          _lastError = '没有可处理的聊天消息';
        });
        return;
      }

      final beforeFragmentCount = await _tableCount('memory_fragments');
      final beforeEpisodeCount = await _tableCount('memory_episodes');
      final beforeWatermark = await _dreamingWatermark(characterId);
      final latestMessageId = await _latestChatMessageId();

      final ok = await DreamingSchedulerService.runDailyDreamingFromBackground(
        db: AppDatabase.instance,
        characterId: characterId,
        forceRun: true,
      );
      final afterFragmentCount = await _tableCount('memory_fragments');
      final afterEpisodeCount = await _tableCount('memory_episodes');
      final afterWatermark = await _dreamingWatermark(characterId);
      await _loadRecentFragments();
      await _loadRecentEpisodes();
      if (!mounted) return;
      final processed = latestMessageId == null
          ? 0
          : (latestMessageId - beforeWatermark).clamp(0, latestMessageId);
      final fragmentDelta = afterFragmentCount - beforeFragmentCount;
      final episodeDelta = afterEpisodeCount - beforeEpisodeCount;
      setState(() {
        _lastSuccess = ok
            ? 'Daily Dreaming 已跑完：处理约 $processed 条新聊天'
                '（水位线 $beforeWatermark → $afterWatermark）\n'
                '新增 $fragmentDelta 个 fragment，新增 $episodeDelta 个 episode'
            : 'Daily Dreaming 未执行；请查看日志确认跳过原因';
      });
    } catch (e, stack) {
      _logger.warning('runDailyDreamingBatchNow failed', e, stack);
      if (!mounted) return;
      setState(() => _lastError = 'Daily Dreaming 失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<int> _tableCount(String tableName) async {
    final row = await AppDatabase.instance
        .customSelect('SELECT COUNT(*) AS c FROM $tableName')
        .getSingle();
    return row.read<int>('c');
  }

  Future<int> _dreamingWatermark(String characterId) async {
    final row = await (AppDatabase.instance.select(AppDatabase.instance.kvStore)
          ..where((t) =>
              t.bucket.equals('memory_v3.dreaming') &
              t.key.equals('dreaming.fragment.last_message_id.$characterId')))
        .getSingleOrNull();
    return int.tryParse(row?.value ?? '') ?? 0;
  }

  Future<void> _resetFragmentWatermark() async {
    final characterId = await _latestChatCharacterId();
    if (characterId == null) {
      if (!mounted) return;
      setState(() => _lastError = '未找到最近的 characterId');
      return;
    }
    final pendingExpr = AppDatabase.instance.personaChatMessages.id.count();
    final pendingRow = await (AppDatabase.instance.selectOnly(
      AppDatabase.instance.personaChatMessages,
    )..addColumns([pendingExpr])
          ..where(AppDatabase.instance.personaChatMessages.messageType
              .equals('chat')))
        .getSingle();
    final pending = pendingRow.read(pendingExpr) ?? 0;
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重置 Fragment 水位线？'),
        content: Text(
          '当前聊天累计 $pending 条 message。下一次 Fragment 抽取会从最早开始重新扫描 —— '
          '已抽取的 fragment 因内容哈希去重不会被重复保存；之前被旧模型拒接 '
          '(例如 NSFW 内容)而被跳过的批次会重新尝试。',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('重置', style: TextStyle(color: Colors.orange))),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() {
      _busy = true;
      _lastError = null;
      _lastSuccess = null;
    });

    try {
      final deleted = await DreamingOrchestratorServiceV3.instance
          .resetFragmentWatermark(characterId);
      if (!mounted) return;
      setState(() {
        _lastSuccess = deleted > 0
            ? '水位线已重置（共 $pending 条待扫描）'
            : '水位线本来就是空的，无需重置';
      });
    } catch (e, stack) {
      _logger.warning('resetFragmentWatermark failed', e, stack);
      if (!mounted) return;
      setState(() => _lastError = '重置失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _clearAllFragments() async {    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空所有 Dreaming fragments？'),
        content: const Text('这会删除所有 fragment、关联的 entity links 和水印标记。不能撤销。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('清空', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() {
      _busy = true;
      _lastError = null;
      _lastSuccess = null;
    });

    try {
      final count =
          await DreamingOrchestratorServiceV3.instance.clearAllFragments();
      await _loadRecentFragments();
      if (!mounted) return;
      setState(() {
        _lastSuccess = '已清空 $count 条 fragment';
      });
    } catch (e, stack) {
      _logger.warning('clearAllFragments failed', e, stack);
      if (!mounted) return;
      setState(() => _lastError = '清空失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

/// Open an edit dialog for a fragment's content. Tapping a fragment in
  /// the Lab list opens this; long-press opens [_fragmentActionsSheet] for
  /// status changes.
  ///
  /// Implemented as a `showModalBottomSheet` rather than `showDialog`
  /// because the dialog's title + content padding + default insetPadding
  /// overflow the viewport by ~36px when the soft keyboard is up. A bottom
  /// sheet with `isScrollControlled: true` is pushed up by the keyboard
  /// natively, so the form never overflows.
  Future<void> _editFragmentDialog(MemoryFragment fragment) async {
    final controller = TextEditingController(text: fragment.content);
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (ctx) {
        // viewInsets is the keyboard's height; padding the sheet by it
        // ensures the action row stays visible above the keyboard even
        // when the form scrolls.
        final keyboardInset = MediaQuery.of(ctx).viewInsets.bottom;
        return Padding(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 16 + keyboardInset),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('编辑 Fragment',
                    style: Theme.of(ctx).textTheme.titleMedium),
                const SizedBox(height: 8),
                Text('原始抽取: ${fragment.content}',
                    style: const TextStyle(fontSize: 11, color: Colors.black54)),
                const SizedBox(height: 4),
                Text(
                  fragment.userCorrected ? '状态: 已修正过' : '状态: 未修正',
                  style: const TextStyle(fontSize: 11, color: Colors.black45),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  maxLength: 80,
                  maxLines: 2,
                  minLines: 1,
                  autofocus: true,
                  textInputAction: TextInputAction.newline,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: '新内容',
                    helperText: '≤ 80 字；过短信息会丢失',
                  ),
                ),
                const SizedBox(height: 8),
                _EmotionalWeightSlider(
                  initial: fragment.emotionalWeight,
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('取消'),
                    ),
                    const SizedBox(width: 8),
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

    // The dialog also offers an emotionalWeight slider via a custom widget
    // that exposes its current value through a static setter. We keep it
    // simple here: only the content round-trips through the dialog; the
    // slider updates the weight as a side effect via a callback registered
    // below.
    setState(() {
      _busy = true;
      _lastError = null;
      _lastSuccess = null;
    });
    try {
      final newWeight = _EmotionalWeightSlider.lastPicked ?? fragment.emotionalWeight;
      await DreamingOrchestratorServiceV3.instance.updateFragment(
        fragment.id,
        content: result,
        emotionalWeight: newWeight != fragment.emotionalWeight
            ? newWeight
            : null,
        sourceKind: 'lab_edit',
      );
      await _loadRecentFragments();
      if (!mounted) return;
      setState(() => _lastSuccess = 'Fragment 已修正');
    } catch (e, stack) {
      _logger.warning('updateFragment failed', e, stack);
      if (!mounted) return;
      setState(() => _lastError = '修正失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Long-press menu for status changes (mark deleted / restore).
  Future<void> _fragmentActionsSheet(MemoryFragment fragment) async {
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
                color: Colors.red.shade700,
              ),
              title: Text(
                fragment.status == 'deleted' ? '恢复为 active' : '标记 deleted',
              ),
              subtitle: Text(
                fragment.status == 'deleted'
                    ? '从 FTS 移除 → 恢复 → 重新索引'
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
          await _editFragmentDialog(fragment);
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
      await _loadRecentFragments();
      if (!mounted) return;
      setState(() => _lastSuccess = '状态已更新');
    } catch (e, stack) {
      _logger.warning('fragment action failed', e, stack);
      if (!mounted) return;
      setState(() => _lastError = '操作失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Open an edit dialog for an episode's narrative + topic/confidence/etc.
  Future<void> _editEpisodeDialog(MemoryEpisode episode) async {
    final narrativeController =
        TextEditingController(text: episode.narrative);
    final topicController = TextEditingController(text: episode.topicId);
    final confidence = ValueNotifier<String>(episode.confidence);
    var significance = episode.significance;
    final valence = ValueNotifier<double>(episode.valence);
    final arousal = ValueNotifier<double>(episode.arousal);

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('编辑 Episode'),
        // SingleChildScrollView guards against bottom-overflow when the
        // soft keyboard pops up over the narrative field.
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('原始: ${episode.narrative}',
                  style: const TextStyle(fontSize: 11, color: Colors.black54)),
              const SizedBox(height: 4),
              Text(
                episode.userCorrected ? '状态: 已修正过' : '状态: 未修正',
                style: const TextStyle(fontSize: 11, color: Colors.black45),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: narrativeController,
                maxLines: 4,
                minLines: 2,
                autofocus: true,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Narrative (第一人称)',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: topicController,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Topic',
                  hintText: 'e.g. relationship_care',
                ),
              ),
              const SizedBox(height: 12),
              ValueListenableBuilder<String>(
                valueListenable: confidence,
                builder: (_, value, __) => DropdownButtonFormField<String>(
                  initialValue: value,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'Confidence',
                  ),
                  items: const [
                    DropdownMenuItem(value: 'high', child: Text('high')),
                    DropdownMenuItem(value: 'medium', child: Text('medium')),
                    DropdownMenuItem(value: 'low', child: Text('low')),
                  ],
                  onChanged: (v) {
                    if (v != null) confidence.value = v;
                  },
                ),
              ),
              const SizedBox(height: 12),
              _IntSliderField(
                label: 'Significance',
                min: 1,
                max: 10,
                value: significance,
                onChanged: (v) => significance = v,
              ),
              const SizedBox(height: 12),
              ValueListenableBuilder<double>(
                valueListenable: valence,
                builder: (_, v, __) => _DoubleSliderField(
                  label: 'Valence (-1..1)',
                  value: v,
                  min: -1.0,
                  max: 1.0,
                  onChanged: (nv) => valence.value = nv,
                ),
              ),
              const SizedBox(height: 8),
              ValueListenableBuilder<double>(
                valueListenable: arousal,
                builder: (_, v, __) => _DoubleSliderField(
                  label: 'Arousal (0..1)',
                  value: v,
                  min: 0.0,
                  max: 1.0,
                  onChanged: (nv) => arousal.value = nv,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('保存')),
        ],
      ),
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
        narrative: newNarrative != episode.narrative ? newNarrative : null,
        topicId:
            topicController.text.trim() != episode.topicId
                ? topicController.text.trim()
                : null,
        confidence: confidence.value != episode.confidence
            ? confidence.value
            : null,
        significance: significance != episode.significance ? significance : null,
        valence:
            valence.value != episode.valence ? valence.value : null,
        arousal:
            arousal.value != episode.arousal ? arousal.value : null,
        sourceKind: 'lab_edit',
      );
      await _loadRecentEpisodes();
      if (!mounted) return;
      setState(() => _lastSuccess = 'Episode 已修正');
    } catch (e, stack) {
      _logger.warning('updateEpisode failed', e, stack);
      if (!mounted) return;
      setState(() => _lastError = '修正失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Long-press menu for episode status changes.
  Future<void> _episodeActionsSheet(MemoryEpisode episode) async {
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
                color: Colors.red.shade700,
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
          await _editEpisodeDialog(episode);
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
      await _loadRecentEpisodes();
      if (!mounted) return;
      setState(() => _lastSuccess = '状态已更新');
    } catch (e, stack) {
      _logger.warning('episode action failed', e, stack);
      if (!mounted) return;
      setState(() => _lastError = '操作失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _clearAllEpisodes() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear all Dreaming episodes?'),
        content: const Text(
          'This deletes all generated episodes and their entity links. Source '
          'fragments used by those episodes will be set back to active.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Clear', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() {
      _busy = true;
      _lastError = null;
      _lastSuccess = null;
    });

    try {
      final count =
          await DreamingOrchestratorServiceV3.instance.clearAllEpisodes();
      await _loadRecentEpisodes();
      await _loadRecentFragments();
      if (!mounted) return;
      setState(() {
        _lastSuccess = 'Cleared $count episode(s)';
      });
    } catch (e, stack) {
      _logger.warning('clearAllEpisodes failed', e, stack);
      if (!mounted) return;
      setState(() => _lastError = 'Clear episodes failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _runEpisodeConsolidation() async {
    if (!DreamingOrchestratorServiceV3.isInitialized) {
      setState(() => _lastError = 'Dreaming service 未初始化');
      return;
    }

    setState(() {
      _busy = true;
      _lastError = null;
      _lastSuccess = null;
    });

    try {
      var preProcessedMessageCount = 0;
      var preFragmentCount = 0;
      final characterId = await _latestChatCharacterId();
      // Episode and fragment extraction share the same record_organizer_agent
      // model config; load it once and reuse for both stages.
      final fragmentResources = await UserStorage.getAgentLLMResources(
        AgentDefinitions.recordOrganizerAgent,
        defaultClientKey: LLMConfig.defaultClientKey,
      );
      if (characterId != null) {
        final fragmentResult =
            await DreamingOrchestratorServiceV3.instance.runDailyFragmentBatch(
          characterId: characterId,
          client: fragmentResources.client,
          modelConfig: fragmentResources.modelConfig,
        );
        preProcessedMessageCount = fragmentResult.processedMessageCount;
        preFragmentCount = fragmentResult.fragmentIds.length;
      }

      final resources = fragmentResources;

      final result =
          await DreamingOrchestratorServiceV3.instance.runEpisodeConsolidation(
        client: resources.client,
        modelConfig: resources.modelConfig,
      );
      await _loadRecentEpisodes();
      await _loadRecentFragments();
      if (!mounted) return;
      setState(() {
        if (result.isEmpty) {
          _lastError = 'Episode 凝结未产生结果\n'
              '${result.skippedEntities.join("\n")}';
        } else {
          final entitySummary = result.consolidatedEntities.take(3).join(", ");
          var msg = preProcessedMessageCount > 0
              ? '先处理 $preProcessedMessageCount 条聊天，写入 $preFragmentCount 个 fragment\n'
              : '';
          msg = '$msg凝结 ${result.episodeIds.length} 条 Episode\n'
              '实体: $entitySummary'
              '${result.consolidatedEntities.length > 3 ? " 等${result.consolidatedEntities.length}个" : ""}\n'
              '消耗 ${result.consolidatedFragmentCount} 条 fragment';
          if (result.skippedEntities.isNotEmpty) {
            final skipSummary = result.skippedEntities.take(3).join(", ");
            msg = '$msg\n跳过: $skipSummary'
                '${result.skippedEntities.length > 3 ? " 等${result.skippedEntities.length}个" : ""}';
          }
          _lastSuccess = msg;
        }
      });
    } catch (e, stack) {
      _logger.warning('runEpisodeConsolidation failed', e, stack);
      if (!mounted) return;
      setState(() => _lastError = 'Episode 凝结失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _latestChatCharacterId() async {
    final db = AppDatabase.instance;
    final rows = await (db.select(db.personaChatMessages)
          ..orderBy([
            (t) => drift.OrderingTerm.desc(t.timestamp),
            (t) => drift.OrderingTerm.desc(t.id),
          ])
          ..limit(1))
        .get();
    return rows.isEmpty ? null : rows.single.characterId;
  }

  Future<int?> _latestChatMessageId() async {
    final db = AppDatabase.instance;
    final rows = await (db.select(db.personaChatMessages)
          ..where((t) => t.messageType.equals('chat'))
          ..orderBy([(t) => drift.OrderingTerm.desc(t.id)])
          ..limit(1))
        .get();
    return rows.isEmpty ? null : rows.single.id;
  }

  Future<void> _deleteCard(MemoryCard card) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除这张卡？'),
        content: Text(card.dropletLabel),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('删除')),
        ],
      ),
    );
    if (confirmed != true) return;
    await RecordOrganizerServiceV3.instance.deleteCard(card.id);
    await _loadRecent();
  }

  void _showCardDetail(MemoryCard card) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MemoryCardDetailScreenV3(
          cardId: card.id,
          queryService: MemoryCardQueryService(AppDatabase.instance),
        ),
      ),
    );
  }

  void _previewCard(MemoryCard card) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Row(
          children: [
            const Text('卡片预览'),
            const Spacer(),
            Text(card.dropletLabel,
                style: const TextStyle(fontSize: 13, color: Colors.black54)),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: MemorySummaryCardV3(
            card: _cardToViewData(card),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  MemoryCardViewData _cardToViewData(MemoryCard card) {
    return MemoryCardViewData(
      id: card.id,
      type: card.type,
      title: card.title,
      dropletLabel: card.dropletLabel,
      presentationModule: card.presentationModule,
      retrievalText: card.retrievalText,
      valence: card.valence,
      arousal: card.arousal,
      status: card.status,
      needsFollowUp: MemoryCardViewData.parseNeedsFollowUp(card.needsFollowUp),
      createdAt: card.createdAt,
      updatedAt: card.updatedAt,
    );
  }

  Object? _decode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      return jsonDecode(raw);
    } catch (_) {
      return raw;
    }
  }

  /// Dump all current memory_cards + dreaming fragments (plus source /
  /// structured / entity links) to a JSON file in the app's external dir.
  /// Returns the absolute path on success.
  ///
  /// Path layout on Android (no permissions needed):
  ///   /sdcard/Android/data/com.memexlab.hereiam.v3/files/v3_dump.json
  /// Pull with:
  ///   adb pull <that path> ./v3_dump.json
  Future<({String path, int cardCount, int fragmentCount, int episodeCount})?>
      _dumpAllToFile() async {
    final db = AppDatabase.instance;
    final cards = await (db.select(db.memoryCards)
          ..orderBy([(t) => drift.OrderingTerm.desc(t.updatedAt)]))
        .get();

    final fragments = await (db.select(db.memoryFragments)
          ..orderBy([(t) => drift.OrderingTerm.desc(t.createdAt)]))
        .get();

    final episodes = await (db.select(db.memoryEpisodes)
          ..orderBy([(t) => drift.OrderingTerm.desc(t.createdAt)]))
        .get();

    final dump = <Map<String, dynamic>>[];
    for (final card in cards) {
      final source = await (db.select(db.memoryCardSources)
            ..where((t) => t.cardId.equals(card.id)))
          .getSingleOrNull();
      final structured = await (db.select(db.memoryCardStructuredFields)
            ..where((t) => t.cardId.equals(card.id)))
          .getSingleOrNull();
      final links = await (db.select(db.memoryEntityLinks)
            ..where((t) =>
                t.sourceTable.equals('memory_cards') &
                t.sourceId.equals(card.id)))
          .get();
      final entities = <MemoryEntity?>[];
      for (final link in links) {
        final e = await (db.select(db.memoryEntities)
              ..where((t) => t.id.equals(link.entityId)))
            .getSingleOrNull();
        entities.add(e);
      }

      dump.add({
        'card': {
          'id': card.id,
          'memoryScope': card.memoryScope,
          'type': card.type,
          'title': card.title,
          'dropletLabel': card.dropletLabel,
          'presentationModule': _decode(card.presentationModule),
          'retrievalText': card.retrievalText,
          'valence': card.valence,
          'arousal': card.arousal,
          'status': card.status,
          'needsFollowUp': _decode(card.needsFollowUp),
          'createdAt': DateTime.fromMillisecondsSinceEpoch(card.createdAt)
              .toIso8601String(),
          'updatedAt': DateTime.fromMillisecondsSinceEpoch(card.updatedAt)
              .toIso8601String(),
        },
        'source': source == null
            ? null
            : {
                'rawInput': source.rawInput,
                'recordedAt':
                    DateTime.fromMillisecondsSinceEpoch(source.recordedAt)
                        .toIso8601String(),
                'recordedPlace': source.recordedPlace,
                'sourceRef': source.sourceRef,
                'sourceKind': source.sourceKind,
              },
        'structuredFields': structured == null
            ? null
            : {
                'type': structured.structuredFieldsType,
                'fields': _decode(structured.fieldsJson),
                'userCorrected': structured.userCorrected,
              },
        'entityLinks': [
          for (var i = 0; i < links.length; i++)
            {
              'relation': links[i].relation,
              'confidence': links[i].confidence,
              'entity': entities[i] == null
                  ? {'id': links[i].entityId, 'missing': true}
                  : {
                      'id': entities[i]!.id,
                      'name': entities[i]!.name,
                      'category': entities[i]!.category,
                      'status': entities[i]!.status,
                      'relationshipToUser': entities[i]!.relationshipToUser,
                    },
            },
        ],
      });
    }

    final payload = {
      'exportedAt': DateTime.now().toIso8601String(),
      'cardCount': dump.length,
      'cards': dump,
      'fragmentCount': fragments.length,
      'fragments': fragments
          .map((f) => {
                'id': f.id,
                'content': f.content,
                'sourceMessageIds': _decode(f.sourceMessageIds),
                'sourceScope': f.sourceScope,
                'emotionalWeight': f.emotionalWeight,
                'status': f.status,
                'isUserTruthCandidate': f.isUserTruthCandidate,
                'generatedByVersion': f.generatedByVersion,
                'createdAt': DateTime.fromMillisecondsSinceEpoch(f.createdAt)
                    .toIso8601String(),
              })
          .toList(),
      'episodeCount': episodes.length,
      'episodes': episodes
          .map((e) => {
                'id': e.id,
                'primaryEntityId': e.primaryEntityId,
                'topicId': e.topicId,
                'narrative': e.narrative,
                'sourceFragmentIds': _decode(e.sourceFragmentIds),
                'significance': e.significance,
                'confidence': e.confidence,
                'valence': e.valence,
                'arousal': e.arousal,
                'occurredAtRange': _decode(e.occurredAtRange),
                'status': e.status,
                'generatedByVersion': e.generatedByVersion,
                'createdAt': DateTime.fromMillisecondsSinceEpoch(e.createdAt)
                    .toIso8601String(),
              })
          .toList(),
    };

    try {
      final dir = await getExternalStorageDirectory();
      if (dir == null) return null;
      final file = File('${dir.path}/v3_dump.json');
      await file.writeAsString(
          const JsonEncoder.withIndent('  ').convert(payload),
          flush: true);
      return (
        path: file.path,
        cardCount: cards.length,
        fragmentCount: fragments.length,
        episodeCount: episodes.length
      );
    } catch (e, st) {
      _logger.warning('dumpAllToFile failed', e, st);
      return null;
    }
  }

  Future<void> _onExportTap() async {
    setState(() {
      _busy = true;
      _lastError = null;
      _lastSuccess = null;
    });
    final result = await _dumpAllToFile();
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (result == null) {
        _lastError = '导出失败（看 logcat）';
      } else {
        _lastSuccess =
            '已导出 ${result.cardCount} 张卡 + ${result.fragmentCount} fragment + ${result.episodeCount} episode 到\n${result.path}';
        Clipboard.setData(ClipboardData(text: result.path));
      }
    });
  }

  Future<void> _onReindexFts() async {
    setState(() {
      _busy = true;
      _lastError = null;
      _lastSuccess = null;
    });
    try {
      final count = await RecordOrganizerServiceV3.instance.reindexAllCards();
      if (!mounted) return;
      setState(() {
        _busy = false;
        _lastSuccess = 'FTS 索引重建完成：$count 张卡片';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _lastError = 'FTS 重建失败：$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Memory V3 Lab'),
        actions: [
          IconButton(
            icon: const Icon(Icons.file_download_outlined),
            onPressed: _busy ? null : _onExportTap,
            tooltip: '导出所有卡片到文件',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              unawaited(_loadRecent());
              unawaited(_loadRecentFragments());
              unawaited(_loadRecentEpisodes());
              unawaited(_loadQueryLog());
              unawaited(_loadDreamingRecallLog());
            },
            tooltip: '刷新',
          ),
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: _busy ? null : _onReindexFts,
            tooltip: '重建 FTS 搜索索引',
          ),
          IconButton(
            icon: Badge(
              isLabelVisible: _zeroResultCount > 0,
              label: Text('$_zeroResultCount',
                  style: const TextStyle(fontSize: 11)),
              child: const Icon(Icons.query_stats),
            ),
            onPressed: _showQueryLog,
            tooltip: '查询日志（零结果: $_zeroResultCount）',
          ),
          IconButton(
            icon: Badge(
              isLabelVisible: _zeroDreamingRecallCount > 0,
              label: Text('$_zeroDreamingRecallCount',
                  style: const TextStyle(fontSize: 11)),
              child: const Icon(Icons.auto_awesome_motion_outlined),
            ),
            onPressed: _showDreamingRecallLog,
            tooltip: 'Dreaming 召回日志（零结果: $_zeroDreamingRecallCount）',
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: EdgeInsets.zero,
                  initiallyExpanded: true,
                  title: const Text('Dreaming 调试'),
                  subtitle: Text(
                    'fragments ${_recentFragments.length} · episodes ${_recentEpisodes.length}',
                    style: const TextStyle(fontSize: 12),
                  ),
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          FilledButton.icon(
                            onPressed: _busy ? null : _runDailyDreamingBatchNow,
                            icon: _busy
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  )
                                : const Icon(Icons.bedtime_outlined),
                            label: Text(
                              _busy ? 'running…' : 'run daily batch now',
                            ),
                          ),
                          OutlinedButton.icon(
                            onPressed: _busy ? null : _runDreamingFragmentBatch,
                            icon: const Icon(Icons.nightlight_round),
                            label: const Text('fragments only'),
                          ),
                          OutlinedButton.icon(
                            onPressed: _busy ? null : _runEpisodeConsolidation,
                            icon: const Icon(Icons.auto_awesome),
                            label: const Text('episodes only'),
                          ),
                          OutlinedButton.icon(
                            onPressed: _busy ? null : _clearAllEpisodes,
                            icon: const Icon(Icons.delete_sweep_outlined,
                                color: Colors.red),
                            label: const Text('clear episodes',
                                style: TextStyle(color: Colors.red)),
                          ),
                          OutlinedButton.icon(
                            onPressed: _busy ? null : _resetFragmentWatermark,
                            icon: const Icon(Icons.restart_alt,
                                color: Colors.orange),
                            label: const Text('reset watermark',
                                style: TextStyle(color: Colors.orange)),
                          ),
                          OutlinedButton.icon(
                            onPressed: _busy ? null : _clearAllFragments,
                            icon: const Icon(Icons.delete_outline,
                                color: Colors.red),
                            label: const Text('clear fragments',
                                style: TextStyle(color: Colors.red)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (_lastError != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: _LabStatusMessage(
                      message: _lastError!,
                      color: Colors.red,
                    ),
                  ),
                if (_lastSuccess != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: _LabStatusMessage(
                      message: _lastSuccess!,
                      color: Colors.green,
                    ),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Wrap(
              spacing: 12,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text('最近 ${_recent.length} 张 memory_cards',
                    style: Theme.of(context).textTheme.titleSmall),
                Text('fragments ${_recentFragments.length}',
                    style: const TextStyle(fontSize: 11)),
                Text('episodes ${_recentEpisodes.length}',
                    style: const TextStyle(fontSize: 11)),
                Text('recall logs ${_dreamingRecallLogEntries.length}',
                    style: const TextStyle(fontSize: 11)),
                Text(
                  RecordOrganizerServiceV3.isInitialized
                      ? 'service: ready'
                      : 'service: not initialized',
                  style: TextStyle(
                      fontSize: 11,
                      color: RecordOrganizerServiceV3.isInitialized
                          ? Colors.green
                          : Colors.red),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              controller: _scrollController,
              children: [
                ExpansionTile(
                  title: Text('最近 memory_cards',
                      style: Theme.of(context).textTheme.titleSmall),
                  subtitle: Text('${_recent.length} 张 · 来自真实记录入口',
                      style: const TextStyle(fontSize: 11)),
                  children: _recent.isEmpty
                      ? const [
                          Padding(
                            padding: EdgeInsets.all(24),
                            child: Center(child: Text('（暂无 memory_cards）')),
                          ),
                        ]
                      : _recent
                          .map(
                            (card) => _CardListTile(
                              card: card,
                              onTap: () => _showCardDetail(card),
                              onLongPress: () => _deleteCard(card),
                              onPreview: () => _previewCard(card),
                            ),
                          )
                          .toList(growable: false),
                ),
                const Divider(height: 1),
                ExpansionTile(
                  title: Text('最近 Dreaming fragments',
                      style: Theme.of(context).textTheme.titleSmall),
                  subtitle: Text('${_recentFragments.length} 条',
                      style: const TextStyle(fontSize: 11)),
                  children: _recentFragments.isEmpty
                      ? const [
                          Padding(
                            padding: EdgeInsets.all(24),
                            child: Center(child: Text('（暂无 fragments）')),
                          ),
                        ]
                      : _recentFragments
                          .map((fragment) => _FragmentListTile(
                                fragment: fragment,
                                onTap: () => _editFragmentDialog(fragment),
                                onLongPress: () =>
                                    _fragmentActionsSheet(fragment),
                              ))
                          .toList(growable: false),
                ),
                const Divider(height: 1),
                ExpansionTile(
                  title: Text('最近 Episodes',
                      style: Theme.of(context).textTheme.titleSmall),
                  subtitle: Text('${_recentEpisodes.length} 条',
                      style: const TextStyle(fontSize: 11)),
                  children: _recentEpisodes.isEmpty
                      ? const [
                          Padding(
                            padding: EdgeInsets.all(24),
                            child: Center(child: Text('（暂无 episodes）')),
                          ),
                        ]
                      : _recentEpisodes
                          .map((ep) => _EpisodeListTile(
                                episode: ep,
                                onTap: () => _editEpisodeDialog(ep),
                                onLongPress: () =>
                                    _episodeActionsSheet(ep),
                              ))
                          .toList(growable: false),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LabStatusMessage extends StatelessWidget {
  const _LabStatusMessage({
    required this.message,
    required this.color,
  });

  final String message;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 96),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withValues(alpha: 0.22)),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: SelectableText(
            message,
            style: TextStyle(color: color, fontSize: 12, height: 1.35),
          ),
        ),
      ),
    );
  }
}

class _EpisodeListTile extends StatelessWidget {
  const _EpisodeListTile({
    required this.episode,
    required this.onTap,
    required this.onLongPress,
  });

  final MemoryEpisode episode;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final createdAt =
        DateTime.fromMillisecondsSinceEpoch(episode.createdAt).toString();
    final corrected = episode.userCorrected ? ' · 已修正' : '';
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.auto_awesome,
              size: 18,
              color: Colors.purple.shade400,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(episode.narrative,
                      style: const TextStyle(fontWeight: FontWeight.w500),
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  Text(
                    'sig ${episode.significance} · ${episode.confidence} · '
                    '${episode.topicId} · '
                    'v ${episode.valence.toStringAsFixed(2)} '
                    'a ${episode.arousal.toStringAsFixed(2)} · '
                    '${episode.status} · $createdAt$corrected',
                    style: const TextStyle(
                        fontSize: 10, color: Colors.black38),
                  ),
                ],
              ),
            ),
            const Icon(Icons.edit_outlined, size: 16, color: Colors.black26),
          ],
        ),
      ),
    );
  }
}

class _FragmentListTile extends StatelessWidget {
  const _FragmentListTile({
    required this.fragment,
    required this.onTap,
    required this.onLongPress,
  });

  final MemoryFragment fragment;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final createdAt =
        DateTime.fromMillisecondsSinceEpoch(fragment.createdAt).toString();
    final corrected = fragment.userCorrected
        ? ' · 已修正'
        : '';
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              fragment.isUserTruthCandidate
                  ? Icons.new_releases_outlined
                  : Icons.auto_awesome_outlined,
              size: 18,
              color: fragment.isUserTruthCandidate
                  ? Colors.orange.shade700
                  : Colors.blueGrey.shade400,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(fragment.content,
                      style: const TextStyle(fontWeight: FontWeight.w500)),
                  const SizedBox(height: 4),
                  Text(
                    '${fragment.status} · weight ${fragment.emotionalWeight.toStringAsFixed(2)} · $createdAt$corrected',
                    style: const TextStyle(
                        fontSize: 10, color: Colors.black38),
                  ),
                ],
              ),
            ),
            const Icon(Icons.edit_outlined, size: 16, color: Colors.black26),
          ],
        ),
      ),
    );
  }
}

class _CardListTile extends StatelessWidget {
  const _CardListTile({
    required this.card,
    required this.onTap,
    required this.onLongPress,
    required this.onPreview,
  });

  final MemoryCard card;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onPreview;

  @override
  Widget build(BuildContext context) {
    final mood = _moodColor(card.valence, card.arousal);
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 8,
              height: 8,
              margin: const EdgeInsets.only(top: 6, right: 10),
              decoration: BoxDecoration(color: mood, shape: BoxShape.circle),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(card.dropletLabel,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                            overflow: TextOverflow.ellipsis),
                      ),
                      Container(
                        margin: const EdgeInsets.only(left: 6),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(card.dropletLabel,
                            style: const TextStyle(fontSize: 11)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(card.retrievalText,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style:
                          const TextStyle(fontSize: 12, color: Colors.black54)),
                  const SizedBox(height: 4),
                  Text(
                    '${card.type} · v ${card.valence.toStringAsFixed(2)} '
                    '· a ${card.arousal.toStringAsFixed(2)} '
                    '· ${DateTime.fromMillisecondsSinceEpoch(card.updatedAt)}',
                    style: const TextStyle(fontSize: 10, color: Colors.black38),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.visibility_outlined, size: 18),
              tooltip: '预览卡片',
              onPressed: onPreview,
            ),
          ],
        ),
      ),
    );
  }

  Color _moodColor(double valence, double arousal) {
    if (arousal < 0.3) return Colors.grey.shade400;
    if (valence > 0.3) return Colors.orange.shade300;
    if (valence < -0.3) return Colors.blueGrey.shade400;
    return Colors.amber.shade200;
  }
}

class _QueryLogSheet extends StatelessWidget {
  const _QueryLogSheet({
    required this.entries,
    required this.zeroCount,
    required this.onClear,
    required this.onRefresh,
  });

  final List<QueryLogEntry> entries;
  final int zeroCount;
  final VoidCallback onClear;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.3,
      maxChildSize: 0.95,
      expand: false,
      builder: (ctx, scrollController) => Column(
        children: [
          // Handle bar
          Center(
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                Text('查询日志', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(width: 8),
                if (zeroCount > 0)
                  Chip(
                    label: Text('$zeroCount 条零结果',
                        style: const TextStyle(fontSize: 11)),
                    backgroundColor: Colors.orange.shade100,
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                const Spacer(),
                if (entries.isNotEmpty) ...[
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 20),
                    onPressed: () => _confirmClear(context),
                    tooltip: '清空日志',
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh, size: 20),
                    onPressed: onRefresh,
                    tooltip: '刷新',
                  ),
                ],
              ],
            ),
          ),
          const Divider(),
          // Body
          Expanded(
            child: entries.isEmpty
                ? const Center(
                    child:
                        Text('暂无查询记录', style: TextStyle(color: Colors.black45)))
                : ListView.separated(
                    controller: scrollController,
                    itemCount: entries.length,
                    separatorBuilder: (_, __) =>
                        const Divider(height: 1, indent: 16),
                    itemBuilder: (ctx, i) => _QueryLogTile(entry: entries[i]),
                  ),
          ),
        ],
      ),
    );
  }

  void _confirmClear(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空查询日志？'),
        content: const Text('这会删除所有查询记录，包括零结果标记。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              onClear();
              Navigator.pop(context); // close the sheet
            },
            child: const Text('清空'),
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
    final isZero = entry.isZeroResult;
    final time = entry.dateTime;
    final timeStr =
        '${time.month}/${time.day} ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';

    return ListTile(
      dense: true,
      leading: CircleAvatar(
        radius: 12,
        backgroundColor: isZero ? Colors.red.shade100 : Colors.green.shade100,
        child: Text(
          '${entry.resultCount}',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: isZero ? Colors.red.shade700 : Colors.green.shade700,
          ),
        ),
      ),
      title: Text(
        entry.query,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 14),
      ),
      subtitle: Text(
        '$timeStr · $_strategyLabel · ${entry.actualSummary}',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
      ),
    );
  }
}

class _DreamingRecallLogSheet extends StatelessWidget {
  const _DreamingRecallLogSheet({
    required this.entries,
    required this.zeroCount,
    required this.onClear,
    required this.onRefresh,
  });

  final List<DreamingRecallLogEntry> entries;
  final int zeroCount;
  final VoidCallback onClear;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final coverage = DreamingRecallCoverage.fromEntries(entries);
    return DraggableScrollableSheet(
      initialChildSize: 0.76,
      minChildSize: 0.3,
      maxChildSize: 0.95,
      expand: false,
      builder: (ctx, scrollController) => Column(
        children: [
          Center(
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('Dreaming 召回日志',
                        style: Theme.of(context).textTheme.titleMedium),
                    const Spacer(),
                    if (entries.isNotEmpty) ...[
                      IconButton(
                        icon: const Icon(Icons.delete_outline, size: 20),
                        onPressed: () => _confirmClear(context),
                        tooltip: '清空日志',
                      ),
                      IconButton(
                        icon: const Icon(Icons.refresh, size: 20),
                        onPressed: onRefresh,
                        tooltip: '刷新',
                      ),
                    ],
                  ],
                ),
                if (coverage.total > 0)
                  Text(
                    '近 ${coverage.total} 轮：Episode 命中 ${coverage.episodeMatched} · '
                    '仅 Fragment ${coverage.fragmentOnly} · '
                    '零结果 $zeroCount',
                    style: TextStyle(
                      fontSize: 11,
                      color: zeroCount > 0
                          ? Colors.orange.shade800
                          : Colors.grey.shade600,
                    ),
                  ),
              ],
            ),
          ),
          const Divider(),
          Expanded(
            child: entries.isEmpty
                ? const Center(
                    child: Text('暂无 Dreaming 召回记录',
                        style: TextStyle(color: Colors.black45)))
                : ListView.separated(
                    controller: scrollController,
                    itemCount: entries.length,
                    separatorBuilder: (_, __) =>
                        const Divider(height: 1, indent: 16),
                    itemBuilder: (ctx, i) =>
                        _DreamingRecallLogTile(entry: entries[i]),
                  ),
          ),
        ],
      ),
    );
  }

  void _confirmClear(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空 Dreaming 召回日志？'),
        content: const Text('这会删除所有 Dreaming context 注入记录。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              onClear();
              Navigator.pop(context);
            },
            child: const Text('清空'),
          ),
        ],
      ),
    );
  }
}

class _DreamingRecallLogTile extends StatelessWidget {
  const _DreamingRecallLogTile({required this.entry});

  final DreamingRecallLogEntry entry;

  @override
  Widget build(BuildContext context) {
    final isZero = entry.isZeroResult;
    final time = entry.dateTime;
    final timeStr =
        '${time.month}/${time.day} ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    final color = isZero ? Colors.red : Colors.deepPurple;

    return ExpansionTile(
      dense: true,
      leading: CircleAvatar(
        radius: 13,
        backgroundColor: color.shade100,
        child: Text(
          '${entry.episodeCount}/${entry.fragmentCount}',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: color.shade700,
          ),
        ),
      ),
      title: Text(
        entry.query.trim().isEmpty ? '（空 query）' : entry.query,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 14),
      ),
      subtitle: Text(
        '$timeStr · episode ${entry.episodeCount} · fragment ${entry.fragmentCount} · ${entry.actualSummary}',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
      ),
      children: [
        if (entry.episodes.isNotEmpty)
          _RecallSection(
            title: 'Episodes',
            children: entry.episodes
                .map((hit) => _RecallHitText(
                      title:
                          'score ${hit.score} · sig ${hit.significance} · ${hit.topicId ?? '__ungrouped__'}',
                      body: hit.narrative,
                    ))
                .toList(growable: false),
          ),
        if (entry.fragments.isNotEmpty)
          _RecallSection(
            title: 'Fragments',
            children: entry.fragments
                .map((hit) => _RecallHitText(
                      title:
                          'score ${hit.score} · weight ${hit.emotionalWeight.toStringAsFixed(2)}${hit.isUserTruthCandidate ? ' · user_truth' : ''}',
                      body: hit.content,
                    ))
                .toList(growable: false),
          ),
        _RecallSection(
          title: 'Injected context',
          children: [
            SelectableText(
              entry.injectedContext.trim().isEmpty
                  ? '（本轮没有注入 dreaming_context）'
                  : entry.injectedContext,
              style: const TextStyle(fontSize: 11, height: 1.35),
            ),
          ],
        ),
      ],
    );
  }
}

class _RecallSection extends StatelessWidget {
  const _RecallSection({
    required this.title,
    required this.children,
  });

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(56, 4, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style:
                  const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          ...children,
        ],
      ),
    );
  }
}

class _RecallHitText extends StatelessWidget {
  const _RecallHitText({
    required this.title,
    required this.body,
  });

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
          const SizedBox(height: 2),
          SelectableText(body, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }
}

/// Slider for picking a fragment's emotional weight (0.0 .. 1.0).
///
/// Stashes the last picked value in [lastPicked] so the parent dialog can
/// read it after the user taps Save. This is intentionally simple — the
/// dialog doesn't otherwise have a way to receive the slider's current
/// value back without rebuilding the dialog tree.
class _EmotionalWeightSlider extends StatefulWidget {
  const _EmotionalWeightSlider({required this.initial});

  final double initial;

  /// Last value picked via the slider. Null if the user never moved it.
  static double? lastPicked;

  @override
  State<_EmotionalWeightSlider> createState() => _EmotionalWeightSliderState();
}

class _EmotionalWeightSliderState extends State<_EmotionalWeightSlider> {
  late double _value = widget.initial;

  @override
  void initState() {
    super.initState();
    _EmotionalWeightSlider.lastPicked = null;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('情感权重: ${_value.toStringAsFixed(2)}',
            style: const TextStyle(fontSize: 12)),
        Slider(
          value: _value,
          min: 0,
          max: 1,
          divisions: 20,
          label: _value.toStringAsFixed(2),
          onChanged: (v) {
            setState(() => _value = v);
            _EmotionalWeightSlider.lastPicked = v;
          },
        ),
      ],
    );
  }
}

/// Int slider (1..10) for episode significance. Local state; parent
/// receives changes via [onChanged] and decides what to do.
class _IntSliderField extends StatelessWidget {
  const _IntSliderField({
    required this.label,
    required this.min,
    required this.max,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final int min;
  final int max;
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 120,
          child: Text('$label: $value',
              style: const TextStyle(fontSize: 12)),
        ),
        Expanded(
          child: Slider(
            value: value.toDouble(),
            min: min.toDouble(),
            max: max.toDouble(),
            divisions: max - min,
            label: '$value',
            onChanged: (v) => onChanged(v.round()),
          ),
        ),
      ],
    );
  }
}

/// Double slider with a fixed value range. Used for valence and arousal
/// on episode edits.
class _DoubleSliderField extends StatelessWidget {
  const _DoubleSliderField({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 120,
          child: Text('$label: ${value.toStringAsFixed(2)}',
              style: const TextStyle(fontSize: 12)),
        ),
        Expanded(
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: 20,
            label: value.toStringAsFixed(2),
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}
