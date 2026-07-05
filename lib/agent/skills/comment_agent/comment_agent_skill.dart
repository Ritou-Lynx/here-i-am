import 'package:dart_agent_core/dart_agent_core.dart';
import 'package:memex/agent/prompts.dart';
import 'package:memex/agent/skills/character_tools_factory.dart';
import 'package:memex/domain/models/character_model.dart';
import 'package:memex/utils/user_storage.dart';

/// Skill for Comment Agent - generates warm comments for private entries.
class CommentAgentSkill extends Skill {
  CommentAgentSkill({
    CharacterModel? character,
    required String factId,
    required String workingDirectory,
    required String userId,
    String userProfile = '',
    String? forcedReplyToId,
    void Function()? onCommentSaved,
    super.forceActivate,
  }) : super(
          name: 'persona_comment',
          description: Prompts.commentAgentSkillDescription,
          systemPrompt: _buildSystemPrompt(
            character: character,
            userProfile: userProfile,
          ),
          tools: _buildTools(
            userId: userId,
            workingDirectory: workingDirectory,
            factId: factId,
            characterId: character?.id,
            forcedReplyToId: forcedReplyToId,
            onCommentSaved: onCommentSaved,
          ),
        );

  static String _buildSystemPrompt({
    CharacterModel? character,
    required String userProfile,
  }) {
    final personaBuffer = StringBuffer();
    if (character != null) {
      personaBuffer.writeln('Name: ${character.name}');
      personaBuffer.writeln('Tags: ${character.tags.join(', ')}');
    }

    final b = StringBuffer();
    b.write(
      Prompts.commentSkillSystemPrompt(
        personaBuffer.toString(),
        UserStorage.l10n.commentLanguageInstruction,
      ),
    );

    if (userProfile.isNotEmpty) {
      b.writeln();
      b.writeln('## User Profile');
      b.writeln(userProfile);
    }

    return b.toString();
  }

  static List<Tool> _buildTools({
    required String userId,
    required String workingDirectory,
    required String factId,
    String? characterId,
    String? forcedReplyToId,
    void Function()? onCommentSaved,
  }) {
    return CharacterToolsFactory.buildCommentTools(
      userId: userId,
      workingDirectory: workingDirectory,
      factId: factId,
      characterId: characterId,
      forcedReplyToId: forcedReplyToId,
      onCommentSaved: onCommentSaved,
    );
  }
}
