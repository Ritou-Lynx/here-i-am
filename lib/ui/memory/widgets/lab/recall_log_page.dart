/// Memory V3 Lab - Dreaming recall log page (promoted from bottom sheet).
///
/// Shows dreaming_context injection records with episode/fragment hits and
/// coverage stats. Clear and refresh from the AppBar.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:memex/data/memory_v3/services/dreaming_recall_log_service.dart';
import 'package:memex/ui/core/themes/spring_rain_ui_tokens.dart';
import 'package:memex/ui/memory/widgets/lab/lab_shared.dart';

class LabRecallLogPage extends StatefulWidget {
  const LabRecallLogPage({super.key});

  @override
  State<LabRecallLogPage> createState() => _LabRecallLogPageState();
}

class _LabRecallLogPageState extends State<LabRecallLogPage> {
  List<DreamingRecallLogEntry> _entries = const [];
  int _zeroCount = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final entries = await DreamingRecallLogService.readAll();
    final zeros = await DreamingRecallLogService.zeroResultCount();
    if (!mounted) return;
    setState(() {
      _entries = entries;
      _zeroCount = zeros;
      _loading = false;
    });
  }

  Future<void> _clear() async {
    final confirmed = await showLabConfirmDialog(
      context,
      title: '清空 Dreaming 召回日志？',
      content: '这会删除所有 Dreaming context 注入记录。',
      confirmLabel: '清空',
      danger: true,
    );
    if (!confirmed) return;
    await DreamingRecallLogService.clear();
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.springRainUi;
    final coverage = DreamingRecallCoverage.fromEntries(_entries);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dreaming 召回日志'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _load,
            tooltip: '刷新',
          ),
          IconButton(
            icon: Icon(Icons.delete_outline, color: t.error),
            onPressed: _entries.isEmpty ? null : _clear,
            tooltip: '清空日志',
          ),
        ],
      ),
      body: Column(
        children: [
          LabBusyLine(visible: _loading),
          if (coverage.total > 0)
            Padding(
              padding: EdgeInsets.fromLTRB(
                t.space16,
                t.space12,
                t.space16,
                t.space8,
              ),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '近 ${coverage.total} 轮：Episode 命中 ${coverage.episodeMatched} · '
                  '仅 Fragment ${coverage.fragmentOnly} · 零结果 $_zeroCount',
                  style: TextStyle(
                    fontSize: 11,
                    color: _zeroCount > 0 ? t.warning : t.textTertiary,
                  ),
                ),
              ),
            ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: _entries.isEmpty && !_loading
                  ? ListView(
                      children: const [
                        LabEmptyState(message: '暂无 Dreaming 召回记录'),
                      ],
                    )
                  : ListView.separated(
                      itemCount: _entries.length,
                      separatorBuilder: (_, __) =>
                          Divider(height: 1, indent: t.space16, color: t.divider),
                      itemBuilder: (ctx, i) =>
                          _RecallLogTile(entry: _entries[i]),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RecallLogTile extends StatelessWidget {
  const _RecallLogTile({required this.entry});

  final DreamingRecallLogEntry entry;

  @override
  Widget build(BuildContext context) {
    final t = context.springRainUi;
    final isZero = entry.isZeroResult;
    final time = entry.dateTime;
    final timeStr =
        '${time.month}/${time.day} ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    final color = isZero ? t.error : t.info;

    return ExpansionTile(
      leading: CircleAvatar(
        radius: 16,
        backgroundColor: isZero ? t.errorSoft : t.infoSoft,
        child: Text(
          '${entry.episodeCount}/${entry.fragmentCount}',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ),
      title: Text(
        entry.query.trim().isEmpty ? '（空 query）' : entry.query,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: t.textPrimary, fontSize: 14),
      ),
      subtitle: Text(
        '$timeStr · episode ${entry.episodeCount} · fragment ${entry.fragmentCount} · ${entry.actualSummary}',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 11, color: t.textTertiary),
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
              style: TextStyle(fontSize: 11, height: 1.35, color: t.textSecondary),
            ),
          ],
        ),
      ],
    );
  }
}

class _RecallSection extends StatelessWidget {
  const _RecallSection({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final t = context.springRainUi;
    return Padding(
      padding: EdgeInsets.fromLTRB(56, t.space4, t.space16, t.space12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: t.textSecondary,
            ),
          ),
          SizedBox(height: t.space4),
          ...children,
        ],
      ),
    );
  }
}

class _RecallHitText extends StatelessWidget {
  const _RecallHitText({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final t = context.springRainUi;
    return Padding(
      padding: EdgeInsets.only(bottom: t.space8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(fontSize: 10, color: t.textTertiary)),
          const SizedBox(height: 2),
          SelectableText(body, style: TextStyle(fontSize: 12, color: t.textPrimary)),
        ],
      ),
    );
  }
}
