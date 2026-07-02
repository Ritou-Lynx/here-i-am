/// In-memory representation of a structured output from the Record Organizer
/// agent, before it gets persisted across the V3 table family.
///
/// Designed to be JSON-serializable for prompt-LLM IO. See § 9 of
/// docs/memory-research/MEMORY_PROPOSAL_V3.md for field semantics.
library;

import 'dart:convert';

/// One Memory Card's worth of structured output.
///
/// A single raw input may produce multiple `OrganizedCard` instances (V3 § 9.4).
class OrganizedCard {
  OrganizedCard({
    required this.type,
    required this.title,
    required this.dropletLabel,
    required this.presentationModule,
    required this.retrievalText,
    required this.valence,
    required this.arousal,
    this.status,
    this.structuredFieldsType,
    this.structuredFields,
    this.entityLinks = const [],
    this.needsFollowUp,
  });

  final String type; // fact / event / task / schedule / plan
  final String title;
  final String dropletLabel;

  /// JSON-serializable PresentationModule (block list).
  final Map<String, dynamic> presentationModule;

  String retrievalText;
  final double valence; // -1.0 ~ 1.0
  final double arousal; // 0.0 ~ 1.0
  final String? status; // task/schedule/plan only

  final String? structuredFieldsType;
  final Map<String, dynamic>? structuredFields;

  /// Entities mentioned in this card. Each entry will be resolved (created or
  /// reused) and linked via [memory_entity_links].
  final List<OrganizedEntityLink> entityLinks;

  /// JSON `[{field, question}]` — fields the agent could not infer and that
  /// I should follow up on in the next chat turn.
  final List<Map<String, dynamic>>? needsFollowUp;

  Map<String, dynamic> toJson() => {
        'type': type,
        'title': title,
        'dropletLabel': dropletLabel,
        'presentationModule': presentationModule,
        'retrievalText': retrievalText,
        'valence': valence,
        'arousal': arousal,
        if (status != null) 'status': status,
        if (structuredFieldsType != null)
          'structuredFieldsType': structuredFieldsType,
        if (structuredFields != null) 'structuredFields': structuredFields,
        if (entityLinks.isNotEmpty)
          'entityLinks': entityLinks.map((e) => e.toJson()).toList(),
        if (needsFollowUp != null) 'needsFollowUp': needsFollowUp,
      };

  factory OrganizedCard.fromJson(Map<String, dynamic> json) => OrganizedCard(
        type: json['type'] as String,
        title: json['title'] as String,
        dropletLabel: json['dropletLabel'] as String,
        presentationModule:
            (json['presentationModule'] as Map).cast<String, dynamic>(),
        retrievalText: json['retrievalText'] as String,
        valence: (json['valence'] as num).toDouble(),
        arousal: (json['arousal'] as num).toDouble(),
        status: json['status'] as String?,
        structuredFieldsType: json['structuredFieldsType'] as String?,
        structuredFields: json['structuredFields'] != null
            ? (json['structuredFields'] as Map).cast<String, dynamic>()
            : null,
        entityLinks: ((json['entityLinks'] as List?) ?? const [])
            .map((e) =>
                OrganizedEntityLink.fromJson((e as Map).cast<String, dynamic>()))
            .toList(),
        needsFollowUp: json['needsFollowUp'] != null
            ? ((json['needsFollowUp'] as List)
                .map((e) => (e as Map).cast<String, dynamic>())
                .toList())
            : null,
      );
}

/// Entity mention extracted by the Record Organizer.
///
/// `category` follows V3 § 5.2: person / place / event / project / hobby /
/// work / object. `relation` follows V3 § 5.3: mentioned / about / with /
/// caused_by / located_at.
class OrganizedEntityLink {
  OrganizedEntityLink({
    required this.name,
    required this.category,
    required this.relation,
    this.relationshipToUser,
    this.confidence = 1.0,
  });

  final String name;
  final String category;
  final String relation;
  final String? relationshipToUser; // family/friend/colleague/self/other
  final double confidence;

  Map<String, dynamic> toJson() => {
        'name': name,
        'category': category,
        'relation': relation,
        if (relationshipToUser != null)
          'relationshipToUser': relationshipToUser,
        'confidence': confidence,
      };

  factory OrganizedEntityLink.fromJson(Map<String, dynamic> json) =>
      OrganizedEntityLink(
        name: json['name'] as String,
        category: json['category'] as String,
        relation: json['relation'] as String,
        relationshipToUser: json['relationshipToUser'] as String?,
        confidence: (json['confidence'] as num?)?.toDouble() ?? 1.0,
      );
}

/// Full output of one Record Organizer run.
class OrganizedRecord {
  OrganizedRecord({required this.cards});

  /// One or more cards produced from the same raw input.
  /// Empty list = nothing should be persisted (rare; usually means input was
  /// pure metadata).
  final List<OrganizedCard> cards;

  String toPrettyJson() =>
      const JsonEncoder.withIndent('  ').convert({'cards': cards.map((c) => c.toJson()).toList()});

  factory OrganizedRecord.fromJson(Map<String, dynamic> json) => OrganizedRecord(
        cards: ((json['cards'] as List?) ?? const [])
            .map((e) =>
                OrganizedCard.fromJson((e as Map).cast<String, dynamic>()))
            .toList(),
      );

  bool get isEmpty => cards.isEmpty;
}
