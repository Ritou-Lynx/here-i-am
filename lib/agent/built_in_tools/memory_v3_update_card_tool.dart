import 'dart:convert';

import 'package:dart_agent_core/dart_agent_core.dart';
import 'package:memex/data/memory_v3/services/record_organizer_service.dart';
import 'package:memex/db/app_database.dart';

/// Builds the tool that lets the companion update fields of an existing
/// Memory V3 card.
Tool buildMemoryV3UpdateCardTool() {
  return Tool(
    name: 'memory_v3_update_card',
    description: '''Update one or more fields of an existing memory card.

Use this when the user points out an error in a recorded card and asks you
to fix it. First call `memory_v3_query` to get the FULL card_id.

Pick the right parameter for what the user wants to fix:

- `title` / `retrieval_text` / `droplet_label`: TEXT CONTENT of the card.
  Use these when the user says the wording / summary is wrong. When
  `retrieval_text` changes, the visible summary card text blocks are
  AUTO-SYNCED to keep what the user sees in sync.
- `presentation_module`: FULL PresentationModule JSON (advanced). Pass this
  ONLY when you need to add/remove/reorder blocks (number, quote, table,
  media, progressBar, ...). Format: a JSON object string, e.g.
  '{"title":"午饭","blocks":[{"type":"text","text":"..."}]}'.
  ⚠ Passing this REPLACES the entire presentation module.
- `structured_fields`: BUSINESS DATA (amount, merchant, category, source,
  companions, etc.). MERGES with existing fields — fields you omit are kept.
  Time fields like `paidAt` / `receivedAt` / `occurredAt` are STRIPPED from
  this parameter (use `time_overrides` instead).
- `time_overrides`: ONLY time fields (`paidAt`, `receivedAt`, `occurredAt`,
  `startAt`, `endAt`, `dueAt`, `remindAt`, `sleepStart`, `sleepEnd`,
  `wakeDate`, `occurredEndAt`, `nextActionAt`). Pass this ONLY when the user
  explicitly says the event time is wrong. Format: JSON object string,
  e.g. '{"receivedAt": "2026-07-15T14:00:00"}'.
- `type` / `status`: card classification (rarely needed).

Rules:
- Never invent a card_id. Always obtain it from `memory_v3_query` first.
- Do NOT touch time fields unless the user explicitly says the event time is
  wrong. The card's modification time is recorded in the audit log, not in
  the card itself.
- retrieval_text MUST use absolute dates ("7月15日" or "2026-07-15"). NEVER
  use relative terms like "昨天" / "今天" / "今晚" / "前天" — they become
  wrong after time passes. Anchor to the event time from `structuredFields`
  (paidAt / receivedAt / occurredAt) or from the card's recordedAt.
- If unsure what to change, ask the user which field is wrong before calling.
- For most "wrong wording" corrections, only `title` / `retrieval_text` are
  needed; leave everything else alone.
- After the tool succeeds, briefly confirm to the user what was changed.''',
    parameters: {
      'type': 'object',
      'properties': {
        'card_id': {
          'type': 'string',
          'description': 'Full UUID of the card to update.',
        },
        'title': {
          'type': 'string',
          'description': 'New title. Omit to keep current.',
        },
        'retrieval_text': {
          'type': 'string',
          'description': 'New retrieval text. Omit to keep current.',
        },
        'droplet_label': {
          'type': 'string',
          'description': 'New 2-4 char droplet label. Omit to keep current.',
        },
        'type': {
          'type': 'string',
          'enum': ['fact', 'event', 'task', 'schedule', 'plan'],
          'description': 'New card type. Omit to keep current.',
        },
        'status': {
          'type': 'string',
          'description': 'New status (task/schedule/plan only). Omit to keep.',
        },
        'structured_fields_type': {
          'type': 'string',
          'description':
              'New structured fields type. Pass with structured_fields.',
        },
        'structured_fields': {
          'type': 'string',
          'description':
              'JSON object string of business data fields, '
              'e.g. \'{"amount_cny":128,"merchant":"麦当劳"}\'. '
              'MERGES with existing — omitted fields are kept. '
              'Time fields are stripped; use time_overrides for those.',
        },
        'presentation_module': {
          'type': 'string',
          'description':
              'Optional full PresentationModule JSON to REPLACE the visible '
              'summary card layout. JSON object string, '
              'e.g. \'{"title":"午饭","blocks":[{"type":"text","text":"..."}]}\'. '
              'Omit unless you need to add/reorder non-text blocks (number, '
              'quote, table, media, etc.). For plain wording fixes, prefer '
              '`retrieval_text` which auto-syncs text blocks.',
        },
        'time_overrides': {
          'type': 'string',
          'description':
              'JSON object string of time fields to explicitly change, '
              'e.g. \'{"receivedAt": "2026-07-15T14:00:00"}\'. '
              'ONLY pass this when the user says the event time is wrong. '
              'Non-time keys are silently ignored.',
        },
      },
      'required': ['card_id'],
    },
    executable: (
      String cardId, [
      String? title,
      String? retrievalText,
      String? dropletLabel,
      String? type,
      String? status,
      String? structuredFieldsType,
      String? structuredFieldsJson,
      String? timeOverridesJson,
      String? presentationModuleJson,
    ]) async {
      if (!AppDatabase.isInitialized) {
        return jsonEncode({'success': false, 'error': 'Database not available.'});
      }
      if (!RecordOrganizerServiceV3.isInitialized) {
        return jsonEncode({'success': false, 'error': 'Record service not available.'});
      }

      Map<String, dynamic>? parseJsonObject(String? raw, String paramName) {
        if (raw == null || raw.isEmpty) return null;
        try {
          final decoded = jsonDecode(raw);
          if (decoded is Map<String, dynamic>) return decoded;
        } catch (_) {}
        return <String, dynamic>{};
      }

      final structuredFields = parseJsonObject(structuredFieldsJson, 'structured_fields');
      final timeOverrides = parseJsonObject(timeOverridesJson, 'time_overrides');

      Map<String, dynamic>? presentationModule;
      if (presentationModuleJson != null && presentationModuleJson.isNotEmpty) {
        try {
          final decoded = jsonDecode(presentationModuleJson);
          if (decoded is Map<String, dynamic>) {
            presentationModule = decoded;
          } else {
            return jsonEncode({
              'success': false,
              'error': 'presentation_module must be a JSON object string.',
            });
          }
        } catch (e) {
          return jsonEncode({
            'success': false,
            'error': 'presentation_module JSON parse error: $e',
          });
        }
      }

      if (structuredFieldsJson != null &&
          structuredFieldsJson.isNotEmpty &&
          (structuredFields == null || structuredFields.isEmpty)) {
        return jsonEncode({
          'success': false,
          'error': 'structured_fields must be a JSON object string.',
        });
      }
      if (timeOverridesJson != null &&
          timeOverridesJson.isNotEmpty &&
          (timeOverrides == null || timeOverrides.isEmpty)) {
        return jsonEncode({
          'success': false,
          'error': 'time_overrides must be a JSON object string.',
        });
      }

      try {
        final updated = await RecordOrganizerServiceV3.instance.updateCard(
          cardId,
          title: title,
          retrievalText: retrievalText,
          dropletLabel: dropletLabel,
          type: type,
          status: status,
          structuredFields: structuredFields,
          structuredFieldsType: structuredFieldsType,
          timeOverrides: timeOverrides,
          presentationModule: presentationModule,
        );
        if (updated == null) {
          return jsonEncode({
            'success': false,
            'error': 'Card not found: $cardId',
          });
        }
        return jsonEncode({
          'success': true,
          'card_id': updated.id,
          'title': updated.title,
          'retrieval_text': updated.retrievalText,
          'droplet_label': updated.dropletLabel,
          'type': updated.type,
        });
      } catch (e) {
        return jsonEncode({'success': false, 'error': e.toString()});
      }
    },
  );
}