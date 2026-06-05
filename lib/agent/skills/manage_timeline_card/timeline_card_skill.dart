import 'package:dart_agent_core/dart_agent_core.dart';
import 'package:logging/logging.dart';
import 'package:memex/agent/prompts.dart';
import 'package:memex/agent/skills/manage_timeline_card/timeline_templates.dart';
import 'package:memex/data/services/file_system_service.dart';
import 'package:memex/domain/models/card_model.dart';
import 'package:memex/utils/user_storage.dart';

final logger = Logger('TimelineCardSkill');

/// Skill for managing Timeline Cards.
class TimelineCardSkill extends Skill {
  TimelineCardSkill({
    super.forceActivate,
    bool stopAfterSuccessSaveCard = false,
  }) : super(
          name: 'manage_timeline_card',
          description:
              'Creates new timeline cards from user input or updates existing timeline card details based on feedback. '
              'Handles information extraction, template selection, and card data persistence for the Timeline view. '
              'Use when: 1. User posts new content needing a timeline card. 2. User provides feedback to modify an existing timeline card.',
          systemPrompt: _buildSystemPrompt(),
          tools: _buildTools(stopAfterSuccessSaveCard),
        );

  static String _buildSystemPrompt() {
    final templatesSection = _buildTemplatesSection();
    return Prompts.timelineCardSkillSystemPrompt(
      templatesSection,
      UserStorage.l10n.timelineCardLanguageInstruction,
    );
  }

  static String _buildTemplatesSection() {
    final sb = StringBuffer();
    sb.writeln('# Available Templates\n');

    for (final template in timelineTemplates) {
      sb.writeln('## template_id: ${template['template_id']}');
      sb.writeln('**Use Case**: ${template['use_case']}');
      sb.writeln('**Data Structure**:');
      sb.writeln(template['data_structure']);
      sb.writeln('');
    }

    return sb.toString();
  }

  static Future<String> getTimelineCardMetadata(String userId) async {
    final fileService = FileSystemService.instance;
    await fileService.ensureTagsFileInitialized(userId);
    final tagsListRaw = await fileService.readTagsFile(userId);
    final tagsList = tagsListRaw.map((t) => t['name'] as String).toList();

    final sb = StringBuffer();
    sb.writeln('# Existing Tags');
    if (tagsList.isEmpty) {
      sb.writeln('No tags currently available.');
    } else {
      for (final tag in tagsList) {
        sb.writeln('- $tag');
      }
    }

    return sb.toString();
  }

