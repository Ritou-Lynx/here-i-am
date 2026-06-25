import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:memex/data/services/shared_life_memory_service.dart';
import 'package:memex/ui/core/cards/style/timeline_theme.dart';
import 'package:memex/ui/core/cards/ui/timeline_card_container.dart';
import 'package:memex/ui/core/cards/ui/timeline_common.dart';
import 'package:memex/utils/user_storage.dart';

@visibleForTesting
class SharedLifeReviewCard extends StatelessWidget {
  const SharedLifeReviewCard({
    super.key,
    required this.entity,
    this.onTap,
  });

  final SharedLifeEntitySnapshot entity;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final summary = _summary(entity.state);
    final details = _detailEntries(entity.state).take(3);
    return TimelineCard(
      variant: TimelineCardVariant.glass,
      padding: const EdgeInsets.all(16),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TimelineHeader(
            title: entity.title,
            subtitle: _typeLabel(entity.entityType),
            icon: _typeIcon(entity.entityType),
            compact: true,
            trailing: _SharedLifeStatusBadge(status: entity.status),
          ),
          if (summary.isNotEmpty)
            Text(
              summary,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TimelineTheme.typography.body.copyWith(
                color: TimelineTheme.colors.textSecondary,
                fontSize: 14,
                height: 1.45,
              ),
            ),
          if (details.isNotEmpty) ...[
            if (summary.isNotEmpty) const SizedBox(height: 8),
            ...details.map(
              (detail) => Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Row(
                  children: [
                    Icon(
                      _fieldIcon(detail.key),
                      size: 14,
                      color: TimelineTheme.colors.textTertiary,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        detail.value,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TimelineTheme.typography.small.copyWith(
                          color: TimelineTheme.colors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          if (entity.tags.isNotEmpty) TimelineFooter(tags: entity.tags),
        ],
      ),
    );
  }
}

class _SharedLifeStatusBadge extends StatelessWidget {
  const _SharedLifeStatusBadge({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final label = _statusLabel(status);
    if (label.isEmpty) return const SizedBox.shrink();
    final color = switch (status) {
      'completed' => TimelineTheme.colors.success,
      'cancelled' => TimelineTheme.colors.textTertiary,
      _ => TimelineTheme.colors.primary,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

String _summary(Map<String, dynamic> state) {
  for (final key in const ['summary', 'details', 'description', 'content']) {
    final value = state[key];
    if (value != null && '$value'.trim().isNotEmpty) {
      return _displayValue(value);
    }
  }
  return '';
}

Iterable<MapEntry<String, String>> _detailEntries(Map<String, dynamic> state) {
  const hidden = {
    'summary',
    'details',
    'description',
    'content',
    'source_excerpts',
    'status',
    'tags',
    'related_entity_ids',
    'related_fact_ids',
  };
  return state.entries
      .where((entry) => !hidden.contains(entry.key) && entry.value != null)
      .map((entry) => MapEntry(entry.key, _displayValue(entry.value)));
}

String _displayValue(dynamic value) {
  if (value is String || value is num || value is bool) return '$value';
  if (value is List) return value.map(_displayValue).join(' · ');
  return jsonEncode(value);
}

String sharedLifeTypeLabel(String entityType) {
  return _typeLabel(entityType);
}

String sharedLifeStatusLabel(String status) {
  return _statusLabel(status);
}

String _typeLabel(String entityType) {
  return switch (entityType) {
    'event' => UserStorage.l10n.companionLifeEvent,
    'task' => UserStorage.l10n.companionLifeTask,
    'plan' => UserStorage.l10n.companionLifePlan,
    'schedule' => UserStorage.l10n.companionLifeSchedule,
    _ => UserStorage.l10n.companionLifeFact,
  };
}

String _statusLabel(String status) {
  return switch (status) {
    'completed' => UserStorage.l10n.companionLifeCompleted,
    'cancelled' => UserStorage.l10n.companionLifeCancelled,
    _ => '', // "active" is the default — don't show a label for normal records
  };
}

IconData _typeIcon(String entityType) {
  return switch (entityType) {
    'event' => Icons.auto_awesome_rounded,
    'task' => Icons.check_circle_outline_rounded,
    'plan' => Icons.route_rounded,
    'schedule' => Icons.calendar_month_rounded,
    _ => Icons.bookmark_outline_rounded,
  };
}

IconData _fieldIcon(String key) {
  final normalized = key.toLowerCase();
  if (normalized.contains('time') ||
      normalized.contains('date') ||
      normalized.contains('deadline')) {
    return Icons.schedule_rounded;
  }
  if (normalized.contains('place') || normalized.contains('location')) {
    return Icons.location_on_outlined;
  }
  return Icons.notes_rounded;
}
