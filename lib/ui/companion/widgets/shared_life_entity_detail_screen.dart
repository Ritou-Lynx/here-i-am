import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:memex/data/services/file_system_service.dart';
import 'package:memex/data/services/shared_life_memory_service.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/domain/models/presentation_module.dart';
import 'package:memex/ui/companion/widgets/shared_life_review_section.dart';
import 'package:memex/ui/core/cards/ui/timeline_common.dart';
import 'package:memex/utils/user_storage.dart';

class SharedLifeEntityDetailScreen extends StatefulWidget {
  const SharedLifeEntityDetailScreen({
    super.key,
    required this.entityId,
    required this.service,
  });

  final String entityId;
  final SharedLifeMemoryService service;

  @override
  State<SharedLifeEntityDetailScreen> createState() =>
      _SharedLifeEntityDetailScreenState();
}

class _SharedLifeEntityDetailScreenState
    extends State<SharedLifeEntityDetailScreen> {
  SharedLifeEntityDetail? _detail;
  Object? _error;
  bool _isDeleting = false;
  bool _showAdvanced = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final detail = await widget.service.getEntityDetail(widget.entityId);
      if (!mounted) return;
      setState(() => _detail = detail);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error);
    }
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除记录'),
        content: const Text('确定要删除这条记录吗？此操作会撤销所有相关操作。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _isDeleting = true);
    try {
      final entity = _detail?.entity;
      await widget.service.fullyDeleteEntity(
        entityId: widget.entityId,
        sourceCharacterId: entity?.state['source_character_id'] as String? ??
            'user_direct',
      );
      if (!mounted) return;
      Navigator.pop(context, true); // signal caller that something changed
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('删除失败：$e')),
      );
    } finally {
      if (mounted) setState(() => _isDeleting = false);
    }
  }

  Future<void> _editTitle() async {
    final entity = _detail?.entity;
    if (entity == null) return;
    final controller = TextEditingController(text: entity.title);
    final newTitle = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('编辑标题'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: '记录标题'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (newTitle == null || newTitle.isEmpty || newTitle == entity.title) return;
    await widget.service.applyDirectOperation(
      sourceCharacterId: 'user_direct',
      operation: SharedLifeOperationDraft(
        operationType: 'correct',
        entityType: entity.entityType,
        title: newTitle,
        patch: {},
        sourceKind: 'manual_edit',
        entityId: widget.entityId,
      ),
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final detail = _detail;
    final error = _error;
    return Scaffold(
      backgroundColor: const Color(0xFFF6F5F2),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF6F5F2),
        surfaceTintColor: Colors.transparent,
        title: Text(
          detail?.entity.title ?? UserStorage.l10n.companionSharedLifeDetail,
        ),
        actions: [
          if (detail != null) ...[
            IconButton(
              icon: const Icon(Icons.edit_outlined, size: 20),
              tooltip: '编辑标题',
              onPressed: _editTitle,
            ),
            IconButton(
              icon: _isDeleting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.delete_outline, size: 20),
              tooltip: '删除',
              onPressed: _isDeleting ? null : _confirmDelete,
            ),
          ],
        ],
      ),
      body: error != null
          ? Center(child: Text(UserStorage.l10n.operationFailed(error)))
          : detail == null
              ? const Center(child: CircularProgressIndicator())
              : _buildDetail(detail),
    );
  }

  static final _timeFmt = DateFormat('yyyy-MM-dd HH:mm');

  Widget _buildDetail(SharedLifeEntityDetail detail) {
    final entity = detail.entity;
    final hasAdvanced = _hasAdvancedData(entity);
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
      children: [
        // ── Header ──────────────────────────────────────────────────
        Text(
          sharedLifeTypeLabel(entity.entityType),
          style: const TextStyle(
            color: Color(0xFF7C8490),
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          entity.title,
          style: const TextStyle(
            color: Color(0xFF24272C),
            fontSize: 24,
            fontWeight: FontWeight.w700,
          ),
        ),
        if (entity.status == 'completed' || entity.status == 'cancelled') ...[
          const SizedBox(height: 10),
          _StatusChip(status: entity.status),
        ],
        if (entity.tags.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 9,
            runSpacing: 6,
            children:
                entity.tags.map((tag) => TimelineTag(label: tag)).toList(),
          ),
        ],
        // ── Content preview (text, images, numbers) ─────────────────
        if (entity.presentationJson != null)
          _buildPresentationSection(entity.presentationJson!),
        // ── Source messages (most important!) ───────────────────────
        const SizedBox(height: 18),
        _DetailSection(
          title: '原始对话',
          child: detail.sourceMessages.isEmpty
              ? Text(UserStorage.l10n.nothingHere)
              : Column(
                  children: detail.sourceMessages
                      .map((message) => _MessageEvidenceRow(message: message))
                      .toList(),
                ),
        ),
        // ── Time ────────────────────────────────────────────────────
        if (entity.occurredAt != null) _buildTimeRow(entity),
        // ── Location ────────────────────────────────────────────────
        if (entity.placeName != null && entity.placeName!.isNotEmpty)
          _buildLocationRow(entity),
        // ── Related ─────────────────────────────────────────────────
        if (entity.relatedEntityIds.isNotEmpty ||
            entity.relatedFactIds.isNotEmpty) ...[
          const SizedBox(height: 18),
          _DetailSection(
            title: UserStorage.l10n.companionSharedLifeRelated,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ...entity.relatedEntityIds.map(_relatedRow),
                ...entity.relatedFactIds.map(_relatedRow),
              ],
            ),
          ),
        ],
        // ── History ─────────────────────────────────────────────────
        const SizedBox(height: 18),
        _DetailSection(
          title: UserStorage.l10n.companionSharedLifeHistory,
          child: Column(
            children: detail.operations
                .map((operation) => _OperationHistoryRow(operation: operation))
                .toList(),
          ),
        ),
        // ── Advanced (collapsible) ──────────────────────────────────
        if (hasAdvanced) ...[
          const SizedBox(height: 18),
          _buildAdvancedSection(entity),
        ],
      ],
    );
  }

  bool _hasAdvancedData(SharedLifeEntitySnapshot entity) {
    if (entity.valence != null || entity.emotionEvidence != null) return true;
    if (entity.timeConfidence != null || entity.timeSourceText != null) return true;
    if (entity.sourceExcerptsJson != null) return true;
    if (entity.structuredFieldsJson != null &&
        entity.structuredFieldsJson!.trim().isNotEmpty) return true;
    if (entity.primaryDomain != 'general' ||
        entity.facets.isNotEmpty ||
        (entity.dropletLabel != null && entity.dropletLabel!.isNotEmpty)) return true;
    // Also check state for non-empty visible entries
    final stateVisible = entity.state.entries.where((e) {
      final key = e.key;
      if (const {
        'tags', 'related_entity_ids', 'related_fact_ids',
        'schema_version', 'source_character_id', 'source_message_id',
        'source_kind', 'entity_id',
      }.contains(key)) return false;
      final v = e.value;
      if (v == null) return false;
      if (v is String && v.trim().isEmpty) return false;
      if (v is List && v.isEmpty) return false;
      if (v is Map && v.isEmpty) return false;
      return true;
    });
    if (stateVisible.isNotEmpty) return true;
    return false;
  }

  Widget _buildAdvancedSection(SharedLifeEntitySnapshot entity) {
    final children = <Widget>[];
    // Emotion
    if (entity.valence != null || entity.emotionEvidence != null) {
      final parts = <Widget>[];
      if (entity.valence != null && entity.arousal != null) {
        final v = entity.valence!;
        final a = entity.arousal!;
        final vLabel = v >= 0.6 ? '正面 😊' : (v <= 0.4 ? '负面 😔' : '中性 😐');
        final aLabel =
            a >= 0.6 ? '高唤醒 ⚡' : (a <= 0.4 ? '低唤醒 💤' : '中等');
        parts.add(_labeledRow('情绪坐标', '$vLabel · $aLabel (v=${v.toStringAsFixed(2)} a=${a.toStringAsFixed(2)})'));
        if (entity.emotionConfidence != null) {
          parts.add(_labeledRow(
            '情绪置信度',
            '${(entity.emotionConfidence! * 100).toStringAsFixed(0)}%',
          ));
        }
      }
      if (entity.emotionEvidence != null &&
          entity.emotionEvidence!.trim().isNotEmpty) {
        parts.add(Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            '依据：${entity.emotionEvidence!}',
            style: const TextStyle(color: Color(0xFF7C8490), fontSize: 13),
          ),
        ));
      }
      children.add(_DetailSection(title: '情绪分析', child: Column(children: parts)));
    }
    // Classification
    if (entity.primaryDomain != 'general' ||
        entity.facets.isNotEmpty ||
        (entity.dropletLabel != null && entity.dropletLabel!.isNotEmpty)) {
      final parts = <Widget>[];
      if (entity.primaryDomain != 'general') {
        parts.add(_labeledRow('领域', entity.primaryDomain));
      }
      if (entity.facets.isNotEmpty) {
        parts.add(_labeledRow('自动分类', entity.facets.join('、')));
      }
      if (entity.dropletLabel != null && entity.dropletLabel!.isNotEmpty) {
        parts.add(_labeledRow('摘要标签', entity.dropletLabel!));
      }
      parts.add(const Padding(
        padding: EdgeInsets.only(top: 6),
        child: Text('以上由 AI 自动生成，仅供参考',
            style: TextStyle(color: Color(0xFFA0A7B0), fontSize: 12)),
      ));
      children.add(_DetailSection(
          title: 'AI 分类', child: Column(children: parts)));
    }
    // Time metadata
    if (entity.timeConfidence != null || entity.timeSourceText != null) {
      final parts = <Widget>[];
      if (entity.timeConfidence != null) {
        parts.add(_labeledRow(
          '时间置信度',
          '${(entity.timeConfidence! * 100).toStringAsFixed(0)}%',
        ));
      }
      if (entity.timeSourceText != null &&
          entity.timeSourceText!.trim().isNotEmpty) {
        parts.add(_labeledRow('时间依据', entity.timeSourceText!));
      }
      children.add(
          _DetailSection(title: '时间推断', child: Column(children: parts)));
    }
    // Source excerpts
    if (entity.sourceExcerptsJson != null) {
      try {
        final excerpts = jsonDecode(entity.sourceExcerptsJson!) as List;
        if (excerpts.isNotEmpty) {
          children.add(_DetailSection(
            title: '原文摘录',
            child: Column(
              children: excerpts
                  .map((e) => Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text('"${e.toString()}"',
                            style: const TextStyle(
                                color: Color(0xFF596579),
                                fontSize: 13,
                                height: 1.5)),
                      ))
                  .toList(),
            ),
          ));
        }
      } catch (_) {}
    }
    // Structured fields
    if (entity.structuredFieldsJson != null &&
        entity.structuredFieldsJson!.trim().isNotEmpty) {
      try {
        final fields =
            jsonDecode(entity.structuredFieldsJson!) as Map<String, dynamic>;
        final visible = fields.entries
            .where((e) =>
                !const {'_primaryDomain', '_facets', '_dropletLabel'}
                    .contains(e.key))
            .toList();
        if (visible.isNotEmpty) {
          children.add(_DetailSection(
            title: '结构化数据',
            child: Column(
              children: visible
                  .map((e) => _labeledRow(e.key, _displayValue(e.value)))
                  .toList(),
            ),
          ));
        }
      } catch (_) {}
    }
    // Raw state
    {
      final stateVisible = entity.state.entries.where((e) {
        final key = e.key;
        if (const {
          'tags', 'related_entity_ids', 'related_fact_ids',
          'schema_version', 'source_character_id', 'source_message_id',
          'source_kind', 'entity_id',
        }.contains(key)) return false;
        final v = e.value;
        if (v == null) return false;
        if (v is String && v.trim().isEmpty) return false;
        if (v is List && v.isEmpty) return false;
        if (v is Map && v.isEmpty) return false;
        return true;
      });
      if (stateVisible.isNotEmpty) {
        children.add(_DetailSection(
          title: '原始状态（调试用）',
          child: Column(
            children: stateVisible
                .map((e) => _labeledRow(e.key, _displayValue(e.value)))
                .toList(),
          ),
        ));
      }
    }

    if (children.isEmpty) return const SizedBox.shrink();
    return _AdvancedExpansionTile(children: children);
  }

  // ── Compact row helpers (replacing full sections) ────────────────

  Widget _buildTimeRow(SharedLifeEntitySnapshot entity) {
    final label =
        _timeFmt.format(DateTime.fromMillisecondsSinceEpoch(entity.occurredAt!));
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Row(
        children: [
          const Icon(Icons.schedule_rounded, size: 16, color: Color(0xFF7C8490)),
          const SizedBox(width: 8),
          Text(label,
              style:
                  const TextStyle(color: Color(0xFF34383E), fontSize: 14)),
        ],
      ),
    );
  }

  Widget _buildLocationRow(SharedLifeEntitySnapshot entity) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        children: [
          const Icon(Icons.location_on_outlined,
              size: 16, color: Color(0xFF7C8490)),
          const SizedBox(width: 8),
          Text(entity.placeName!,
              style:
                  const TextStyle(color: Color(0xFF34383E), fontSize: 14)),
        ],
      ),
    );
  }

  Widget _labeledRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: const TextStyle(
                color: Color(0xFF7C8490),
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: Color(0xFF34383E),
                fontSize: 14,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Renders the [PresentationModule] from [presentationJson] as a preview
  /// section showing text, media, numbers, etc.  Falls back to nothing if the
  /// JSON is malformed or has no blocks.
  Widget _buildPresentationSection(String presentationJson) {
    final presentation = PresentationModule.tryParse(presentationJson);
    if (presentation == null || presentation.blocks.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: _DetailSection(
        title: '内容预览',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: _withBlockGap(
            presentation.blocks.map(_buildPresentationBlock).toList(),
            10,
          ),
        ),
      ),
    );
  }

  Widget _buildPresentationBlock(MemoryBlock block) {
    if (block is TextBlock) {
      return Text(
        block.text,
        style: const TextStyle(
          color: Color(0xFF596579),
          fontSize: 14,
          height: 1.65,
        ),
      );
    }
    if (block is NumberBlock) {
      final unitStr = block.unit ?? '';
      return Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            block.value,
            style: const TextStyle(
              color: Color(0xFF24272C),
              fontSize: 28,
              fontWeight: FontWeight.w800,
            ),
          ),
          if (unitStr.isNotEmpty) ...[
            const SizedBox(width: 4),
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                unitStr,
                style: const TextStyle(
                  color: Color(0xFF7C8490),
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ],
      );
    }
    if (block is MediaBlock) {
      return _DetailMediaBlock(block: block);
    }
    if (block is TableBlock) {
      return Table(
        border: TableBorder.all(
          color: const Color(0xFFE8E5DF),
          width: 0.5,
          borderRadius: BorderRadius.circular(8),
        ),
        children: block.rows.map((row) {
          return TableRow(
            children: [
              TableCell(
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Text(
                    row.label,
                    style: const TextStyle(
                      color: Color(0xFF7C8490),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              TableCell(
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Text(
                    row.value,
                    style: const TextStyle(
                      color: Color(0xFF24272C),
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
            ],
          );
        }).toList(),
      );
    }
    // Fallback: show raw type for unknown blocks
    return Text(
      '[${block.type}]',
      style: const TextStyle(color: Color(0xFFA0A7B0), fontSize: 12),
    );
  }

  List<Widget> _withBlockGap(List<Widget> items, double gap) {
    if (items.isEmpty) return items;
    final out = <Widget>[];
    for (var i = 0; i < items.length; i++) {
      if (i > 0) out.add(SizedBox(height: gap));
      out.add(items[i]);
    }
    return out;
  }

  Widget _relatedRow(String id) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          const Icon(Icons.link_rounded, size: 16, color: Color(0xFF7C8490)),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              id,
              style: const TextStyle(color: Color(0xFF596579), fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

/// Renders a [MediaBlock] in the detail view using the filesystem path.
class _DetailMediaBlock extends StatelessWidget {
  const _DetailMediaBlock({required this.block});
  final MediaBlock block;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: AspectRatio(
            aspectRatio: 16 / 10,
            child: _buildImage(),
          ),
        ),
        if (block.caption != null) ...[
          const SizedBox(height: 6),
          Text(
            block.caption!,
            style: const TextStyle(
              color: Color(0xFF7C8490),
              fontSize: 12,
              height: 1.5,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildImage() {
    try {
      final absPath = FileSystemService.instance.toAbsolutePath(block.assetPath);
      final file = File(absPath);
      if (file.existsSync()) {
        return Image.file(file, fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _placeholder(),
        );
      }
    } catch (_) {}
    return _placeholder();
  }

  Widget _placeholder() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFCDB8C8), Color(0xFFD9B5AF), Color(0xFF8FA7A0)],
          stops: [0.0, 0.38, 1.0],
        ),
      ),
    );
  }
}

class _DetailSection extends StatelessWidget {
  const _DetailSection({
    required this.title,
    required this.child,
  });

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: Color(0xFF434950),
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: const [
              BoxShadow(
                color: Color(0x0D000000),
                blurRadius: 14,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: child,
        ),
      ],
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});
  final String status;
  @override
  Widget build(BuildContext context) {
    final label = sharedLifeStatusLabel(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: status == 'completed'
            ? const Color(0xFF2E7D32).withValues(alpha: 0.1)
            : const Color(0xFF7C8490).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label,
          style: TextStyle(
            color: status == 'completed'
                ? const Color(0xFF2E7D32)
                : const Color(0xFF7C8490),
            fontSize: 12,
            fontWeight: FontWeight.w600,
          )),
    );
  }
}