  static List<Tool> _buildTools(bool stopAfterSuccessSaveCard) {
    return [
      Tool(
        name: 'get_card_metadata',
        description: 'Get all available Timeline Card Templates and Tags.',
        parameters: {
          'type': 'object',
          'properties': {},
        },
        executable: () async {
          final context = AgentCallToolContext.current;
          final userId = context?.state.metadata['userId'] as String?;
          if (userId == null || userId.isEmpty) {
            throw StateError('Missing userId in agent metadata.');
          }
          return getTimelineCardMetadata(userId);
        },
      ),
      Tool(
        name: 'save_timeline_card',
        description: 'Saves or updates a timeline card for the Memex timeline.',
        parameters: {
          'type': 'object',
          'properties': {
            'fact_id': {
              'type': 'string',
              'description':
                  'The id of the raw input (e.g. 2025/01/01.md#ts_123). If creating a new record from chat text, provide any tentative id; the tool will create a valid source fact when needed.'
            },
            'title': {
              'type': 'string',
              'description':
                  'A concise summary displayed on detail page header.'
            },
            'ui_configs': {
              'type': 'array',
              'description':
                  'UI rendering configuration list. You MUST provide the full data object according to the selected template.',
              'items': {
                'type': 'object',
                'properties': {
                  'template_id': {
                    'type': 'string',
                    'description': 'Template ID',
                  },
                  'data': {
                    'type': 'object',
                    'description':
                        'Template data object. CRITICAL: This MUST NOT be empty. You must populate all required fields for the chosen template_id as defined in the available templates.'
                  },
                },
                'required': ['template_id', 'data'],
              },
            },
            'address': {
              'type': 'string',
              'description':
                  'Location information for where the card happened. If raw input explicitly names a place, use that. If raw input describes an immediate present-time event, check-in, photo capture, or daily activity and current_location_context is available, use its location_summary or full_address_candidate as a conservative default. Do not use current_location_context for memories, plans, remote events, or when raw input names a conflicting place. Do not be too specific. Use the format "City 路 Specific Location" (e.g., Beijing 路 Chaoyang Park) if possible, otherwise just the specific location name is fine.'
            },
            'user_mark_address': {
              'type': 'string',
              'description':
                  'User-marked location information, set when raw input contains very close user-marked location',
            },
            'content_creation_date': {
              'type': 'string',
              'description':
                  'The creation date of the content (e.g. image capture time), in format "YYYY-MM-DD HH:MM:SS". If not provided, current time will be used.'
            },
            'tags': {
              'type': 'array',
              'description':
                  'Select 1-3 most appropriate tags strictly from tags.md. Do not invent new tags.',
              'items': {
                'type': 'object',
                'properties': {
                  'name': {
                    'type': 'string',
                    'description':
                        'Tag name. MUST exactly match one of the existing tags from get_card_metadata.',
                  },
                  'icon': {
                    'type': 'string',
                    'description':
                        'Not used anymore, internal icons are hardcoded.',
                  },
                },
                'required': ['name'],
              },
            },
          },
          'required': ['fact_id', 'title', 'ui_configs'],
        },
        executable: (
          String fact_id,
          String title,
          List ui_configs,
          String? address,
          String? user_mark_address,
          String? content_creation_date,
          List? tags,
        ) async {
          final fileService = FileSystemService.instance;
          final context = AgentCallToolContext.current;
          if (context == null) {
            throw StateError(
              'save_timeline_card must be called within an agent execution context.',
            );
          }

          logger.info('Saving card for fact: $fact_id');

          try {
            final userId = context.state.metadata['userId'] as String?;
            if (userId == null || userId.isEmpty) {
              throw StateError('Missing userId in agent metadata.');
            }
            if (title.isEmpty) {
              throw ArgumentError('title is required');
            }
            if (ui_configs.isEmpty) {
              throw ArgumentError('ui_configs must be provided and non-empty.');
            }

            final finalUiConfigs = _validatedUiConfigs(ui_configs);
            final timestamp = _parseTimestamp(content_creation_date);
            final effectiveFactId = await _resolveOrCreateFactId(
              fileService: fileService,
              userId: userId,
              requestedFactId: fact_id,
              title: title,
              uiConfigs: finalUiConfigs,
              timestamp: timestamp,
            );
            final tagNames = await _canonicalTagNames(
              fileService: fileService,
              userId: userId,
              tags: tags,
            );

            Map<String, dynamic>? locationInfo;
            if (user_mark_address != null) {
              locationInfo = await fileService.getUserLocationByName(
                userId,
                user_mark_address,
              );
            }

            final uiConfigEntries = finalUiConfigs
                .map((m) => UiConfig(
                      templateId: m['template_id'] as String? ?? '',
                      data: m['data'] is Map
                          ? Map<String, dynamic>.from(m['data'] as Map)
                          : {},
                    ))
                .toList();

            final updatedCardData = await fileService.updateCardFile(
              userId,
              effectiveFactId,
              createIfNotExists: true,
              (card) {
                var updated = card.copyWith(
                  status: 'completed',
                  title: title,
                  uiConfigs: uiConfigEntries,
                  timestamp: timestamp ??
                      (card.timestamp > 0
                          ? card.timestamp
                          : DateTime.now().millisecondsSinceEpoch ~/ 1000),
                  address: address ?? card.address,
                  tags: tagNames.isNotEmpty ? tagNames : card.tags,
                );
                if (locationInfo != null) {
                  updated = updated.copyWith(
                    userFixedAddress: locationInfo['name'] as String?,
                    userFixedLocation: UserFixedLocation(
                      lat: (locationInfo['lat'] as num?)?.toDouble(),
                      lng: (locationInfo['lng'] as num?)?.toDouble(),
                      name: locationInfo['name'] as String?,
                    ),
                  );
                }
                return updated;
              },
            );

            if (updatedCardData == null) {
              return AgentToolResult(
                content: TextPart(
                  'Card file not found for fact_id: $effectiveFactId, maybe it has been deleted',
                ),
              );
            }

            await _logCardModified(
              fileService: fileService,
              userId: userId,
              factId: effectiveFactId,
              title: title,
            );

            return AgentToolResult(
              content: TextPart(
                'Successfully saved timeline card for Fact $effectiveFactId',
              ),
              stopFlag: stopAfterSuccessSaveCard,
            );
          } catch (e, stack) {
            logger.severe('SaveTimelineCard failed', e, stack);
            Error.throwWithStackTrace(e, stack);
          }
        },
      ),
    ];
  }
}

List<Map<String, dynamic>> _validatedUiConfigs(List uiConfigs) {
  final finalUiConfigs = <Map<String, dynamic>>[];
  for (var i = 0; i < uiConfigs.length; i++) {
    final raw = uiConfigs[i];
    if (raw is! Map) {
      throw ArgumentError(
        'ui_configs[$i] must be an object (Map), got ${raw.runtimeType}.',
      );
    }
    final config = Map<String, dynamic>.from(raw);
    validateUiConfig(config);
    finalUiConfigs.add(config);
  }

  if (finalUiConfigs.length <= 1) return finalUiConfigs;
  final nonSnapshot = finalUiConfigs
      .where((config) => config['template_id'] != 'snapshot')
      .toList();
  return nonSnapshot.isNotEmpty ? nonSnapshot : [finalUiConfigs.first];
}

