import 'character_memory.dart';

/// AI character model
class CharacterModel {
  final String id;
  final String name;
  final List<String> tags;
  final String persona; // combined persona (identity, style, examples, PKM filters, etc.)
  final bool enabled;
  final String? avatar;
  final List<CharacterMemoryBlock> memory;
  final bool isPrimaryCompanion; // user's chosen main companion
  final String? interestFilter; // what this character cares about (for selection)

  CharacterModel({
    required this.id,
    required this.name,
    required this.tags,
    required this.persona,
    required this.enabled,
    this.avatar,
    this.memory = const [],
    this.isPrimaryCompanion = false,
    this.interestFilter,
  });

  factory CharacterModel.fromJson(Map<String, dynamic> json) {
    return CharacterModel(
      id: json['id'] as String,
      name: json['name'] as String,
      tags:
          (json['tags'] as List<dynamic>?)?.map((e) => e.toString()).toList() ??
              [],
      persona: json['persona'] as String? ?? '',
      enabled: json['enabled'] as bool? ?? false,
      avatar: json['avatar'] as String?,
      memory: (json['memory'] as List<dynamic>?)
              ?.map((e) =>
                  CharacterMemoryBlock.fromJson(Map<String, dynamic>.from(e)))
              .toList() ??
          [],
      isPrimaryCompanion: json['is_primary_companion'] as bool? ?? false,
      interestFilter: json['interest_filter'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'tags': tags,
      'persona': persona,
      'enabled': enabled,
      'avatar': avatar,
      'memory': memory.map((e) => e.toJson()).toList(),
      'is_primary_companion': isPrimaryCompanion,
      if (interestFilter != null) 'interest_filter': interestFilter,
    };
  }

  CharacterModel copyWith({
    String? id,
    String? name,
    List<String>? tags,
    String? persona,
    bool? enabled,
    String? avatar,
    List<CharacterMemoryBlock>? memory,
    bool? isPrimaryCompanion,
    String? interestFilter,
  }) {
    return CharacterModel(
      id: id ?? this.id,
      name: name ?? this.name,
      tags: tags ?? this.tags,
      persona: persona ?? this.persona,
      enabled: enabled ?? this.enabled,
      avatar: avatar ?? this.avatar,
      memory: memory ?? this.memory,
      isPrimaryCompanion: isPrimaryCompanion ?? this.isPrimaryCompanion,
      interestFilter: interestFilter ?? this.interestFilter,
    );
  }
}
