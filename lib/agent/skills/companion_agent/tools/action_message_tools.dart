import 'package:dart_agent_core/dart_agent_core.dart';
import 'package:memex/data/services/persona_chat_service.dart';

/// Factory for the SendActionMessage tool used by the companion agent.
///
/// An "action message" is a narrative / stage-direction style message
/// (e.g. *leans closer and whispers*) that is rendered differently in the
/// chat UI — no speech bubble, italic text, centred.
class ActionMessageToolFactory {
  final String characterId;
  final Set<String> _sentActionKeys = <String>{};

  ActionMessageToolFactory({required this.characterId});

  Tool buildSendActionMessageTool() {
    return Tool(
      name: 'SendActionMessage',
      description: '''Send a narrative / action description message to the user.

Use this for actions, gestures, scene descriptions, or atmosphere — anything
that is *shown* rather than *said*.

This sends a SEPARATE message rendered as a centred italic line between chat
bubbles. Your spoken reply goes in the final text output of the turn.
Do NOT put dialogue or spoken words in this tool.''',
      parameters: {
        'type': 'object',
        'properties': {
          'action': {
            'type': 'string',
            'description': 'The narrative / action text to send.',
          },
        },
        'required': ['action'],
      },
      executable: (String action) async {
        final trimmed = action.trim();
        if (trimmed.isEmpty) {
          return 'Error: action text cannot be empty.';
        }
        final actionKey = _canonicalActionKey(trimmed);
        if (!_sentActionKeys.add(actionKey)) {
          return 'Action message already sent in this turn. Do not send it again.';
        }
        // Wrap in asterisks if not already wrapped.
        final wrapped = (trimmed.startsWith('*') && trimmed.endsWith('*'))
            ? trimmed
            : '*$trimmed*';
        try {
          await PersonaChatService.instance.addActionMessage(
            characterId,
            wrapped,
            isRead: true,
          );
          return 'Action message sent.';
        } catch (e) {
          _sentActionKeys.remove(actionKey);
          return 'Error sending action message: $e';
        }
      },
    );
  }

  static String _canonicalActionKey(String action) {
    var normalized = action.trim();
    while (normalized.length >= 2 &&
        normalized.startsWith('*') &&
        normalized.endsWith('*')) {
      normalized = normalized.substring(1, normalized.length - 1).trim();
    }
    return normalized.replaceAll(RegExp(r'\s+'), ' ');
  }
}