int? _parseTimestamp(String? contentCreationDate) {
  if (contentCreationDate == null || contentCreationDate.isEmpty) return null;
  try {
    return DateTime.parse(contentCreationDate).millisecondsSinceEpoch ~/ 1000;
  } catch (e) {
    logger.warning(
      'Failed to parse content_creation_date: $contentCreationDate',
    );
    return null;
  }
}

Future<String> _resolveOrCreateFactId({
  required FileSystemService fileService,
  required String userId,
  required String requestedFactId,
  required String title,
  required List<Map<String, dynamic>> uiConfigs,
  required int? timestamp,
}) async {
  final trimmedFactId = requestedFactId.trim();
  final existing = await _tryExtractFact(fileService, userId, trimmedFactId);
  if (existing != null) return trimmedFactId;

  final factDate = _dateForNewFact(
    fileService: fileService,
    factId: trimmedFactId,
    timestamp: timestamp,
  );
  final newFactId = await fileService.generateFactId(userId, factDate);
  final simpleFactId = fileService.extractSimpleFactId(newFactId);
  final rawContent = _rawFactContentFromCard(
    title: title,
    uiConfigs: uiConfigs,
  );
  final markdownEntry =
      '## <id:$simpleFactId> ${fileService.formatTime(factDate)} "{}"\n\n$rawContent\n';

  await fileService.appendToDailyFactFile(userId, factDate, markdownEntry);
  final created = await _tryExtractFact(fileService, userId, newFactId);
  if (created == null) {
    throw StateError('Failed to create source fact for timeline card.');
  }
  return newFactId;
}

Future<FactContentResult?> _tryExtractFact(
  FileSystemService fileService,
  String userId,
  String factId,
) async {
  if (factId.isEmpty) return null;
  try {
    return await fileService.extractFactContentFromFile(userId, factId);
  } catch (_) {
    return null;
  }
}

DateTime _dateForNewFact({
  required FileSystemService fileService,
  required String factId,
  required int? timestamp,
}) {
  if (timestamp != null) {
    return DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
  }
  try {
    final parsedDate = fileService.parseFactIdDate(factId);
    final now = DateTime.now();
    return DateTime(
      parsedDate.year,
      parsedDate.month,
      parsedDate.day,
      now.hour,
      now.minute,
      now.second,
    );
  } catch (_) {
    return DateTime.now();
  }
}

String _rawFactContentFromCard({
  required String title,
  required List<Map<String, dynamic>> uiConfigs,
}) {
  final parts = <String>[];
  for (final config in uiConfigs) {
    final data = config['data'];
    if (data is! Map) continue;
    final body = data['body'];
    final content = data['content'];
    final summary = data['summary'];
    if (body is String && body.trim().isNotEmpty) {
      parts.add(body.trim());
    } else if (content is String && content.trim().isNotEmpty) {
      parts.add(content.trim());
    } else if (summary is String && summary.trim().isNotEmpty) {
      parts.add(summary.trim());
    }
  }
  if (parts.isEmpty) return title;
  return '# $title\n\n${parts.join('\n\n')}';
}

Future<List<String>> _canonicalTagNames({
  required FileSystemService fileService,
  required String userId,
  required List? tags,
}) async {
  await fileService.ensureTagsFileInitialized(userId);
  final tagDefinitions = await fileService.readTagsFile(userId);
  final canonicalTags = <String, String>{
    for (final tag in tagDefinitions)
      if ((tag['name'] as String?)?.trim().isNotEmpty == true)
        (tag['name'] as String).trim().toLowerCase():
            (tag['name'] as String).trim(),
  };

  if (tags == null || canonicalTags.isEmpty) return const [];

  final tagNames = <String>[];
  for (final tagObj in tags) {
    if (tagObj is! Map) continue;
    final requestedTag = (tagObj['name'] as String?)?.trim().toLowerCase();
    final tagName = canonicalTags[requestedTag];
    if (tagName == null || tagNames.contains(tagName)) continue;
    tagNames.add(tagName);
    if (tagNames.length >= 3) break;
  }
  return tagNames;
}

Future<void> _logCardModified({
  required FileSystemService fileService,
  required String userId,
  required String factId,
  required String title,
}) async {
  try {
    final parts = factId.split('#');
    if (parts.length != 2) return;
    final datePart = parts[0].replaceFirst('.md', '');
    final tsId = parts[1];
    final cardPath = 'Cards/${datePart}_$tsId.yaml';
    await fileService.eventLogService.logFileModified(
      userId: userId,
      filePath: cardPath,
      description: 'Agent updated timeline card',
      metadata: {'fact_id': factId, 'title': title},
    );
  } catch (_) {
    // Event logging failure should not break tool.
  }
}
