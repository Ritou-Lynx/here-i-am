import 'dart:convert';

import 'package:dart_agent_core/dart_agent_core.dart';
import 'package:memex/data/memory_v3/services/record_organizer_service.dart';
import 'package:memex/db/app_database.dart';

/// Builds the tool that lets the companion delete a memory card.
///
/// This is the counterpart to `memory_v3_update_card`: when the user says a
/// recorded card is wrong and wants it gone (not corrected), the companion
/// can delete it directly instead of telling the user to go to Memory Review
/// and do it manually.
Tool buildMemoryV3DeleteCardTool() {
  return Tool(
    name: 'memory_v3_delete_card',
    description: '''Delete a memory card that was recorded by mistake, is a
duplicate, or contains fabricated/inferred content the user never confirmed.

Use this when:
- The user says a card is wrong and wants it deleted (not just corrected)
- A card was recorded twice for the same event
- The user points out that details in a card were inferred/fabricated, not
  from what they actually said or from an image they sent
- The user asks "把那条删了" / "这张卡不对，删掉" / "别记这个"

Rules:
- NEVER delete a card the user has not explicitly approved removing.
- Find the card_id first with `memory_v3_query`, then pass the FULL UUID here.
- For partial corrections (wrong amount, wrong wording), prefer
  `memory_v3_update_card` over delete — update preserves the card's place
  in history.
- Deletion is permanent (an audit-log row is kept, but the card itself and
  its structured fields / sources / entity links are removed).
- After the tool succeeds, briefly confirm to the user what was deleted.''',
    parameters: {
      'type': 'object',
      'properties': {
        'card_id': {
          'type': 'string',
          'description':
              'Full UUID of the card to delete. Obtain it from '
              '`memory_v3_query` first — never invent an id.',
        },
        'reason': {
          'type': 'string',
          'description':
              'Why this card is being deleted (for the audit log). '
              'Brief, e.g. "duplicate", "fabricated details", "user requested removal".',
        },
      },
      'required': ['card_id', 'reason'],
    },
    executable: (String cardId, String reason) async {
      if (!AppDatabase.isInitialized) {
        return jsonEncode({'success': false, 'error': 'Database not available.'});
      }
      if (!RecordOrganizerServiceV3.isInitialized) {
        return jsonEncode({
          'success': false,
          'error': 'Record service not available.'
        });
      }
      try {
        await RecordOrganizerServiceV3.instance.deleteCard(
          cardId,
          sourceKind: 'agent_tool',
        );
        return jsonEncode({
          'success': true,
          'deleted_card_id': cardId,
          'reason': reason,
        });
      } catch (e) {
        return jsonEncode({'success': false, 'error': e.toString()});
      }
    },
  );
}