class _AdvancedExpansionTile extends StatefulWidget {
  const _AdvancedExpansionTile({required this.children});
  final List<Widget> children;
  @override
  State<_AdvancedExpansionTile> createState() => _AdvancedExpansionTileState();
}

class _AdvancedExpansionTileState extends State<_AdvancedExpansionTile> {
  bool _expanded = false;
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x0D000000),
                  blurRadius: 14,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                const Icon(Icons.tune_rounded,
                    size: 18, color: Color(0xFF7C8490)),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text('AI 标注详情',
                      style: TextStyle(
                          color: Color(0xFF434950),
                          fontSize: 15,
                          fontWeight: FontWeight.w700)),
                ),
                Icon(
                  _expanded
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  color: const Color(0xFF7C8490),
                ),
              ],
            ),
          ),
        ),
        if (_expanded) ...[
          const SizedBox(height: 12),
          ...widget.children,
        ],
      ],
    );
  }
}

class _MessageEvidenceRow extends StatelessWidget {
  const _MessageEvidenceRow({required this.message});

  final PersonaChatMessage message;

  @override
  Widget build(BuildContext context) {
    final role = message.isFromCharacter
        ? UserStorage.l10n.companionSharedLifeCharacterMessage
        : UserStorage.l10n.companionSharedLifeUserMessage;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$role · ${DateFormat('MM-dd HH:mm').format(message.timestamp)}',
            style: const TextStyle(color: Color(0xFF8B9098), fontSize: 12),
          ),
          const SizedBox(height: 4),
          Text(
            message.content,
            style: const TextStyle(
              color: Color(0xFF34383E),
              fontSize: 14,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}

class _OperationHistoryRow extends StatelessWidget {
  const _OperationHistoryRow({required this.operation});

  final SharedLifeEventOperation operation;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.history_rounded, size: 16, color: Color(0xFF7C8490)),
          const SizedBox(width: 7),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  operation.operationType,
                  style: const TextStyle(
                    color: Color(0xFF34383E),
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  DateFormat('MM-dd HH:mm').format(
                    DateTime.fromMicrosecondsSinceEpoch(operation.createdAt),
                  ),
                  style:
                      const TextStyle(color: Color(0xFF8B9098), fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _displayValue(dynamic value) {
  if (value is String || value is num || value is bool) return '$value';
  if (value is List) return value.map(_displayValue).join(' · ');
  return jsonEncode(value);
}
