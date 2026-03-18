import 'dart:convert';
import 'dart:io';

import 'package:dart_agent_core/dart_agent_core.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;

import 'package:memex/agent/memex_skill_host_agent/memex_skill_host_agent.dart';
import 'package:memex/agent/pure_skill_host_agent/pure_skill_host_agent.dart';
import 'package:memex/agent/state_util.dart';
import 'package:memex/data/services/custom_agent_config_service.dart';
import 'package:memex/data/services/event_bus_service.dart';
import 'package:memex/data/services/file_system_service.dart';
import 'package:memex/domain/models/agent_definitions.dart';
import 'package:memex/domain/models/card_model.dart';
import 'package:memex/domain/models/custom_agent_config.dart';
import 'package:memex/domain/models/event_bus_message.dart';
import 'package:memex/domain/models/llm_config.dart';
import 'package:memex/utils/logger.dart';
import 'package:memex/utils/user_storage.dart';

final Logger _logger = getLogger('CustomAgentTaskHandler');

/// Call once at app init to wire the real runner into the service.
void initCustomAgentHandler() {
  setCustomAgentRunner(_handleCustomAgentTask);
}

/// MIME type lookup for common image/audio extensions.
const _mimeTypes = <String, String>{
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.png': 'image/png',
  '.gif': 'image/gif',
  '.webp': 'image/webp',
  '.heic': 'image/heic',
  '.heif': 'image/heif',
  '.bmp': 'image/bmp',
  '.tiff': 'image/tiff',
  '.tif': 'image/tiff',
  '.mp3': 'audio/mpeg',
  '.wav': 'audio/wav',
  '.flac': 'audio/flac',
  '.aac': 'audio/aac',
  '.ogg': 'audio/ogg',
  '.m4a': 'audio/mp4',
  '.aiff': 'audio/aiff',
  '.aif': 'audio/aiff',
  '.wma': 'audio/x-ms-wma',
};

const _imageExtensions = {
  '.jpg',
  '.jpeg',
  '.png',
  '.gif',
  '.webp',
  '.heic',
  '.heif',
  '.bmp',
  '.tiff',
  '.tif',
};

const _audioExtensions = {
  '.mp3',
  '.wav',
  '.flac',
  '.aac',
  '.ogg',
  '.m4a',
  '.aiff',
  '.aif',
  '.wma',
};

/// Regex to extract `fs://filename` references from markdown media links
/// in serialized event content. Matches both Chinese and English labels:
///   `![图片](fs://xxx)` / `![image](fs://xxx)` → image
///   `[音频](fs://xxx)` / `[audio](fs://xxx)` → audio
final _mediaRefPattern =
    RegExp(r'(?:!\[(?:图片|image)\]|\[(?:音频|audio)\])\(fs://([^)]+)\)');

/// Extract media references from the event XML string and build multimodal
/// [UserContentPart] list. This is generic — works for any event type whose
/// serialized content contains `![image](fs://file)` or `[audio](fs://file)`.
Future<List<UserContentPart>> _buildAssetPartsFromXml(
    String userId, String eventXml) async {
  final matches = _mediaRefPattern.allMatches(eventXml);
  if (matches.isEmpty) return const [];

  final assetsDir = FileSystemService.instance.getAssetsPath(userId);
  final parts = <UserContentPart>[];

  for (final match in matches) {
    final filename = match.group(1)!;
    final fullMatch = match.group(0)!;
    final isImage = fullMatch.startsWith('!');

    try {
      final absPath = p.join(assetsDir, filename);
      final file = File(absPath);
      if (!file.existsSync()) {
        _logger.warning('Asset file not found, skipping: $absPath');
        continue;
      }

      final ext = p.extension(filename).toLowerCase();
      final mime = _mimeTypes[ext];
      if (mime == null) {
        _logger.fine('Unsupported asset extension, skipping: $ext');
        continue;
      }

      final bytes = await file.readAsBytes();
      final b64 = base64Encode(bytes);

      if (isImage && _imageExtensions.contains(ext)) {
        parts.add(ImagePart(b64, mime));
      } else if (!isImage && _audioExtensions.contains(ext)) {
        parts.add(AudioPart(b64, mime));
      }
    } catch (e) {
      _logger.warning('Failed to read asset $filename: $e');
    }
  }
  return parts;
}

