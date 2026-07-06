/// In-memory representation of Dreaming fragment extraction output.
///
/// These objects are automatic relationship-memory evidence. They are NOT
/// User-truth Memory Cards and must never be persisted to `memory_cards`.
library;

import 'dart:convert';
import 'dart:math' as math;

class DreamingFragmentExtraction {
  DreamingFragmentExtraction({required this.fragments});

  final List<DreamingFragmentDraft> fragments;

  bool get isEmpty => fragments.isEmpty;

  String toPrettyJson() => const JsonEncoder.withIndent('  ').convert({
        'fragments': fragments.map((f) => f.toJson()).toList(),
      });

  factory DreamingFragmentExtraction.fromJson(Map<String, dynamic> json) {
    return DreamingFragmentExtraction(
      fragments: ((json['fragments'] as List?) ?? const [])
          .map((e) => DreamingFragmentDraft.fromJson(
                (e as Map).cast<String, dynamic>(),
              ))
          .where((fragment) => fragment.content.isNotEmpty)
          .toList(),
    );
  }
}

class DreamingFragmentDraft {
  DreamingFragmentDraft({
    required this.content,
    required this.sourceMessageIds,
    required this.emotionalWeight,
    required this.isUserTruthCandidate,
    this.sourceScope = 'main_chat',
    this.entityLinks = const [],
  });

  final String content;
  final List<int> sourceMessageIds;
  final String sourceScope;
  final double emotionalWeight;
  final bool isUserTruthCandidate;
  final List<DreamingEntityLinkDraft> entityLinks;

  Map<String, dynamic> toJson() => {
        'content': content,
        'sourceMessageIds': sourceMessageIds,
        'sourceScope': sourceScope,
        'emotionalWeight': emotionalWeight,
        'isUserTruthCandidate': isUserTruthCandidate,
        if (entityLinks.isNotEmpty)
          'entityLinks': entityLinks.map((e) => e.toJson()).toList(),
      };

  factory DreamingFragmentDraft.fromJson(Map<String, dynamic> json) {
    final rawContent = (json['content'] as String? ?? '').trim();
    final content = rawContent.length <= 80
        ? rawContent
        : rawContent.substring(0, math.min(rawContent.length, 80)).trim();
    final ids = ((json['sourceMessageIds'] as List?) ?? const [])
        .map((id) {
          if (id is int) return id;
          if (id is num) return id.toInt();
          return int.tryParse(id.toString());
        })
        .whereType<int>()
        .toSet()
        .toList()
      ..sort();

    return DreamingFragmentDraft(
      content: content,
      sourceMessageIds: ids,
      sourceScope: (json['sourceScope'] as String? ?? 'main_chat').trim(),
      emotionalWeight: _clampDouble(json['emotionalWeight'], min: 0, max: 1),
      isUserTruthCandidate: json['isUserTruthCandidate'] == true,
      entityLinks: ((json['entityLinks'] as List?) ?? const [])
          .map((e) => DreamingEntityLinkDraft.fromJson(
                (e as Map).cast<String, dynamic>(),
              ))
          .where((link) => link.name.isNotEmpty)
          .toList(),
    );
  }
}

class DreamingEntityLinkDraft {
  DreamingEntityLinkDraft({
    required this.name,
    required this.category,
    required this.relation,
    this.relationshipToUser,
    this.confidence = 1.0,
  });

  final String name;
  final String category;
  final String relation;
  final String? relationshipToUser;
  final double confidence;

  Map<String, dynamic> toJson() => {
        'name': name,
        'category': category,
        'relation': relation,
        if (relationshipToUser != null)
          'relationshipToUser': relationshipToUser,
        'confidence': confidence,
      };

  factory DreamingEntityLinkDraft.fromJson(Map<String, dynamic> json) {
    return DreamingEntityLinkDraft(
      name: (json['name'] as String? ?? '').trim(),
      category: _normalizeCategory(json['category'] as String?),
      relation: _normalizeRelation(json['relation'] as String?),
      relationshipToUser:
          (json['relationshipToUser'] as String?)?.trim().isNotEmpty == true
              ? (json['relationshipToUser'] as String).trim()
              : null,
      confidence: _clampDouble(json['confidence'], min: 0, max: 1),
    );
  }
}

double _clampDouble(Object? raw, {required double min, required double max}) {
  final value = raw is num ? raw.toDouble() : double.tryParse('$raw') ?? min;
  return value.clamp(min, max).toDouble();
}

String _normalizeCategory(String? raw) {
  const allowed = {
    'person',
    'place',
    'event',
    'project',
    'hobby',
    'work',
    'object',
    'illness',
  };
  final value = raw?.trim();
  return allowed.contains(value) ? value! : 'object';
}

String _normalizeRelation(String? raw) {
  const allowed = {
    'mentioned',
    'about',
    'with',
    'caused_by',
    'located_at',
  };
  final value = raw?.trim();
  return allowed.contains(value) ? value! : 'mentioned';
}
