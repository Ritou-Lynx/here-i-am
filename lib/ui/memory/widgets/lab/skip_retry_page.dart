/// Memory V3 Lab - skipped extraction intervals & retry page.
///
/// Promoted from a top-level ExpansionTile into its own page so the
/// "跳过补提取" entry in AboutIScreen can deep-link here directly.
library;

import 'dart:async';

import 'package:drift/drift.dart' as drift;
import 'package:flutter/material.dart';
import 'package:memex/data/memory_v3/services/dreaming_orchestrator_service.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/domain/models/agent_definitions.dart';
import 'package:memex/domain/models/llm_config.dart';
import 'package:memex/ui/core/themes/spring_rain_ui_tokens.dart';
import 'package:memex/ui/memory/widgets/lab/lab_shared.dart';
import 'package:memex/utils/logger.dart';
import 'package:memex/utils/user_storage.dart';

final _logger = getLogger('LabSkipRetryPage');

class LabSkipRetryPage extends StatefulWidget {
  const LabSkipRetryPage({super.key});

  @override
  State<LabSkipRetryPage> createState() => _LabSkipRetryPageState();
}

class _LabSkipRetryPageState extends State<LabSkipRetryPage> {
  List<DreamingSkipRecord> _records = const [];
  int _pendingMessageCount = 0;
  int _watermark = 0;
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
      setState(() => _loading = false);
      return;
    }
    final characterId = await latestChatCharacterId();
    if (characterId == null) {
      if (!mounted) return;
      setState(() => _loading = false);
      return;
    }
    List<DreamingSkipRecord> records = const [];
    var pending = 0;
    var watermark = 0;
    try {
      records = await DreamingOrchestratorServiceV3.instance
          .getSkipRecords(characterId);
      watermark = await dreamingWatermark(characterId);
      final db = AppDatabase.instance;
      final pendingExpr = db.personaChatMessages.id.count();
      final pendingRow = await (db.selectOnly(db.personaChatMessages)
            ..addColumns([pendingExpr])
            ..where(db.personaChatMessages.characterId.equals(characterId) &
                db.personaChatMessages.id.isBiggerThanValue(watermark) &
                db.personaChatMessages.messageType.equals('chat') &
                db.personaChatMessages.content.isNotValue('')))
          .getSingle();
      pending = pendingRow.read(pendingExpr) ?? 0;
    } catch (e, st) {
      _logger.warning('_loadSkipRecords failed', e, st);
    }
    if (!mounted) return;
    setState(() {
      _records = records;
      _pendingMessageCount = pending;
      _watermark = watermark;
      _loading = false;
    });
  }

  Future<void> _retryOne(DreamingSkipRecord record) async {
    if (_busy || !DreamingOrchestratorServiceV3.isInitialized) return;
    final characterId = await latestChatCharacterId();
    if (characterId == null) {
      if (!mounted) return;
      setState(() => _lastError = '未找到最近的 characterId');
      return;
    }
    setState(() {
      _busy = true;
      _lastError = null;
      _lastSuccess = null;
    });
    try {
      final resources = await UserStorage.getAgentLLMResources(
        AgentDefinitions.recordOrganizerAgent,
        defaultClientKey: LLMConfig.defaultClientKey,
      );
      final result = await DreamingOrchestratorServiceV3.instance.retrySkippedRange(
        characterId: characterId,
        client: resources.client,
        modelConfig: resources.modelConfig,
        fromId: record.fromId,
        toId: record.toId,
      );
      await _load();
      if (!mounted) return;
      setState(() => _lastSuccess = '补跑 #${record.fromId}–#${record.toId}：${result.message}');
    } catch (e, st) {
      _logger.warning('retrySkippedRange failed', e, st);
      if (!mounted) return;
      setState(() => _lastError = '补跑失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _retryAll() async {
    if (_busy || !DreamingOrchestratorServiceV3.isInitialized) return;
    final characterId = await latestChatCharacterId();
    if (characterId == null) {
      if (!mounted) return;
      setState(() => _lastError = '未找到最近的 characterId');
      return;
    }
    setState(() {
      _busy = true;
      _lastError = null;
      _lastSuccess = null;
    });
    try {
      final resources = await UserStorage.getAgentLLMResources(
        AgentDefinitions.recordOrganizerAgent,
        defaultClientKey: LLMConfig.defaultClientKey,
      );
      final results = await DreamingOrchestratorServiceV3.instance.retryAllSkipped(
        characterId: characterId,
        client: resources.client,
        modelConfig: resources.modelConfig,
      );
      await _load();
      if (!mounted) return;
      final ok = results.where((r) => r.fragmentCount > 0).length;
      setState(() => _lastSuccess = '补跑 ${results.length} 个区间完成，其中 $ok 个产生了新碎片');
    } catch (e, st) {
      _logger.warning('retryAllSkipped failed', e, st);
      if (!mounted) return;
      setState(() => _lastError = '补跑全部失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.springRainUi;
    final errorCount =
        _records.where((r) => r.reason == 'error').length;
    final emptyCount =
        _records.where((r) => r.reason == 'empty').length;
    return Scaffold(
      appBar: AppBar(
        title: const Text('跳过与补跑'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _load,
            tooltip: '刷新',
          ),
          IconButton(
            icon: const Icon(Icons.play_arrow),
            onPressed: _busy || _records.isEmpty ? null : _retryAll,
            tooltip: '补跑全部',
          ),
        ],
      ),
      body: Column(
        children: [
          LabBusyLine(visible: _busy || _loading),
          Padding(
            padding: EdgeInsets.fromLTRB(
              t.space16,
              t.space12,
              t.space16,
              t.space4,
            ),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '水位线 #$_watermark · 待扫描 $_pendingMessageCount 条 chat',
                style: TextStyle(color: t.textSecondary, fontSize: 12),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: t.space16),
            child: Row(
              children: [
                if (errorCount > 0)
                  Padding(
                    padding: EdgeInsets.only(right: t.space8),
                    child: Chip(
                      label: Text('失败 $errorCount'),
                      backgroundColor: t.errorSoft,
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                if (emptyCount > 0)
                  Chip(
                    label: Text('零片段 $emptyCount'),
                    backgroundColor: t.surfaceMuted,
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
              ],
            ),
          ),
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
              child: _records.isEmpty && !_loading
                  ? ListView(
                      children: const [
                        LabEmptyState(message: '无跳过记录'),
                      ],
                    )
                  : ListView.separated(
                      itemCount: _records.length,
                      separatorBuilder: (_, __) =>
                          Divider(height: 1, indent: t.space16, color: t.divider),
                      itemBuilder: (ctx, i) {
                        final r = _records[i];
                        return ListTile(
                          leading: CircleAvatar(
                            radius: 10,
                            backgroundColor:
                                r.reason == 'error' ? t.error : t.iconMuted,
                          ),
                          title: Text(
                            '消息 #${r.fromId}–#${r.toId}',
                            style: TextStyle(
                                color: t.textPrimary, fontSize: 13),
                          ),
                          subtitle: Text(
                            '${r.reason == 'error' ? '提取失败' : '零片段'}'
                            ' · ${DateTime.fromMillisecondsSinceEpoch(r.at).toIso8601String()}'
                            '${r.error != null ? '\n${r.error}' : ''}',
                            style:
                                TextStyle(fontSize: 11, color: t.textTertiary),
                          ),
                          trailing: TextButton(
                            onPressed: _busy ? null : () => _retryOne(r),
                            child: const Text('补跑'),
                          ),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
