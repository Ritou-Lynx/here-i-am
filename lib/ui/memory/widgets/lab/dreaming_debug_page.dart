/// Memory V3 Lab - Dreaming scheduler debug page.
///
/// Hosts the 8 previously flat buttons, now grouped into 4 sections:
/// batch run, episode consolidation, saga weaving, and destructive cleanup.
library;

import 'package:flutter/material.dart';
import 'package:drift/drift.dart' as drift;
import 'package:memex/data/memory_v3/services/dreaming_orchestrator_service.dart';
import 'package:memex/data/memory_v3/services/dreaming_scheduler_service.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/domain/models/agent_definitions.dart';
import 'package:memex/domain/models/llm_config.dart';
import 'package:memex/ui/core/themes/spring_rain_ui_tokens.dart';
import 'package:memex/ui/memory/widgets/lab/lab_shared.dart';
import 'package:memex/utils/logger.dart';
import 'package:memex/utils/user_storage.dart';

final _logger = getLogger('LabDreamingDebugPage');

class LabDreamingDebugPage extends StatefulWidget {
  const LabDreamingDebugPage({super.key});

  @override
  State<LabDreamingDebugPage> createState() => _LabDreamingDebugPageState();
}

class _LabDreamingDebugPageState extends State<LabDreamingDebugPage> {
  bool _busy = false;
  String? _lastError;
  String? _lastSuccess;

  void _setBusy() {
    setState(() {
      _busy = true;
      _lastError = null;
      _lastSuccess = null;
    });
  }

