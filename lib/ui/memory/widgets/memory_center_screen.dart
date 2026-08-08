/// Memory Center - unified entry for browsing, organizing and diagnosing
/// the Memory V3 system.
///
/// Replaces the old `MemoryV3LabScreen` hub and absorbs the memory-management
/// slice that used to live on `AboutIScreen` (manual organize, skip badge,
/// recent browse entries). Sub-pages under `lab/` are reused unchanged.
///
/// Three groups, ordered by audience:
///  1. 「我的记忆」- read/browse entries for cards + fragments + episodes +
///     sagas, named with user-facing labels.
///  2. 「整理」- the one-tap "organize now" action plus the skip/retry entry
///     (badge surfaces failures without leaking pipeline internals onto the
///     profile page).
///  3. 「高级」- diagnostic tools (step organize, logs, export, reindex),
///     kept behind a single clearly-labeled section instead of a separate
///     debug-only route.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' as drift;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:memex/data/memory_v3/services/dreaming_orchestrator_service.dart';
import 'package:memex/data/memory_v3/services/dreaming_recall_log_service.dart';
import 'package:memex/data/memory_v3/services/dreaming_scheduler_service.dart';
import 'package:memex/data/memory_v3/services/record_organizer_service.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/ui/core/themes/spring_rain_ui_tokens.dart';
import 'package:memex/ui/memory/widgets/lab/lab_shared.dart';
import 'package:memex/routing/routes.dart';
import 'package:memex/utils/logger.dart';
import 'package:memex/utils/toast_helper.dart';
import 'package:path_provider/path_provider.dart';

final _logger = getLogger('MemoryCenterScreen');

class MemoryCenterScreen extends StatefulWidget {
  const MemoryCenterScreen({super.key});

  @override
  State<MemoryCenterScreen> createState() => _MemoryCenterScreenState();
}

class _MemoryCenterScreenState extends State<MemoryCenterScreen> {
  static const _backgroundAsset = 'assets/images/雨玻璃.jpg';

  bool _busy = false;
  String? _lastError;
  String? _lastSuccess;

