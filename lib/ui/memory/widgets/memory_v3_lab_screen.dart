/// Memory V3 Lab - hub page.
///
/// Entry from AboutIScreen ("高级记忆检查"). Slimmed from the old 2828-line
/// monolith into a grouped navigation surface that follows the 春雨昼眠
/// daylight tokens. Each former section now lives in its own sub-page under
/// `lab/`.
///
/// Still a backend test rig (no ViewModel), but no longer a wall of
/// ExpansionTiles: the hub shows a compact status strip + grouped rows,
/// and the 维护与导出 group keeps export / reindex as inline actions.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' as drift;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:memex/data/memory_v3/services/dreaming_orchestrator_service.dart';
import 'package:memex/data/memory_v3/services/dreaming_recall_log_service.dart';
import 'package:memex/data/memory_v3/services/record_organizer_service.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/ui/core/themes/spring_rain_ui_tokens.dart';
import 'package:memex/ui/memory/widgets/lab/cards_page.dart';
import 'package:memex/ui/memory/widgets/lab/dreaming_debug_page.dart';
import 'package:memex/ui/memory/widgets/lab/episodes_page.dart';
import 'package:memex/ui/memory/widgets/lab/fragments_page.dart';
import 'package:memex/ui/memory/widgets/lab/lab_shared.dart';
import 'package:memex/ui/memory/widgets/lab/query_log_page.dart';
import 'package:memex/ui/memory/widgets/lab/recall_log_page.dart';
import 'package:memex/ui/memory/widgets/lab/sagas_page.dart';
import 'package:memex/ui/memory/widgets/lab/skip_retry_page.dart';
import 'package:memex/utils/logger.dart';
import 'package:path_provider/path_provider.dart';

final _logger = getLogger('MemoryV3LabScreen');

class MemoryV3LabScreen extends StatefulWidget {
  const MemoryV3LabScreen({super.key});

  @override
  State<MemoryV3LabScreen> createState() => _MemoryV3LabScreenState();
}

class _MemoryV3LabScreenState extends State<MemoryV3LabScreen> {
  static const _backgroundAsset = 'assets/images/雨玻璃.jpg';

  bool _busy = false;
  String? _lastError;
  String? _lastSuccess;

  // Compact counts for the status strip.
  int _cardCount = 0;
  int _fragmentCount = 0;
  int _episodeCount = 0;
  int _sagaCount = 0;
  int _recallCount = 0;
  int _zeroQueryCount = 0;
  bool _loadingCounts = true;

  @override
  void initState() {
    super.initState();
    unawaited(_loadCounts());
  }

  Future<void> _loadCounts() async {
    var cards = 0;
    var fragments = 0;
    var episodes = 0;
    var sagas = 0;
    var recall = 0;
    var zeroQuery = 0;
    try {
      cards = RecordOrganizerServiceV3.isInitialized
          ? await tableCount('memory_cards')
          : 0;
      fragments =
          DreamingOrchestratorServiceV3.isInitialized
              ? await tableCount('memory_fragments')
              : 0;
      episodes = DreamingOrchestratorServiceV3.isInitialized
          ? await tableCount('memory_episodes')
          : 0;
      sagas = DreamingOrchestratorServiceV3.isInitialized
          ? await tableCount('memory_sagas')
          : 0;
      recall = (await DreamingRecallLogService.readAll()).length;
      zeroQuery = await DreamingRecallLogService.zeroResultCount();
    } catch (e, st) {
      _logger.warning('loadCounts failed', e, st);
    }
    if (!mounted) return;
    setState(() {
      _cardCount = cards;
      _fragmentCount = fragments;
      _episodeCount = episodes;
      _sagaCount = sagas;
      _recallCount = recall;
      _zeroQueryCount = zeroQuery;
      _loadingCounts = false;
    });
  }

