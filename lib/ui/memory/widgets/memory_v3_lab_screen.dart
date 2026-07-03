/// V3 Lab — dev / debug screen for the Memory V3 backend.
///
/// Lets you exercise [RecordOrganizerServiceV3.organizeAndPersist] end-to-end
/// against the user-configured "Record Organizer" model, list the newest
/// memory_cards, inspect each card's full V3 fields, and delete cards.
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
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();
  bool _busy = false;
  String? _lastError;
  String? _lastSuccess;
  List<MemoryCard> _recent = const [];
  List<QueryLogEntry> _queryLogEntries = const [];
  int _zeroResultCount = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_loadRecent());
    unawaited(_loadQueryLog());
  }

  @override
  void dispose() {
    _inputController.dispose();
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

  Future<void> _loadQueryLog() async {
    final entries = await QueryLogService.readAll();
    final zeros = await QueryLogService.zeroResultCount();
    if (!mounted) return;
    setState(() {
      _queryLogEntries = entries;
      _zeroResultCount = zeros;
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

  Future<void> _organizeAndSave() async {
    final input = _inputController.text.trim();
    if (input.isEmpty) {
      setState(() => _lastError = '空输入');
      return;
    }
    if (!RecordOrganizerServiceV3.isInitialized) {
      setState(() => _lastError = 'V3 service 未初始化 (memex_router 未跑过 init?)');
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

      // Pass recent cards as context so the agent can suggest merges
      // (V3 § 9.6). We keep the summary short to control tokens.
      final summaries = await _recentCardSummaries(limit: 20);
      final entityNames = await _recentActiveEntityNames(limit: 20);

      final result = await RecordOrganizerServiceV3.instance.organizeAndPersist(
        client: resources.client,
        modelConfig: resources.modelConfig,
        source: RecordSource(
          sourceKind: 'dev_screen',
          rawInput: input,
        ),
        relevantExistingCardSummaries: summaries,
        recentEntityNames: entityNames,
      );

      _inputController.clear();
      await _loadRecent();
      if (!mounted) return;
      setState(() {
        _lastSuccess = result.isEmpty
            ? '已调用但没有产生卡片'
            : '已写入 ${result.cardIds.length} 张卡，${result.entityIds.length} 个 entity';
      });
    } catch (e, stack) {
      _logger.warning('organizeAndPersist failed', e, stack);
      if (!mounted) return;
      setState(() => _lastError = '失败：$e');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  /// Compact one-line summaries of the most recent N cards, for feeding to
  /// the Record Organizer as merge-suggestion context.
  Future<List<String>> _recentCardSummaries({required int limit}) async {
    final db = AppDatabase.instance;
    final rows = await (db.select(db.memoryCards)
          ..orderBy([(t) => drift.OrderingTerm.desc(t.updatedAt)])
          ..limit(limit))
        .get();
    return rows
        .map((c) =>
            '[${c.id.substring(0, 8)}] ${c.type} · ${c.dropletLabel} · ${_truncate(c.retrievalText, 60)}')
        .toList(growable: false);
  }

  /// Names of recently mentioned active entities, for the agent to prefer
  /// reusing names instead of inventing new ones.
  Future<List<String>> _recentActiveEntityNames({required int limit}) async {
    final db = AppDatabase.instance;
    final rows = await (db.select(db.memoryEntities)
          ..where((t) => t.status.equals('active'))
          ..orderBy([
            (t) => drift.OrderingTerm.desc(t.lastMentionedAt),
            (t) => drift.OrderingTerm.desc(t.firstMentionedAt),
          ])
          ..limit(limit))
        .get();
    return rows.map((e) => e.name).toList(growable: false);
  }

  String _truncate(String text, int max) =>
      text.length <= max ? text : '${text.substring(0, max)}…';

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

  /// Dump all current memory_cards (plus source / structured / entity links)
  /// to a JSON file in the app's external dir. Returns the absolute path
  /// on success.
  ///
  /// Path layout on Android (no permissions needed):
  ///   /sdcard/Android/data/com.memexlab.hereiam.v3/files/v3_dump.json
  /// Pull with:
  ///   adb pull <that path> ./v3_dump.json
  Future<String?> _dumpAllToFile() async {
    final db = AppDatabase.instance;
    final cards = await (db.select(db.memoryCards)
          ..orderBy([(t) => drift.OrderingTerm.desc(t.updatedAt)]))
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
                'recordedAt': DateTime.fromMillisecondsSinceEpoch(
                        source.recordedAt)
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
      'count': dump.length,
      'cards': dump,
    };

    try {
      final dir = await getExternalStorageDirectory();
      if (dir == null) return null;
      final file = File('${dir.path}/v3_dump.json');
      await file.writeAsString(
          const JsonEncoder.withIndent('  ').convert(payload),
          flush: true);
      return file.path;
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
    final path = await _dumpAllToFile();
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (path == null) {
        _lastError = '导出失败（看 logcat）';
      } else {
        _lastSuccess = '已导出 ${_recent.length} 张到\n$path';
        Clipboard.setData(ClipboardData(text: path));
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
            onPressed: _loadRecent,
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
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _inputController,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: '输入要记录的内容（中文）',
                    hintText: '例：今天午饭跟小红吃了麻辣烫花了 78',
                  ),
                ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: _busy ? null : _organizeAndSave,
                  icon: _busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save),
                  label: Text(_busy ? '整理中…' : 'organize + persist'),
                ),
                if (_lastError != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(_lastError!,
                        style: const TextStyle(color: Colors.red)),
                  ),
                if (_lastSuccess != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(_lastSuccess!,
                        style: const TextStyle(color: Colors.green)),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              children: [
                Text('最近 ${_recent.length} 张 memory_cards',
                    style: Theme.of(context).textTheme.titleSmall),
                const Spacer(),
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
            child: _recent.isEmpty
                ? const Center(child: Text('（暂无记录）'))
                : ListView.builder(
                    controller: _scrollController,
                    itemCount: _recent.length,
                    itemBuilder: (ctx, i) => _CardListTile(
                      card: _recent[i],
                      onTap: () => _showCardDetail(_recent[i]),
                      onLongPress: () => _deleteCard(_recent[i]),
                      onPreview: () => _previewCard(_recent[i]),
                    ),
                  ),
          ),
        ],
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
                      style: const TextStyle(fontSize: 12, color: Colors.black54)),
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

/// Bottom sheet that displays the Memory V3 query log for Phase 3 Lite+
/// bad-case accumulation.
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
                Text('查询日志',
                    style: Theme.of(context).textTheme.titleMedium),
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
                    child: Text('暂无查询记录',
                        style: TextStyle(color: Colors.black45)))
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
        '$timeStr · $_strategyLabel',
        style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
      ),
    );
  }
}
