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

  CharacterModel({
    required this.id,
    required this.name,
    required this.tags,
    required this.persona,
    required this.enabled,
    this.avatar,
    this.memory = const [],
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
  }) {
    return CharacterModel(
      id: id ?? this.id,
      name: name ?? this.name,
      tags: tags ?? this.tags,
      persona: persona ?? this.persona,
      enabled: enabled ?? this.enabled,
      avatar: avatar ?? this.avatar,
      memory: memory ?? this.memory,
    );
  }
}
