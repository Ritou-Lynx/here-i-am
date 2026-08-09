import 'package:dart_agent_core/dart_agent_core.dart';
import 'package:flutter/foundation.dart';
import 'package:memex/data/services/persona_chat_service.dart';
import 'package:memex/data/services/sticker_library.dart';

/// Builds the `send_sticker` tool for the companion agent.
///
/// When the agent wants to express an emotion visually, it calls this tool
/// with a `stickerId` from the available sticker list (injected per-turn via
/// system reminders).  The sticker is attached as a `type: 'sticker'`
/// addendum to a new character message and rendered inline via
/// [StickerAddendumWidget].
///
/// The `enum` for `stickerId` is populated dynamically from [StickerLibrary]
/// so the LLM can only select stickers that actually exist.  If the library
/// is empty the tool still registers but returns an error message.
Tool buildSendStickerTool({required String characterId}) {
  final stickerIds = StickerLibrary.instance.ids;

  if (stickerIds.isEmpty) {
    return Tool(
      name: 'send_sticker',
      description: 'Send a sticker image. No stickers are currently available.',
      parameters: const {
        'type': 'object',
        'properties': <String, dynamic>{},
        'required': <String>[],
      },
      executable: () async => 'No stickers are currently available.',
    );
  }

  // Track which stickers were already sent this turn to prevent duplicates.
  final sentThisTurn = <String>{};

  return Tool(
    name: 'send_sticker',
    description: '''Send a sticker image to express an emotion visually.

Use this when words alone don't fully convey how you feel - a warm moment, playful teasing, coquettishness, or a reaction that's better shown than said.

Rules:
- ALWAYS write your spoken text reply in your <visible_reply> BEFORE calling this tool. The sticker appears as a separate message right after your text.
- Call this tool AT MOST ONCE per turn. Never call it twice.
- Do NOT use stickers for serious topics, reminders, task confirmations, or record operations.
- Pick the sticker that best matches the current emotion from the available list.
- Do NOT pass your chat text as the caption parameter. Leave caption empty unless you want a very short label (<=5 chars) under the sticker.

Parameters:
- stickerId: One of the available sticker ids (see the per-turn available_stickers list).
- caption: Optional very short label (<=5 chars) below the sticker. Usually leave this empty.''',
    parameters: {
      'type': 'object',
      'properties': {
        'stickerId': {
          'type': 'string',
          'enum': stickerIds,
          'description': 'The sticker to send. Choose from the available_stickers list.',
        },
        'caption': {
          'type': 'string',
          'description': 'Optional very short label under the sticker. Leave empty if unsure.',
        },
      },
      'required': ['stickerId'],
    },
    executable: (String stickerId, [String? caption]) async {
      // Prevent duplicate sends within the same turn.
      if (sentThisTurn.contains(stickerId)) {
        return 'Error: this sticker was already sent this turn. Do NOT call send_sticker again.';
      }
      sentThisTurn.add(stickerId);

      final sticker = StickerLibrary.instance.get(stickerId);
      if (sticker == null) {
        return 'Error: sticker not found: $stickerId. '
            'Available: ${StickerLibrary.instance.ids.join(", ")}';
      }
      try {
        await PersonaChatService.instance.addCharacterMessage(
          characterId,
          '', // No text content — the sticker is the message.
          addenda: [
            {
              'type': 'sticker',
              'stickerId': stickerId,
              'assetPath': sticker.assetPath,
            },
          ],
          isRead: true,
        );
        debugPrint('[Sticker] Sent: $stickerId (${sticker.desc})');
        return 'Sticker sent: $stickerId (${sticker.desc})';
      } catch (e) {
        debugPrint('[Sticker] Failed to send: $e');
        return 'Error sending sticker: $e';
      }
    },
  );
}