  Future<T?> _push<T>(Widget page) {
    return Navigator.push<T>(
      context,
      MaterialPageRoute(builder: (_) => page),
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

  /// Dump all current memory_cards + dreaming fragments + episodes to a JSON
  /// file in the app's external dir. Returns the path on success.
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
          'createdAt':
              DateTime.fromMillisecondsSinceEpoch(card.createdAt).toIso8601String(),
          'updatedAt':
              DateTime.fromMillisecondsSinceEpoch(card.updatedAt).toIso8601String(),
        },
        'source': source == null
            ? null
            : {
                'rawInput': source.rawInput,
                'recordedAt': DateTime.fromMillisecondsSinceEpoch(source.recordedAt)
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

  Future<void> _onExport() async {
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

  Future<void> _onReindex() async {
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
    final t = context.springRainUi;
    final serviceReady = RecordOrganizerServiceV3.isInitialized;
    return SpringRainUiScope(
      child: Builder(
        builder: (context) {
          return AnnotatedRegion<SystemUiOverlayStyle>(
            value: SystemUiOverlayStyle.light.copyWith(
              statusBarColor: Colors.transparent,
              systemNavigationBarColor: t.canvas,
              systemNavigationBarIconBrightness: Brightness.dark,
            ),
            child: Scaffold(
              backgroundColor: t.canvas,
              body: Stack(
                fit: StackFit.expand,
                children: [
                  Align(
                    alignment: Alignment.topCenter,
                    child: Image.asset(
                      _backgroundAsset,
                      width: double.infinity,
                      height: 170,
                      fit: BoxFit.cover,
                      alignment: const Alignment(0, -0.25),
                    ),
                  ),
                  SafeArea(
                    bottom: false,
                    child: Column(
                      children: [
                        SizedBox(
                          height: 58,
                          child: Row(
                            children: [
                              SizedBox(width: t.space8),
                              _HeaderCircleButton(
                                icon: Icons.arrow_back_ios_new_rounded,
                                tooltip: MaterialLocalizations.of(context)
                                    .backButtonTooltip,
                                onTap: () => Navigator.maybePop(context),
                              ),
                              Expanded(
                                child: Text(
                                  '高级记忆检查',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: t.textOnAccent,
                                    fontSize: 17,
                                    fontWeight: FontWeight.w600,
                                    shadows: const [
                                      Shadow(
                                          color: Colors.black45,
                                          blurRadius: 8),
                                    ],
                                  ),
                                ),
                              ),
                              SizedBox(
                                width: 38,
                                child: IconButton(
                                  icon: const Icon(Icons.refresh, size: 18),
                                  color: t.textOnAccent,
                                  onPressed: _loadCounts,
                                  tooltip: '刷新计数',
                                ),
                              ),
                              const SizedBox(width: 6),
                            ],
                          ),
                        ),
                        Expanded(
                          child: Container(
                            width: double.infinity,
                            decoration: BoxDecoration(
                              color: t.canvas,
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(28),
                              ),
                            ),
                            child: ListView(
                              padding: EdgeInsets.fromLTRB(
                                t.space20,
                                t.space16,
                                t.space20,
                                t.space32,
                              ),
                              children: [
                                _StatusStrip(
                                  serviceReady: serviceReady,
                                  cardCount: _cardCount,
                                  fragmentCount: _fragmentCount,
                                  episodeCount: _episodeCount,
                                  sagaCount: _sagaCount,
                                  recallCount: _recallCount,
                                  loading: _loadingCounts,
                                ),
                                SizedBox(height: t.space16),
                                const LabSectionLabel('数据浏览'),
                                LabNavRow(
                                  icon: Icons.style_outlined,
                                  title: '记忆卡片',
                                  subtitle: '$_cardCount 张 · 真实记录入口写入',
                                  status: '$_cardCount',
                                  onTap: () =>
                                      _push(const LabCardsPage()),
                                ),
                                LabNavRow(
                                  icon: Icons.auto_awesome_outlined,
                                  title: '梦境碎片',
                                  subtitle: '$_fragmentCount 条 · Dreaming 抽取',
                                  status: '$_fragmentCount',
                                  onTap: () =>
                                      _push(const LabFragmentsPage()),
                                ),
                                LabNavRow(
                                  icon: Icons.auto_awesome,
                                  title: '情节片段',
                                  subtitle: '$_episodeCount 条 · 碎片凝结',
                                  status: '$_episodeCount',
                                  onTap: () =>
                                      _push(const LabEpisodesPage()),
                                ),
                                LabNavRow(
                                  icon: Icons.auto_stories_outlined,
                                  title: '长期弧线',
                                  subtitle: '$_sagaCount 条 · Saga 编织',
                                  status: '$_sagaCount',
                                  onTap: () =>
                                      _push(const LabSagasPage()),
                                ),
                                const LabSectionLabel('运行日志'),
                                LabNavRow(
                                  icon: Icons.query_stats,
                                  title: '查询日志',
                                  subtitle: 'memory_cards 检索与命中策略',
                                  warning: _zeroQueryCount > 0,
                                  status: _zeroQueryCount > 0
                                      ? '零结果 $_zeroQueryCount'
                                      : null,
                                  onTap: () =>
                                      _push(const LabQueryLogPage()),
                                ),
                                LabNavRow(
                                  icon: Icons.auto_awesome_motion_outlined,
                                  title: '召回日志',
                                  subtitle: 'Dreaming context 注入记录',
                                  status: '$_recallCount',
                                  onTap: () =>
                                      _push(const LabRecallLogPage()),
                                ),
                                LabNavRow(
                                  icon: Icons.skip_next_outlined,
                                  title: '跳过与补跑',
                                  subtitle: '被跳过的提取区间与水位线',
                                  onTap: () =>
                                      _push(const LabSkipRetryPage()),
                                ),
                                const LabSectionLabel('Dreaming 调度'),
                                LabNavRow(
                                  icon: Icons.construction_outlined,
                                  title: '批处理与重置',
                                  subtitle: '手动跑 Dreaming、凝结、Saga、清空',
                                  diagnostic: true,
                                  onTap: () =>
                                      _push(const LabDreamingDebugPage()),
                                ),
                                const LabSectionLabel('维护与导出'),
                                LabNavRow(
                                  icon: Icons.file_download_outlined,
                                  title: '导出全部数据',
                                  subtitle: 'cards + fragments + episodes -> JSON',
                                  diagnostic: true,
                                  onTap: _busy ? null : _onExport,
                                ),
                                LabNavRow(
                                  icon: Icons.search,
                                  title: '重建搜索索引',
                                  subtitle: '重建 memory_cards FTS 索引',
                                  diagnostic: true,
                                  onTap: _busy ? null : _onReindex,
                                ),
                                if (_lastError != null) ...[
                                  SizedBox(height: t.space16),
                                  LabStatusBanner(
                                      message: _lastError!,
                                      kind: LabStatusKind.error),
                                ],
                                if (_lastSuccess != null) ...[
                                  SizedBox(height: t.space16),
                                  LabStatusBanner(
                                      message: _lastSuccess!,
                                      kind: LabStatusKind.success),
                                ],
                                SizedBox(height: t.space16),
                                LabBusyLine(visible: _busy),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _StatusStrip extends StatelessWidget {
  const _StatusStrip({
    required this.serviceReady,
    required this.cardCount,
    required this.fragmentCount,
    required this.episodeCount,
    required this.sagaCount,
    required this.recallCount,
    required this.loading,
  });

  final bool serviceReady;
  final int cardCount;
  final int fragmentCount;
  final int episodeCount;
  final int sagaCount;
  final int recallCount;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final t = context.springRainUi;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: t.space16,
        vertical: t.space12,
      ),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(t.radius18),
        border: Border.all(color: t.divider),
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: serviceReady ? t.success : t.error,
              shape: BoxShape.circle,
            ),
          ),
          SizedBox(width: t.space8),
          Text(
            loading
                ? '加载中…'
                : (serviceReady ? 'service ready' : 'service 未初始化'),
            style: TextStyle(
              color: t.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          _CountChip(label: 'cards', value: cardCount),
          _CountChip(label: 'frag', value: fragmentCount),
          _CountChip(label: 'ep', value: episodeCount),
          _CountChip(label: 'saga', value: sagaCount),
          _CountChip(label: 'recall', value: recallCount),
        ],
      ),
    );
  }
}

class _CountChip extends StatelessWidget {
  const _CountChip({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    final t = context.springRainUi;
    return Padding(
      padding: EdgeInsets.only(left: t.space8),
      child: Text(
        '$label $value',
        style: TextStyle(color: t.textTertiary, fontSize: 11),
      ),
    );
  }
}

class _HeaderCircleButton extends StatelessWidget {
  const _HeaderCircleButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: const Color(0x473A5146),
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: 38,
            height: 38,
            child: Icon(icon, size: 18, color: const Color(0xFFF8FBF8)),
          ),
        ),
      ),
    );
  }
}