  Future<void> _runDailyBatchNow() async {
    if (!DreamingOrchestratorServiceV3.isInitialized) {
      setState(() => _lastError = 'Dreaming service 未初始化');
      return;
    }
    _setBusy();
    try {
      final characterId = await latestChatCharacterId();
      if (characterId == null) {
        if (!mounted) return;
        setState(() {
          _busy = false;
          _lastError = '没有可处理的聊天消息';
        });
        return;
      }
      final beforeFragmentCount = await tableCount('memory_fragments');
      final beforeEpisodeCount = await tableCount('memory_episodes');
      final beforeWatermark = await dreamingWatermark(characterId);
      final latestMessageId = await latestChatMessageId();

      final ok = await DreamingSchedulerService.runDailyDreamingFromBackground(
        db: AppDatabase.instance,
        characterId: characterId,
        forceRun: true,
      );
      final afterFragmentCount = await tableCount('memory_fragments');
      final afterEpisodeCount = await tableCount('memory_episodes');
      final afterWatermark = await dreamingWatermark(characterId);
      if (!mounted) return;
      final processed = latestMessageId == null
          ? 0
          : (latestMessageId - beforeWatermark).clamp(0, latestMessageId);
      final fragmentDelta = afterFragmentCount - beforeFragmentCount;
      final episodeDelta = afterEpisodeCount - beforeEpisodeCount;
      setState(() {
        _lastSuccess = ok
            ? 'Daily Dreaming 已跑完：处理约 $processed 条新聊天'
                '（水位线 $beforeWatermark -> $afterWatermark）\n'
                '新增 $fragmentDelta 个 fragment，新增 $episodeDelta 个 episode'
            : 'Daily Dreaming 未执行；请查看日志确认跳过原因';
      });
    } catch (e, st) {
      _logger.warning('runDailyDreamingBatchNow failed', e, st);
      if (!mounted) return;
      setState(() => _lastError = 'Daily Dreaming 失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _runFragmentsOnly() async {
    if (!DreamingOrchestratorServiceV3.isInitialized) {
      setState(() => _lastError = 'Dreaming service 未初始化');
      return;
    }
    _setBusy();
    try {
      final characterId = await latestChatCharacterId();
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
      if (!mounted) return;
      setState(() {
        _lastSuccess = result.processedMessageCount == 0
            ? 'Dreaming 没有新消息可处理'
            : 'Dreaming 处理 ${result.processedMessageCount} 条消息，写入 ${result.fragmentIds.length} 个 fragment';
      });
    } catch (e, st) {
      _logger.warning('runDreamingFragmentBatch failed', e, st);
      if (!mounted) return;
      setState(() => _lastError = 'Dreaming 失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _runEpisodesOnly() async {
    if (!DreamingOrchestratorServiceV3.isInitialized) {
      setState(() => _lastError = 'Dreaming service 未初始化');
      return;
    }
    _setBusy();
    try {
      final characterId = await latestChatCharacterId();
      final fragmentResources = await UserStorage.getAgentLLMResources(
        AgentDefinitions.recordOrganizerAgent,
        defaultClientKey: LLMConfig.defaultClientKey,
      );
      var preProcessedMessageCount = 0;
      var preFragmentCount = 0;
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
      final result =
          await DreamingOrchestratorServiceV3.instance.runEpisodeConsolidation(
        client: fragmentResources.client,
        modelConfig: fragmentResources.modelConfig,
      );
      if (!mounted) return;
      setState(() {
        if (result.isEmpty) {
          _lastError =
              'Episode 凝结未产生结果\n${result.skippedEntities.join("\n")}';
        } else {
          final entitySummary =
              result.consolidatedEntities.take(3).join(", ");
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
    } catch (e, st) {
      _logger.warning('runEpisodeConsolidation failed', e, st);
      if (!mounted) return;
      setState(() => _lastError = 'Episode 凝结失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _runSagaWeaving() async {
    if (!DreamingOrchestratorServiceV3.isInitialized) {
      setState(() => _lastError = 'Dreaming service 未初始化');
      return;
    }
    _setBusy();
    try {
      final resources = await UserStorage.getAgentLLMResources(
        AgentDefinitions.recordOrganizerAgent,
        defaultClientKey: LLMConfig.defaultClientKey,
      );
      final result =
          await DreamingOrchestratorServiceV3.instance.runSagaWeaving(
        client: resources.client,
        modelConfig: resources.modelConfig,
        forceRun: true,
      );
      if (!mounted) return;
      setState(() {
        if (result.isEmpty) {
          _lastError =
              'Saga 编织未产生结果\n${result.skippedReasons.join("\n")}';
        } else {
          _lastSuccess = 'Saga 编织完成：新增 ${result.sagaIds.length} 条，更新 ${result.updatedSagaIds.length} 条';
        }
      });
    } catch (e, st) {
      _logger.warning('runSagaWeaving failed', e, st);
      if (!mounted) return;
      setState(() => _lastError = 'Saga 编织失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resetWatermark() async {
    final characterId = await latestChatCharacterId();
    if (characterId == null) {
      if (!mounted) return;
      setState(() => _lastError = '未找到最近的 characterId');
      return;
    }
    final db = AppDatabase.instance;
    final pendingExpr = db.personaChatMessages.id.count();
    final pendingRow = await (db.selectOnly(db.personaChatMessages)
          ..addColumns([pendingExpr])
          ..where(db.personaChatMessages.messageType.equals('chat')))
        .getSingle();
    final pending = pendingRow.read(pendingExpr) ?? 0;
    if (!mounted) return;
    final confirmed = await showLabConfirmDialog(
      context,
      title: '重置 Fragment 水位线？',
      content: '当前聊天累计 $pending 条 message。下一次 Fragment 抽取会从最早开始重新扫描 -- '
          '已抽取的 fragment 因内容哈希去重不会被重复保存；之前被旧模型拒接 '
          '(例如 NSFW 内容)而被跳过的批次会重新尝试。',
      confirmLabel: '重置',
      danger: true,
    );
    if (confirmed != true) return;

    _setBusy();
    try {
      final deleted = await DreamingOrchestratorServiceV3.instance
          .resetFragmentWatermark(characterId);
      if (!mounted) return;
      setState(() {
        _lastSuccess = deleted > 0
            ? '水位线已重置（共 $pending 条待扫描）'
            : '水位线本来就是空的，无需重置';
      });
    } catch (e, st) {
      _logger.warning('resetFragmentWatermark failed', e, st);
      if (!mounted) return;
      setState(() => _lastError = '重置失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _clearFragments() async {
    final confirmed = await showLabConfirmDialog(
      context,
      title: '清空所有 Dreaming fragments？',
      content: '这会删除所有 fragment、关联的 entity links 和水印标记。不能撤销。',
      confirmLabel: '清空',
      danger: true,
    );
    if (confirmed != true) return;
    _setBusy();
    try {
      final count =
          await DreamingOrchestratorServiceV3.instance.clearAllFragments();
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

  Future<void> _clearEpisodes() async {
    final confirmed = await showLabConfirmDialog(
      context,
      title: '清空所有 Dreaming episodes？',
      content: '这会删除所有生成的 episodes 及其 entity links。被这些 episode '
          '用过的 source fragments 会被重置回 active。',
      confirmLabel: '清空',
      danger: true,
    );
    if (confirmed != true) return;
    _setBusy();
    try {
      final count =
          await DreamingOrchestratorServiceV3.instance.clearAllEpisodes();
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

  Future<void> _clearSagas() async {
    final confirmed = await showLabConfirmDialog(
      context,
      title: '清空所有 Saga？',
      content: '这会删除所有 saga 及其历史快照。不能撤销。',
      confirmLabel: '清空',
      danger: true,
    );
    if (confirmed != true) return;
    _setBusy();
    try {
      await DreamingOrchestratorServiceV3.instance.clearAllSagas();
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
      appBar: AppBar(title: const Text('Dreaming 调度')),
      body: Column(
        children: [
          LabBusyLine(visible: _busy),
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
            child: ListView(
              padding: EdgeInsets.symmetric(vertical: t.space8),
              children: [
                const LabSectionLabel('批处理'),
                _ActionTile(
                  icon: Icons.bedtime_outlined,
                  title: 'run daily batch now',
                  subtitle: '完整跑一次每日 Dreaming（fragments + episodes）',
                  onTap: _busy ? null : _runDailyBatchNow,
                ),
                _ActionTile(
                  icon: Icons.nightlight_round,
                  title: 'fragments only',
                  subtitle: '只抽取碎片，不凝结 episode',
                  onTap: _busy ? null : _runFragmentsOnly,
                ),
                const LabSectionLabel('凝结'),
                _ActionTile(
                  icon: Icons.auto_awesome,
                  title: 'episodes only',
                  subtitle: '把已有碎片凝结为 episode',
                  onTap: _busy ? null : _runEpisodesOnly,
                ),
                _ActionTile(
                  icon: Icons.auto_stories_outlined,
                  title: 'saga weaving',
                  subtitle: '从 episodes 编织长期弧线',
                  onTap: _busy ? null : _runSagaWeaving,
                ),
                const LabSectionLabel('水位线'),
                _ActionTile(
                  icon: Icons.restart_alt,
                  title: 'reset watermark',
                  subtitle: '重置 fragment 抽取水位线',
                  warning: true,
                  onTap: _busy ? null : _resetWatermark,
                ),
                const LabSectionLabel('清理（不可撤销）'),
                _ActionTile(
                  icon: Icons.delete_outline,
                  title: 'clear fragments',
                  subtitle: '删除所有 fragment 与 entity links',
                  danger: true,
                  onTap: _busy ? null : _clearFragments,
                ),
                _ActionTile(
                  icon: Icons.delete_sweep_outlined,
                  title: 'clear episodes',
                  subtitle: '删除所有 episode，碎片重置回 active',
                  danger: true,
                  onTap: _busy ? null : _clearEpisodes,
                ),
                _ActionTile(
                  icon: Icons.delete_sweep,
                  title: 'clear sagas',
                  subtitle: '删除所有 saga 及其历史快照',
                  danger: true,
                  onTap: _busy ? null : _clearSagas,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.warning = false,
    this.danger = false,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool warning;
  final bool danger;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.springRainUi;
    final enabled = onTap != null;
    final color = danger
        ? t.error
        : warning
            ? t.warning
            : t.accent;
    return InkWell(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 64),
        padding: EdgeInsets.symmetric(
          horizontal: t.space16,
          vertical: t.space12,
        ),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: t.divider)),
        ),
        child: Row(
          children: [
            Icon(icon, size: t.iconMedium, color: color),
            SizedBox(width: t.space12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: danger ? t.error : t.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: TextStyle(color: t.textSecondary, fontSize: 13),
                  ),
                ],
              ),
            ),
            if (enabled)
              Icon(Icons.chevron_right_rounded, color: t.iconMuted, size: 20),
          ],
        ),
      ),
    );
  }
}
