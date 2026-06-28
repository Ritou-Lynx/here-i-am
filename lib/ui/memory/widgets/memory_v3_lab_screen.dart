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

import 'package:drift/drift.dart' as drift;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:memex/data/memory_v3/services/record_organizer_service.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/domain/models/agent_definitions.dart';
import 'package:memex/domain/models/llm_config.dart';
import 'package:memex/utils/logger.dart';
import 'package:memex/utils/user_storage.dart';

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

  @override
  void initState() {
    super.initState();
    unawaited(_loadRecent());
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

      final result = await RecordOrganizerServiceV3.instance.organizeAndPersist(
        client: resources.client,
        modelConfig: resources.modelConfig,
        source: RecordSource(
          sourceKind: 'dev_screen',
          rawInput: input,
        ),
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

  Future<void> _deleteCard(MemoryCard card) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除这张卡？'),
        content: Text(card.title),
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

  void _showCardDetail(MemoryCard card) async {
    final db = AppDatabase.instance;
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
    final entities = <MemoryEntity>[];
    for (final link in links) {
      final e = await (db.select(db.memoryEntities)
            ..where((t) => t.id.equals(link.entityId)))
          .getSingleOrNull();
      if (e != null) entities.add(e);
    }
    if (!mounted) return;
    final detailJson = const JsonEncoder.withIndent('  ').convert({
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
        'confidence': card.confidence,
        'status': card.status,
        'needsFollowUp': _decode(card.needsFollowUp),
        'createdAt':
            DateTime.fromMillisecondsSinceEpoch(card.createdAt).toIso8601String(),
        'updatedAt':
            DateTime.fromMillisecondsSinceEpoch(card.updatedAt).toIso8601String(),
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
            'entity': {
              'id': entities[i].id,
              'name': entities[i].name,
              'category': entities[i].category,
              'status': entities[i].status,
              'relationshipToUser': entities[i].relationshipToUser,
            },
          },
      ],
    });
    if (!mounted) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        expand: false,
        builder: (sheetCtx, scrollCtl) => SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(card.title,
                          style: const TextStyle(fontSize: 16),
                          overflow: TextOverflow.ellipsis),
                    ),
                    IconButton(
                      icon: const Icon(Icons.copy, size: 18),
                      tooltip: '复制 JSON',
                      onPressed: () => Clipboard.setData(
                          ClipboardData(text: detailJson)),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  controller: scrollCtl,
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: SelectableText(
                    detailJson,
                    style: const TextStyle(
                        fontFamily: 'monospace', fontSize: 12, height: 1.4),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Memory V3 Lab'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadRecent,
            tooltip: '刷新',
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
  });

  final MemoryCard card;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

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
                        child: Text(card.title,
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
