/// Agent System Prompt Helper
///
/// Load agent custom prompt config from workspace/_user_id/_UserSettings/prompts/.
/// Config file name is {agent_name}.conf, supporting:
///
/// 1. System Prompt:
///    - Override mode: replace the entire system_prompt
///    - Replace mode: replace specified strings in system_prompt (supports multiline)
///
/// 2. Tool:
///    - Match tools by name, override description and/or parameters
///
/// Config format: see doc comments in Python agent_system_prompt_helper.py.

import 'dart:convert';
import 'dart:io';

import 'package:dart_agent_core/dart_agent_core.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as path;

import 'package:memex/data/services/file_system_service.dart';

final _logger = Logger('AgentSystemPromptHelper');

const _tagPrefix = '@@#CONF#';

class SystemPromptConfig {
  String? overrideContent;
  final List<(String, String)> replacements = []; // [(old, new)]
}

class ToolOverride {
  final String name;
  final String? description;
  final Map<String, dynamic>? parameters;

  ToolOverride({required this.name, this.description, this.parameters});
}

class AgentPromptConfig {
  final SystemPromptConfig systemPrompt = SystemPromptConfig();
  final Map<String, ToolOverride> toolOverrides = {};
}

/// Extract content from lines[start] up to (but not including) the endTag line.
/// Returns (content, nextLineIndex).
(String, int) _extractBlock(List<String> lines, int start, String endTag) {
  final blockLines = <String>[];
  var i = start;
  while (i < lines.length) {
    if (lines[i].trim() == endTag) {
      i++;
      break;
    }
    blockLines.add(lines[i]);
    i++;
  }
  final content = blockLines.join('\n');
  // trim leading/trailing blank lines
  final trimmed = content.replaceAll(RegExp(r'^\n+'), '').replaceAll(RegExp(r'\n+$'), '');
  return (trimmed, i);
}

AgentPromptConfig _parseConfig(String content) {
  final config = AgentPromptConfig();
  final lines = content.split('\n');
  var i = 0;
  final p = _tagPrefix;

  while (i < lines.length) {
    final line = lines[i].trim();

    if (line == '$p[system_prompt:override]') {
      i++;
      final (block, nextI) = _extractBlock(lines, i, '$p[/system_prompt:override]');
      i = nextI;
      config.systemPrompt.overrideContent = block;
    } else if (line == '$p[system_prompt:replace]') {
      i++;
      String? oldText;
      String? newText;
      while (i < lines.length) {
        final inner = lines[i].trim();
        if (inner == '$p[/system_prompt:replace]') {
          i++;
          break;
        } else if (inner == '$p[old]') {
          i++;
          final (block, nextI) = _extractBlock(lines, i, '$p[/old]');
          i = nextI;
          oldText = block;
        } else if (inner == '$p[new]') {
          i++;
          final (block, nextI) = _extractBlock(lines, i, '$p[/new]');
          i = nextI;
          newText = block;
        } else {
          i++;
        }
      }
      if (oldText != null && newText != null) {
        config.systemPrompt.replacements.add((oldText, newText));
      }
    } else if (line.startsWith('$p[tool:') && line.endsWith(']') && !line.startsWith('$p[/')) {
      final toolName = line.substring('$p[tool:'.length, line.length - 1);
      final endTag = '$p[/tool:$toolName]';
      i++;
      final (jsonBlock, nextI) = _extractBlock(lines, i, endTag);
      i = nextI;
      if (jsonBlock.isNotEmpty) {
        try {
          final data = jsonDecode(jsonBlock) as Map<String, dynamic>;
          config.toolOverrides[toolName] = ToolOverride(
            name: toolName,
            description: data['description'] as String?,
            parameters: data['parameters'] as Map<String, dynamic>?,
          );
        } catch (e) {
          _logger.warning('Failed to parse tool override JSON for "$toolName": $e');
        }
      }
    } else {
      i++;
    }
  }

  return config;
}

String _getConfigPath(String userId, String agentName) {
  final settingsPath = FileSystemService.instance.getUserSettingsPath(userId);
  return path.join(settingsPath, 'prompts', '$agentName.conf');
}

Future<AgentPromptConfig?> loadAgentPromptConfig(String userId, String agentName) async {
  final configPath = _getConfigPath(userId, agentName);
  final file = File(configPath);
  if (!await file.exists()) return null;
  try {
    final content = await file.readAsString();
    return _parseConfig(content);
  } catch (e) {
    _logger.severe('Failed to load agent prompt config from $configPath: $e');
    return null;
  }
}

(SystemMessage?, List<Tool>, List<LLMMessage>) applyPromptConfig(
  AgentPromptConfig config,
  SystemMessage? systemMessage,
  List<Tool> tools,
  List<LLMMessage> requestMessages,
) {
  var newSystemMessage = systemMessage;
  var newTools = List<Tool>.from(tools);
  var newRequestMessages = List<LLMMessage>.from(requestMessages);

  final spConfig = config.systemPrompt;

  if (spConfig.overrideContent != null) {
    newSystemMessage = SystemMessage(spConfig.overrideContent!);
  } else if (spConfig.replacements.isNotEmpty) {
    if (newSystemMessage != null) {
      var newContent = newSystemMessage.content;
      for (final (oldStr, newStr) in spConfig.replacements) {
        newContent = newContent.replaceAll(oldStr, newStr);
      }
      newSystemMessage = SystemMessage(newContent);
    }
  }

  if (config.toolOverrides.isNotEmpty) {
    for (var idx = 0; idx < newTools.length; idx++) {
      final override = config.toolOverrides[newTools[idx].name];
      if (override != null) {
        newTools[idx] = Tool(
          name: newTools[idx].name,
          description: override.description ?? newTools[idx].description,
          parameters: override.parameters ?? newTools[idx].parameters,
          executable: newTools[idx].executable,
          namedParameters: newTools[idx].namedParameters,
        );
      }
    }
  }

  return (newSystemMessage, newTools, newRequestMessages);
}

/// Create a systemCallback to pass to StatefulAgent.
/// user_id is captured by closure; agent_name is taken from agent.name at callback time.
///
/// Usage: StatefulAgent(..., systemCallback: createSystemCallback(userId))
SystemCallback createSystemCallback(String userId) {
  return (StatefulAgent agent, SystemMessage? systemMessage, List<Tool> tools,
      List<LLMMessage> requestMessages) async {
    final config = await loadAgentPromptConfig(userId, agent.name);
    if (config == null) {
      return (systemMessage, tools, requestMessages);
    }
    return applyPromptConfig(config, systemMessage, tools, requestMessages);
  };
}
