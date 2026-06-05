import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:memex/data/services/shared_life_memory_service.dart';
import 'package:memex/db/app_database.dart';
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
      ),
      body: error != null
          ? Center(child: Text(UserStorage.l10n.operationFailed(error)))
          : detail == null
              ? const Center(child: CircularProgressIndicator())
              : _buildDetail(detail),
    );
  }

  Widget _buildDetail(SharedLifeEntityDetail detail) {
    final entity = detail.entity;
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
      children: [
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
        const SizedBox(height: 10),
        Text(
          sharedLifeStatusLabel(entity.status),
          style: const TextStyle(
            color: Color(0xFF596579),
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (entity.tags.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 9,
            runSpacing: 6,
            children:
                entity.tags.map((tag) => TimelineTag(label: tag)).toList(),
          ),
        ],
        const SizedBox(height: 24),
        _DetailSection(
          title: UserStorage.l10n.companionSharedLifeCurrentState,
          child: _StateTable(state: entity.state),
        ),
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
        const SizedBox(height: 18),
        _DetailSection(
          title: UserStorage.l10n.companionSharedLifeEvidence,
          child: detail.sourceMessages.isEmpty
              ? Text(UserStorage.l10n.nothingHere)
              : Column(
                  children: detail.sourceMessages
                      .map((message) => _MessageEvidenceRow(message: message))
                      .toList(),
                ),
        ),
        const SizedBox(height: 18),
        _DetailSection(
          title: UserStorage.l10n.companionSharedLifeHistory,
          child: Column(
            children: detail.operations
                .map((operation) => _OperationHistoryRow(operation: operation))
                .toList(),
          ),
        ),
      ],
    );
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

class _StateTable extends StatelessWidget {
  const _StateTable({required this.state});

  final Map<String, dynamic> state;

  @override
  Widget build(BuildContext context) {
    final visible = state.entries.where(
      (entry) => !const {
        'tags',
        'related_entity_ids',
        'related_fact_ids',
      }.contains(entry.key),
    );
    if (visible.isEmpty) return Text(UserStorage.l10n.nothingHere);
    return Column(
      children: visible
          .map(
            (entry) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 92,
                    child: Text(
                      entry.key,
                      style: const TextStyle(
                        color: Color(0xFF7C8490),
                        fontSize: 13,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      _displayValue(entry.value),
                      style: const TextStyle(
                        color: Color(0xFF34383E),
                        fontSize: 14,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          )
          .toList(),
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
