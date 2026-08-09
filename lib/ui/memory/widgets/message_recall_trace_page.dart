/// User-facing recall trace for one companion turn.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:memex/data/memory_v3/services/memory_recall_trace_service.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/ui/core/themes/spring_rain_ui_tokens.dart';

class MessageRecallTracePage extends StatefulWidget {
  const MessageRecallTracePage({
    super.key,
    required this.chatMessageId,
    required this.messagePreview,
    this.traceService,
  });

  final int chatMessageId;
  final String messagePreview;
  final MemoryRecallTraceService? traceService;

  @override
  State<MessageRecallTracePage> createState() => _MessageRecallTracePageState();
}

class _MessageRecallTracePageState extends State<MessageRecallTracePage> {
  MemoryRecallTrace? _trace;
  Object? _error;

  MemoryRecallTraceService get _service =>
      widget.traceService ?? MemoryRecallTraceService(AppDatabase.instance);

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final trace = await _service.loadTrace(widget.chatMessageId);
      if (!mounted) return;
      setState(() => _trace = trace);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error);
    }
  }

  Future<void> _setFeedback(
    MemoryRecallTraceItem item,
    MemoryRecallFeedback feedback,
  ) async {
    final next = item.feedback == feedback ? null : feedback;
    await _service.setFeedback(
      chatMessageId: widget.chatMessageId,
      targetTable: item.targetTable,
      targetId: item.targetId,
      feedback: next,
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return SpringRainUiScope(
      child: Builder(
        builder: (context) {
          final t = context.springRainUi;
          return Scaffold(
            backgroundColor: t.surface,
            appBar: AppBar(
              title: const Text('这轮召回了什么'),
              backgroundColor: t.surface,
              surfaceTintColor: Colors.transparent,
            ),
            body: _buildBody(context),
          );
        },
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final t = context.springRainUi;
    if (_error != null) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(t.space24),
          child: Text(
            '召回记录读取失败\n$_error',
            textAlign: TextAlign.center,
            style: TextStyle(color: t.error),
          ),
        ),
      );
    }
    final trace = _trace;
    if (trace == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding:
            EdgeInsets.fromLTRB(t.space16, t.space12, t.space16, t.space32),
        children: [
          _TurnSummaryCard(
            trace: trace,
            messagePreview: widget.messagePreview,
          ),
          SizedBox(height: t.space16),
          if (!trace.wasCaptured)
            const _RecallEmptyCard(
              icon: Icons.history_toggle_off_rounded,
              title: '这条消息没有可用的召回记录',
              body: '它可能来自旧版本、主动消息，或发送时召回追踪尚未启用。',
            )
          else if (trace.items.isEmpty)
            const _RecallEmptyCard(
              icon: Icons.search_off_rounded,
              title: '这一轮没有使用长期记忆',
              body: '系统记录了本轮查询，但没有找到可注入的 Memory Card、'
                  'Episode、Fragment、Saga 或 Project Memory。',
            )
          else
            ..._buildSections(context, trace.items),
          SizedBox(height: t.space16),
          Text(
            '说明：匹配表示内容检索命中；补位表示系统为了保持连续性而加入的最近记忆。'
            '点“定位原对话”可回到生成这条记忆的聊天证据。反馈只影响后续召回排序，不会修改记忆内容。',
            style: TextStyle(
              fontSize: 11,
              height: 1.45,
              color: t.textTertiary,
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildSections(
    BuildContext context,
    List<MemoryRecallTraceItem> items,
  ) {
    const order = [
      MemoryRecallTraceService.memoryCardsTable,
      MemoryRecallTraceService.memoryEpisodesTable,
      MemoryRecallTraceService.memoryFragmentsTable,
      MemoryRecallTraceService.memorySagasTable,
      MemoryRecallTraceService.projectMemoryTable,
    ];
    final widgets = <Widget>[];
    for (final table in order) {
      final section = items.where((item) => item.targetTable == table).toList();
      if (section.isEmpty) continue;
      if (widgets.isNotEmpty) {
        widgets.add(SizedBox(height: context.springRainUi.space16));
      }
      widgets.add(_RecallSection(
        title: section.first.typeLabel,
        items: section,
        onJumpToMessage: (messageId) => Navigator.pop(context, messageId),
        onFeedback: _setFeedback,
      ));
    }
    return widgets;
  }
}

class _TurnSummaryCard extends StatelessWidget {
  const _TurnSummaryCard({
    required this.trace,
    required this.messagePreview,
  });

  final MemoryRecallTrace trace;
  final String messagePreview;

  @override
  Widget build(BuildContext context) {
    final t = context.springRainUi;
    final preview = messagePreview.trim().isEmpty ? '（无文本）' : messagePreview;
    return Container(
      padding: EdgeInsets.all(t.space16),
      decoration: BoxDecoration(
        color: t.surfaceRaised,
        borderRadius: BorderRadius.circular(t.radius18),
        border: Border.all(color: t.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '用户消息',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: t.textTertiary,
            ),
          ),
          SizedBox(height: t.space4),
          Text(
            preview,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 15, height: 1.45, color: t.textPrimary),
          ),
          if (trace.query.trim().isNotEmpty &&
              trace.query.trim() != preview) ...[
            SizedBox(height: t.space12),
            Text(
              '召回查询：${trace.query.trim()}',
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style:
                  TextStyle(fontSize: 11, height: 1.35, color: t.textTertiary),
            ),
          ],
          SizedBox(height: t.space12),
          Wrap(
            spacing: t.space8,
            runSpacing: t.space8,
            children: [
              _CountChip(
                label: '使用 ${trace.items.length}',
                color: t.info,
                background: t.infoSoft,
              ),
              _CountChip(
                label: '匹配 ${trace.directMatchCount}',
                color: t.success,
                background: t.successSoft,
              ),
              if (trace.fallbackCount > 0)
                _CountChip(
                  label: '补位 ${trace.fallbackCount}',
                  color: t.warning,
                  background: t.warningSoft,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CountChip extends StatelessWidget {
  const _CountChip({
    required this.label,
    required this.color,
    required this.background,
  });

  final String label;
  final Color color;
  final Color background;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.w700, color: color),
        ),
      );
}

class _RecallSection extends StatelessWidget {
  const _RecallSection({
    required this.title,
    required this.items,
    required this.onJumpToMessage,
    required this.onFeedback,
  });

  final String title;
  final List<MemoryRecallTraceItem> items;
  final ValueChanged<int> onJumpToMessage;
  final void Function(MemoryRecallTraceItem, MemoryRecallFeedback) onFeedback;

  @override
  Widget build(BuildContext context) {
    final t = context.springRainUi;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$title · ${items.length}',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: t.textSecondary,
          ),
        ),
        SizedBox(height: t.space8),
        ...items.map((item) => Padding(
              padding: EdgeInsets.only(bottom: t.space8),
              child: _RecallItemCard(
                item: item,
                onJumpToMessage: onJumpToMessage,
                onFeedback: onFeedback,
              ),
            )),
      ],
    );
  }
}

class _RecallItemCard extends StatelessWidget {
  const _RecallItemCard({
    required this.item,
    required this.onJumpToMessage,
    required this.onFeedback,
  });

  final MemoryRecallTraceItem item;
  final ValueChanged<int> onJumpToMessage;
  final void Function(MemoryRecallTraceItem, MemoryRecallFeedback) onFeedback;

  @override
  Widget build(BuildContext context) {
    final t = context.springRainUi;
    final accent = item.isDirectMatch ? t.success : t.warning;
    final accentSoft = item.isDirectMatch ? t.successSoft : t.warningSoft;
    return Container(
      padding: EdgeInsets.all(t.space12),
      decoration: BoxDecoration(
        color: t.surfaceRaised,
        borderRadius: BorderRadius.circular(t.radius14),
        border: Border.all(color: t.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  item.title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: t.textPrimary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: accentSoft,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  item.isDirectMatch
                      ? '匹配 ${item.score.toStringAsFixed(0)}'
                      : '最近补位',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: accent,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: t.space8),
          SelectableText(
            item.body,
            style:
                TextStyle(fontSize: 13, height: 1.45, color: t.textSecondary),
          ),
          SizedBox(height: t.space8),
          Wrap(
            spacing: t.space8,
            children: [
              ChoiceChip(
                selected: item.feedback == MemoryRecallFeedback.helpful,
                onSelected: (_) =>
                    onFeedback(item, MemoryRecallFeedback.helpful),
                avatar: const Icon(Icons.thumb_up_alt_outlined, size: 14),
                label: const Text('有帮助'),
              ),
              ChoiceChip(
                selected: item.feedback == MemoryRecallFeedback.irrelevant,
                onSelected: (_) =>
                    onFeedback(item, MemoryRecallFeedback.irrelevant),
                avatar: const Icon(Icons.block_rounded, size: 14),
                label: const Text('不相关'),
              ),
            ],
          ),
          if (item.sourceMessages.isNotEmpty) ...[
            SizedBox(height: t.space12),
            Divider(height: 1, color: t.divider),
            SizedBox(height: t.space8),
            Text(
              '原始聊天证据',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: t.textTertiary,
              ),
            ),
            SizedBox(height: t.space4),
            ...item.sourceMessages.take(6).map(
                  (message) => _SourceMessageRow(
                    message: message,
                    onTap: () => onJumpToMessage(message.id),
                  ),
                ),
            if (item.sourceMessages.length > 6)
              Padding(
                padding: EdgeInsets.only(top: t.space4),
                child: Text(
                  '另有 ${item.sourceMessages.length - 6} 条来源消息',
                  style: TextStyle(fontSize: 10, color: t.textTertiary),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _SourceMessageRow extends StatelessWidget {
  const _SourceMessageRow({required this.message, required this.onTap});

  final MemoryRecallSourceMessage message;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.springRainUi;
    final time = message.timestamp;
    final timeText =
        '${time.month}/${time.day} ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(t.radius10),
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: t.space8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.subdirectory_arrow_right_rounded,
                size: 16, color: t.info),
            SizedBox(width: t.space8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${message.isFromCharacter ? '林埃' : '你'} · $timeText',
                    style: TextStyle(fontSize: 10, color: t.textTertiary),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    message.content,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 12, height: 1.35, color: t.textPrimary),
                  ),
                ],
              ),
            ),
            SizedBox(width: t.space8),
            Icon(Icons.my_location_rounded, size: 16, color: t.info),
          ],
        ),
      ),
    );
  }
}

class _RecallEmptyCard extends StatelessWidget {
  const _RecallEmptyCard({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final t = context.springRainUi;
    return Container(
      padding: EdgeInsets.all(t.space20),
      decoration: BoxDecoration(
        color: t.surfaceRaised,
        borderRadius: BorderRadius.circular(t.radius18),
        border: Border.all(color: t.divider),
      ),
      child: Column(
        children: [
          Icon(icon, size: 28, color: t.textTertiary),
          SizedBox(height: t.space8),
          Text(
            title,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: t.textPrimary,
            ),
          ),
          SizedBox(height: t.space4),
          Text(
            body,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, height: 1.45, color: t.textTertiary),
          ),
        ],
      ),
    );
  }
}