  // Compact counts for the status strip + row subtitles.
  int _cardCount = 0;
  int _fragmentCount = 0;
  int _episodeCount = 0;
  int _sagaCount = 0;
  int _recallCount = 0;
  int _zeroQueryCount = 0;
  int _skipErrorCount = 0;
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
    var skipError = 0;
    try {
      cards = RecordOrganizerServiceV3.isInitialized
          ? await tableCount('memory_cards')
          : 0;
      if (DreamingOrchestratorServiceV3.isInitialized) {
        fragments = await tableCount('memory_fragments');
        episodes = await tableCount('memory_episodes');
        sagas = await tableCount('memory_sagas');
        final characterId = await latestChatCharacterId();
        if (characterId != null) {
          final records = await DreamingOrchestratorServiceV3.instance
              .getSkipRecords(characterId);
          skipError = records.where((r) => r.reason == 'error').length;
        }
      }
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
      _skipErrorCount = skipError;
      _loadingCounts = false;
    });
  }

  Future<T?> _push<T>(String route) {
    return context.push<T>(route);
  }

  // ---- Organize now ------------------------------------------------------

  Future<void> _organizeNow() async {
    if (_busy || !DreamingOrchestratorServiceV3.isInitialized) {
      if (!DreamingOrchestratorServiceV3.isInitialized && mounted) {
        ToastHelper.showInfo(context, '记忆整理服务尚未初始化');
      }
      return;
    }
    setState(() {
      _busy = true;
      _lastError = null;
      _lastSuccess = null;
    });
    try {
      final characterId = await latestChatCharacterId();
      if (characterId == null) {
        throw StateError('还没有可以整理的聊天');
      }
      await DreamingSchedulerService.runDailyDreamingFromBackground(
        db: AppDatabase.instance,
        characterId: characterId,
        forceRun: true,
      );
      if (!mounted) return;
      setState(() => _lastSuccess = '整理已完成');
      await _loadCounts();
    } catch (e, st) {
      _logger.warning('organizeNow failed', e, st);
      if (!mounted) return;
      setState(() => _lastError = '整理没有完成：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ---- Export ------------------------------------------------------------

  Object? _decode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      return jsonDecode(raw);
    } catch (_) {
      return raw;
    }
  }

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
                                  '记忆中心',
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
                                const LabSectionLabel('我的记忆'),
                                LabNavRow(
                                  icon: Icons.style_outlined,
                                  title: '记忆卡片',
                                  subtitle: '$_cardCount 张 · 主动记录写入',
                                  status: '$_cardCount',
                                  onTap: () => _push(AppRoutes.memoryCenterCards),
                                ),
                                LabNavRow(
                                  icon: Icons.scatter_plot_outlined,
                                  title: '记忆碎片',
                                  subtitle: '$_fragmentCount 条 · 从聊天提取',
                                  status: '$_fragmentCount',
                                  onTap: () => _push(AppRoutes.memoryCenterFragments),
                                ),
                                LabNavRow(
                                  icon: Icons.auto_awesome_outlined,
                                  title: '我们的经历',
                                  subtitle: '$_episodeCount 条 · 碎片凝结',
                                  status: '$_episodeCount',
                                  onTap: () => _push(AppRoutes.memoryCenterEpisodes),
                                ),
                                LabNavRow(
                                  icon: Icons.timeline_rounded,
                                  title: '长期记忆',
                                  subtitle: '$_sagaCount 条 · 长期弧线',
                                  status: '$_sagaCount',
                                  onTap: () => _push(AppRoutes.memoryCenterSagas),
                                ),
                                const LabSectionLabel('整理'),
                                LabNavRow(
                                  icon: Icons.sync_rounded,
                                  title: _busy ? '正在整理…' : '手动整理一次',
                                  subtitle: '立即跑一次完整 Dreaming',
                                  onTap: _busy ? null : _organizeNow,
                                ),
                                LabNavRow(
                                  icon: Icons.skip_next_outlined,
                                  title: '被跳过的提取',
                                  subtitle: _skipErrorCount > 0
                                      ? '有 $_skipErrorCount 个失败区间待补跑'
                                      : '查看被跳过的提取区间',
                                  warning: _skipErrorCount > 0,
                                  status: _skipErrorCount > 0
                                      ? '失败 $_skipErrorCount'
                                      : null,
                                  onTap: () async {
                                    await _push(AppRoutes.memoryCenterSkipRetry);
                                    await _loadCounts();
                                  },
                                ),
                                const LabSectionLabel('高级'),
                                LabNavRow(
                                  icon: Icons.construction_outlined,
                                  title: '分步整理与重置',
                                  subtitle: '单独跑碎片/经历/弧线、重置水位线、清空',
                                  diagnostic: true,
                                  onTap: () =>
                                      _push(AppRoutes.memoryCenterDreaming),
                                ),
                                LabNavRow(
                                  icon: Icons.query_stats,
                                  title: '查询日志',
                                  subtitle: '记忆卡片检索与命中策略',
                                  warning: _zeroQueryCount > 0,
                                  status: _zeroQueryCount > 0
                                      ? '零结果 $_zeroQueryCount'
                                      : null,
                                  diagnostic: true,
                                  onTap: () => _push(AppRoutes.memoryCenterQueryLog),
                                ),
                                LabNavRow(
                                  icon: Icons.auto_awesome_motion_outlined,
                                  title: '召回日志',
                                  subtitle: 'Dreaming context 注入记录',
                                  status: '$_recallCount',
                                  diagnostic: true,
                                  onTap: () => _push(AppRoutes.memoryCenterRecallLog),
                                ),
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
                                  subtitle: '重建记忆卡片 FTS 索引',
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
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
              Flexible(
                child: Text(
                  loading
                      ? '加载中…'
                      : (serviceReady ? 'service ready' : 'service 未初始化'),
                  style: TextStyle(
                    color: t.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          SizedBox(height: t.space8),
          Wrap(
            spacing: t.space12,
            runSpacing: t.space4,
            children: [
              _CountChip(label: 'cards', value: cardCount),
              _CountChip(label: 'frag', value: fragmentCount),
              _CountChip(label: 'ep', value: episodeCount),
              _CountChip(label: 'saga', value: sagaCount),
              _CountChip(label: 'recall', value: recallCount),
            ],
          ),
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