Future<void> _handleCustomAgentTask(
  String userId,
  CustomAgentConfig config,
  Map<String, dynamic> payload,
) async {
  final agentName = config.agentName;
  _logger.info(
      'Running custom agent "$agentName" for event ${payload['event_type']}');

  final agentIdForLLM = config.llmConfigKey ?? AgentDefinitions.chatAgent;
  final resources = await UserStorage.getAgentLLMResources(
    agentIdForLLM,
    defaultClientKey: config.llmConfigKey ?? LLMConfig.defaultClientKey,
  );

  final now = DateTime.now();
  final nowStr =
      '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}_${now.microsecond.toString().padLeft(6, '0')}';
  final sessionId = 'custom_${agentName}_${userId}_$nowStr';
  final state = await loadOrCreateAgentState(sessionId, {
    'userId': userId,
    'agentName': agentName,
    'scene': 'custom_agent_$agentName',
    'sceneId': nowStr,
  });

  final skillAbsPath = FileSystemService.instance
      .resolveSkillPath(userId, config.skillDirectoryPath);

  final eventXml = payload['event_xml'] as String? ?? '';
  final textContent =
      'A system event has occurred. Process it according to your skills.\n\n$eventXml';

  // Build multimodal message: text + any image/audio assets found in the XML.
  final contentParts = <UserContentPart>[TextPart(textContent)];
  final mediaParts = await _buildAssetPartsFromXml(userId, eventXml);
  contentParts.addAll(mediaParts);

  final userMessage = UserMessage(contentParts);

  StatefulAgent agent;
  switch (config.hostAgentType) {
    case HostAgentType.pure:
      agent = await PureSkillHostAgent.createAgent(
        client: resources.client,
        modelConfig: resources.modelConfig,
        userId: userId,
        name: agentName,
        state: state,
        skillDirectoryPath: skillAbsPath,
        workingDirectory: config.workingDirectory,
        additionalSystemPrompt: config.systemPrompt,
      );
      break;
    case HostAgentType.memex:
      agent = await MemexSkillHostAgent.createAgent(
        client: resources.client,
        modelConfig: resources.modelConfig,
        userId: userId,
        name: agentName,
        state: state,
        skillDirectoryPath: skillAbsPath,
        workingDirectory: config.workingDirectory,
        additionalSystemPrompt: config.systemPrompt,
      );
      break;
  }

  final responses = await agent.run([userMessage]);

  // Extract text result from agent output.
  String? resultText;
  final last = responses.isNotEmpty ? responses.last : null;
  if (last is ModelMessage && last.textOutput != null) {
    resultText = last.textOutput;
    _logger.info('Custom agent "$agentName" result: $resultText');
  } else {
    _logger.info('Custom agent "$agentName" completed, last: $last');
  }

  // Create a system_task card to show the result on the timeline.
  await _createResultCard(
    userId: userId,
    agentName: agentName,
    status: 'completed',
    message: resultText,
  );
}

/// Create a system_task card for the custom agent result and notify the UI.
Future<void> _createResultCard({
  required String userId,
  required String agentName,
  required String status,
  String? message,
}) async {
  final now = DateTime.now();
  final timestampMs = now.millisecondsSinceEpoch;
  final timestampSec = timestampMs ~/ 1000;
  final year = now.year;
  final month = now.month.toString().padLeft(2, '0');
  final day = now.day.toString().padLeft(2, '0');
  final factId = '$year/$month/$day.md#ts_$timestampMs';

  final title = agentName;
  final uiConfig = UiConfig(
    templateId: 'system_task',
    data: {
      'title': title,
      'status': status,
      if (message != null) 'message': message,
    },
  );

  final card = CardData(
    factId: factId,
    title: title,
    timestamp: timestampSec,
    status: status,
    tags: [agentName],
    uiConfigs: [uiConfig],
  );

  final fs = FileSystemService.instance;
  try {
    final success = await fs.safeWriteCardFile(userId, factId, card);
    if (success) {
      _logger.info('Created system_task card for agent "$agentName": $factId');
    } else {
      _logger.warning('safeWriteCardFile returned false for $factId');
    }
  } catch (e) {
    _logger.warning('Failed to write system_task card: $e');
    return;
  }

  // Notify the timeline UI.
  EventBusService.instance.emitEvent(CardAddedMessage(
    id: factId,
    html: '',
    timestamp: timestampSec,
    tags: [agentName],
    status: status,
    title: title,
    uiConfigs: [uiConfig],
  ));
}
