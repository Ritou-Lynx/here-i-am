import 'character_memory.dart';

/// AI character model
class CharacterModel {
  final String id;
  final String name;
  final List<String> tags;
  final bool enabled;
  final String? avatar;
  final List<CharacterMemoryBlock> memory;
  final bool isPrimaryCompanion; // user's chosen main companion
  final String?
      firstMessage; // greeting sent on first chat (from tavern first_mes)
  final String? chatBackground; // custom chat background image path
  final String? ttsVoiceId; // ElevenLabs voice ID for TTS

  CharacterModel({
    required this.id,
    required this.name,
    required this.tags,
    required this.enabled,
    this.avatar,
    this.memory = const [],
    this.isPrimaryCompanion = false,
    this.firstMessage,
    this.chatBackground,
    this.ttsVoiceId,
  });

  factory CharacterModel.fromJson(Map<String, dynamic> json) {
    return CharacterModel(
      id: json['id'] as String,
      name: json['name'] as String,
      tags:
          (json['tags'] as List<dynamic>?)?.map((e) => e.toString()).toList() ??
              [],
      enabled: json['enabled'] as bool? ?? false,
      avatar: json['avatar'] as String?,
      memory: (json['memory'] as List<dynamic>?)
              ?.map((e) =>
                  CharacterMemoryBlock.fromJson(Map<String, dynamic>.from(e)))
              .toList() ??
          [],
      isPrimaryCompanion: json['is_primary_companion'] as bool? ?? false,
      firstMessage: json['first_message'] as String?,
      chatBackground: json['chat_background'] as String?,
      ttsVoiceId: json['tts_voice_id'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'tags': tags,
      'enabled': enabled,
      'avatar': avatar,
      'memory': memory.map((e) => e.toJson()).toList(),
      'is_primary_companion': isPrimaryCompanion,
      if (firstMessage != null) 'first_message': firstMessage,
      if (chatBackground != null) 'chat_background': chatBackground,
      if (ttsVoiceId != null) 'tts_voice_id': ttsVoiceId,
    };
  }

  CharacterModel copyWith({
    String? id,
    String? name,
    List<String>? tags,
    bool? enabled,
    String? avatar,
    List<CharacterMemoryBlock>? memory,
    bool? isPrimaryCompanion,
    String? firstMessage,
    String? chatBackground,
    String? ttsVoiceId,
  }) {
    return CharacterModel(
      id: id ?? this.id,
      name: name ?? this.name,
      tags: tags ?? this.tags,
      enabled: enabled ?? this.enabled,
      avatar: avatar ?? this.avatar,
      memory: memory ?? this.memory,
      isPrimaryCompanion: isPrimaryCompanion ?? this.isPrimaryCompanion,
      firstMessage: firstMessage ?? this.firstMessage,
      chatBackground: chatBackground ?? this.chatBackground,
      ttsVoiceId: ttsVoiceId ?? this.ttsVoiceId,
    );
  }
}
