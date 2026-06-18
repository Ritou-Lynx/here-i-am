import 'dart:convert';

import 'package:dart_agent_core/dart_agent_core.dart';
import 'package:logging/logging.dart';

import 'package:memex/data/services/reading/reading_fetch_coordinator.dart';
import 'package:memex/data/services/shared_life_memory_service.dart';
import 'package:memex/utils/logger.dart';

/// Builds a `LoadReadingContent` tool for the Companion Agent.
///
/// The agent uses `LifeMemoryQuery` to discover that a `reading_item` entity
/// exists; that response only carries a short summary + ~500-char excerpt
/// stashed in the entity state. To actually *discuss* or *narrate* the
/// article the agent needs the full body — that's what this tool returns.
///
/// Full bodies are stored on disk (workspace/reading/{entityId}.md) by the
/// fetch pipeline, so they don't bloat the shared-life entity row.
///
/// Returns a JSON envelope with `success`, `entity_id`, and either
/// `content` + `title` + `author` + `platform` on success, or `reason` on
/// failure (entity not found, not a reading_item, content not yet fetched,
/// file missing, etc.).
Tool buildLoadReadingContentTool({
  required SharedLifeMemoryService sharedLifeMemory,
  required ReadingFetchCoordinator fetchCoordinator,
}) {
  final logger = getLogger('LoadReadingContent');
  return Tool(
    name: 'LoadReadingContent',
    description:
        'Load the full body of a saved reading_item (article the user '
        'shared from 小红书 / 微信公众号 / web). Use this when the user '
        'asks you to discuss, narrate, summarise, or react to a specific '
        'saved article. Workflow: first call LifeMemoryQuery to find the '
        'reading_item and get its entity_id, then call this to fetch the '
        'full text before replying.\n\n'
        'The returned `content` may include TWO sections:\n'
        '  1) Plain article body at the top.\n'
        '  2) A section starting with "---" then "图片文字识别（OCR）：" '
        'containing on-device OCR output from the article\'s images, '
        'labelled "[图 N - 文字识别]". For 小红书 图文 notes — especially '
        'technical sharing posts — the image text is OFTEN the substantive '
        'content (code snippets, settings screenshots, captions). You MUST '
        'read and consider this section, not just the plain body. If a '
        'reading_item has empty plain body but rich OCR text, the OCR IS '
        'the article.\n\n'
        'Use the content as reference, do not quote large blocks verbatim. '
        'Stay in your character voice; do not produce bullet-pointed '
        'corporate summaries.',
    parameters: {
      'type': 'object',
      'properties': {
        'entity_id': {
          'type': 'string',
          'description':
              'Exact reading_item entity ID from LifeMemoryQuery.',
        },
      },
      'required': ['entity_id'],
    },
    parameterMode: ToolParameterMode.object,
    executable: (Map<String, dynamic> args) async {
      try {
        final entityId = (args['entity_id'] as String?)?.trim() ?? '';
        if (entityId.isEmpty) {
          return jsonEncode({
            'success': false,
            'reason': 'entity_id is required',
          });
        }
        final detail = await sharedLifeMemory.getEntityDetail(entityId);
        if (detail == null) {
          return jsonEncode({
            'success': false,
            'entity_id': entityId,
            'reason': 'entity not found',
          });
        }
        if (detail.entity.entityType != 'reading_item') {
          return jsonEncode({
            'success': false,
            'entity_id': entityId,
            'reason': 'entity is not a reading_item '
                '(entityType=${detail.entity.entityType})',
          });
        }
        final state = detail.entity.state;
        final fetchStatus = (state['fetch_status'] as String?) ?? 'pending';
        if (fetchStatus != 'success') {
          return jsonEncode({
            'success': false,
            'entity_id': entityId,
            'reason': 'content not yet available '
                '(fetch_status=$fetchStatus). '
                'Use the entity title and excerpt fields from '
                'LifeMemoryQuery instead.',
            'title': detail.entity.title,
            'excerpt': state['content_excerpt'],
          });
        }
        final filePath = state['content_file_path'] as String?;
        if (filePath == null || filePath.isEmpty) {
          return jsonEncode({
            'success': false,
            'entity_id': entityId,
            'reason': 'no content file path recorded',
          });
        }
        final body = await fetchCoordinator.loadFullBody(filePath);
        if (body == null || body.isEmpty) {
          return jsonEncode({
            'success': false,
            'entity_id': entityId,
            'reason': 'content file missing on disk',
          });
        }
        logger.info(
            'LoadReadingContent returned ${body.length} chars for $entityId');
        return jsonEncode({
          'success': true,
          'entity_id': entityId,
          'title': detail.entity.title,
          'author': state['author'],
          'platform': state['platform'],
          'url': state['url'],
          'content': body,
        });
      } catch (e, stack) {
        logger.warning('LoadReadingContent failed: $e', e, stack);
        return jsonEncode({
          'success': false,
          'reason': 'tool error: $e',
        });
      }
    },
  );
}
