import 'dart:convert';
import 'dart:io';

import 'package:dart_agent_core/dart_agent_core.dart';
import 'package:memex/data/services/file_system_service.dart';

Future<AgentState> loadOrCreateAgentState(
  String sessionId,
  Map<String, dynamic>? initialMetadata,
) async {
  final userId = initialMetadata?['userId'] ?? 'mock_user_id';
  final stateDirPath = await FileSystemService.instance.getAgentStateDirectory(
    userId,
  );
  final stateDir = Directory(stateDirPath);
  final storage = FileStateStorage(stateDir);
  final state = await storage.loadOrCreate(sessionId, initialMetadata);
  var stateChanged = false;
  if (_repairLegacyAssistantContentBlocks(state)) stateChanged = true;
  if (_flattenPersistedToolCallTurns(state)) stateChanged = true;
  // Run orphan-strip BEFORE tool-only strip: a previous buggy run may have
  // already removed the ModelMessages, leaving FunctionExecutionResultMessages
  // with no corresponding tool_use block.
  if (_stripOrphanedToolResults(state)) stateChanged = true;
  if (_stripToolOnlyModelMessages(state)) stateChanged = true;
  if (stateChanged) {
    await storage.save(state);
  }
  return state;
}

Future<void> saveAgentState(AgentState state) async {
  final userId = state.metadata['userId'] ?? 'mock_user_id';
  final stateDirPath = await FileSystemService.instance.getAgentStateDirectory(
    userId,
  );
  final stateDir = Directory(stateDirPath);
  final storage = FileStateStorage(stateDir);
  await storage.save(state);
}

bool _repairLegacyAssistantContentBlocks(AgentState state) {
  var changed = false;
  final repairedMessages = <LLMMessage>[];

  for (final message in state.history.messages) {
    if (message is! ModelMessage) {
      repairedMessages.add(message);
      continue;
    }

    var repaired = message;
    if (repaired.contentBlocks.isEmpty &&
        repaired.thought != null &&
        repaired.thought!.isNotEmpty) {
      repaired = _withSynthesizedContentBlocks(repaired);
      changed = true;
    }

    if (_needsLegacyReasoningContentPlaceholder(repaired)) {
      repaired = _withReasoningContentPlaceholder(repaired);
      changed = true;
    }

    repairedMessages.add(repaired);
  }

  if (changed) {
    state.history.messages = repairedMessages;
  }
  return changed;
}

/// Persisted tool-call turns are risky across providers/proxies: a later API
/// call must preserve the exact assistant tool_calls -> tool result adjacency.
/// If an interrupted run or older sanitizer leaves that sequence malformed, the
/// next request fails before the model can answer. Keep any visible assistant
/// text, but drop protocol-level tool calls and their following results.
bool _flattenPersistedToolCallTurns(AgentState state) {
  final messages = state.history.messages;
  final repairedMessages = <LLMMessage>[];
  var changed = false;
  var skipFollowingToolResults = false;

  for (final message in messages) {
    if (skipFollowingToolResults && message is FunctionExecutionResultMessage) {
      changed = true;
      continue;
    }
    skipFollowingToolResults = false;

    if (message is ModelMessage && message.functionCalls.isNotEmpty) {
      changed = true;
      skipFollowingToolResults = true;

      final text = message.textOutput;
      if (text != null && text.trim().isNotEmpty) {
        repairedMessages.add(
          _copyModelMessage(
            message,
            contentBlocks: _contentBlocksWithoutToolUse(message),
            functionCalls: const [],
          ),
        );
      }
      continue;
    }

    repairedMessages.add(message);
  }

  if (changed) {
    state.history.messages = repairedMessages;
  }
  return changed;
}

/// Strip FunctionExecutionResultMessages that have no preceding ModelMessage
/// with tool calls — i.e. they are "orphaned" because the ModelMessage that
/// generated them was previously stripped (e.g. by an earlier buggy run of
/// _stripToolOnlyModelMessages that used the wrong class check).
///
/// A result message is orphaned when the nearest preceding non-result message
/// is NOT a ModelMessage. We walk backwards through consecutive result blocks;
/// if the block is not anchored by a ModelMessage, the whole block is stripped.
bool _stripOrphanedToolResults(AgentState state) {
  final messages = state.history.messages;
  final toRemove = <int>{};

  for (int i = 0; i < messages.length; i++) {
    final msg = messages[i];
    if (msg is! FunctionExecutionResultMessage) continue;

    // Walk backwards past any consecutive FunctionExecutionResultMessages.
    int j = i - 1;
    while (j >= 0 && messages[j] is FunctionExecutionResultMessage) {
      j--;
    }

    // If nothing precedes this block, or the anchor is not a ModelMessage with
    // tool calls, the result block is orphaned from the API protocol's point
    // of view. A plain assistant text before a tool result is still invalid.
    if (j < 0 ||
        messages[j] is! ModelMessage ||
        (messages[j] as ModelMessage).functionCalls.isEmpty) {
      toRemove.add(i);
    }
  }

  if (toRemove.isEmpty) return false;

  state.history.messages = [
    for (int i = 0; i < messages.length; i++)
      if (!toRemove.contains(i)) messages[i],
  ];
  return true;
}

/// Remove ModelMessage turns that have tool calls but zero text output,
/// together with all immediately-following FunctionExecutionResultMessages.
///
/// When the LLM produces tool-only turns (no spoken text) and those turns get
/// persisted, the next run sees them as examples and repeats the pattern.
/// Stripping them on load prevents the "call tool → empty → loopDetection" cycle.
///
/// The FunctionExecutionResultMessage(s) MUST also be removed: leaving them
/// orphaned causes an Anthropic API validation error (tool_result with no
/// matching tool_use_id in context).
///
/// We keep turns that have BOTH tool calls AND text — those are legitimate
/// agentic turns (e.g. "Let me check your memories *calls MemoryRead*").
bool _stripToolOnlyModelMessages(AgentState state) {
  final messages = state.history.messages;
  final toRemove = <int>{};

  for (int i = 0; i < messages.length; i++) {
    final msg = messages[i];
    if (msg is! ModelMessage) continue;

    final hasText = msg.textOutput != null && msg.textOutput!.trim().isNotEmpty;
    final hasToolCalls = msg.functionCalls.isNotEmpty;

    // A tool-only turn: tool calls with no spoken text output.
    if (hasToolCalls && !hasText) {
      toRemove.add(i);
      // Also strip all immediately-following FunctionExecutionResultMessages
      // (tool results for this turn). Multiple results may be stored as
      // separate messages. Leaving any of them orphaned causes an API 400.
      int j = i + 1;
      while (j < messages.length &&
          messages[j] is FunctionExecutionResultMessage) {
        toRemove.add(j);
        j++;
      }
    }
  }

  if (toRemove.isEmpty) return false;

  state.history.messages = [
    for (int i = 0; i < messages.length; i++)
      if (!toRemove.contains(i)) messages[i],
  ];
  return true;
}

bool _needsLegacyReasoningContentPlaceholder(ModelMessage message) {
  if (message.thought != null) return false;
  if (message.functionCalls.isEmpty) return false;

  final model = message.model.toLowerCase();
  return model.contains('deepseek-v4');
}

ModelMessage _withReasoningContentPlaceholder(ModelMessage message) {
  // Old interrupted DeepSeek V4 tool-call turns may have lost
  // reasoning_content. We cannot reconstruct it, but a present field unblocks
  // the next API call; fresh turns keep the real reasoning_content.
  return _copyModelMessage(message, thought: ' ');
}

ModelMessage _withSynthesizedContentBlocks(ModelMessage message) {
  final contentBlocks = <Map<String, dynamic>>[
    {
      'type': 'thinking',
      'thinking': message.thought,
      if (message.thoughtSignature != null)
        'signature': message.thoughtSignature,
    },
  ];

  if (message.textOutput != null && message.textOutput!.isNotEmpty) {
    contentBlocks.add({'type': 'text', 'text': message.textOutput});
  }

  for (final call in message.functionCalls) {
    if (call.id.isEmpty) continue;
    contentBlocks.add({
      'type': 'tool_use',
      'id': call.id,
      'name': call.name,
      'input': _decodeToolInput(call.arguments),
    });
  }

  return _copyModelMessage(message, contentBlocks: contentBlocks);
}

List<Map<String, dynamic>> _contentBlocksWithoutToolUse(ModelMessage message) {
  final blocks = [
    for (final block in message.contentBlocks)
      if (block['type'] != 'tool_use') Map<String, dynamic>.from(block),
  ];
  final hasTextBlock = blocks.any((block) => block['type'] == 'text');
  if (!hasTextBlock &&
      message.textOutput != null &&
      message.textOutput!.trim().isNotEmpty) {
    blocks.add({'type': 'text', 'text': message.textOutput});
  }
  return blocks;
}

ModelMessage _copyModelMessage(
  ModelMessage message, {
  String? thought,
  List<Map<String, dynamic>>? contentBlocks,
  List<FunctionCall>? functionCalls,
}) {
  return ModelMessage(
    thought: thought ?? message.thought,
    thoughtSignature: message.thoughtSignature,
    contentBlocks: contentBlocks ?? message.contentBlocks,
    functionCalls: functionCalls ?? message.functionCalls,
    textOutput: message.textOutput,
    imageOutputs: message.imageOutputs,
    videoOutputs: message.videoOutputs,
    audioOutputs: message.audioOutputs,
    usage: message.usage,
    metadata: message.metadata,
    stopReason: message.stopReason,
    model: message.model,
    responseId: message.responseId,
    timestamp: message.timestamp,
  );
}

dynamic _decodeToolInput(String arguments) {
  if (arguments.isEmpty) {
    return {};
  }
  try {
    return jsonDecode(arguments);
  } catch (_) {
    return {};
  }
}

Future<void> deleteAgentState(String userId, String sessionId) async {
  final stateDirPath = await FileSystemService.instance.getAgentStateDirectory(
    userId,
  );
  final stateDir = Directory(stateDirPath);
  final storage = FileStateStorage(stateDir);
  await storage.delete(sessionId);
}

/// Resolve the session ID for a character agent.
///
/// Strategy:
/// - Look for existing state files matching `prefix_N` pattern.
/// - If the latest one is still running (interrupted), return it for resume.
/// - Otherwise, return a new ID with incremented sequence number.
///
/// Returns `(sessionId, isExisting)` — if `isExisting` is true, the caller
/// should attempt resume; otherwise it's a fresh session.
Future<({String sessionId, bool isExisting})> resolveCharacterSessionId({
  required String prefix,
  required String userId,
}) async {
  final stateDirPath = await FileSystemService.instance.getAgentStateDirectory(
    userId,
  );
  final stateDir = Directory(stateDirPath);
  if (!await stateDir.exists()) {
    return (sessionId: '${prefix}_1', isExisting: false);
  }

  // List state files matching the prefix pattern.
  final entities = await stateDir.list().toList();
  int maxSeq = 0;
  String? latestFile;
  for (final entity in entities) {
    if (entity is! File) continue;
    final name = entity.uri.pathSegments.last.replaceAll('.json', '');
    if (!name.startsWith('${prefix}_')) continue;
    final suffix = name.substring(prefix.length + 1);
    final seq = int.tryParse(suffix);
    if (seq != null && seq > maxSeq) {
      maxSeq = seq;
      latestFile = name;
    }
  }

  if (latestFile == null) {
    return (sessionId: '${prefix}_1', isExisting: false);
  }

  // Check if the latest session is still running (interrupted).
  final storage = FileStateStorage(stateDir);
  try {
    final state = await storage.loadOrCreate(latestFile, null);
    if (state.isRunning) {
      return (sessionId: latestFile, isExisting: true);
    }
  } catch (_) {
    // Corrupted state file — skip it.
  }

  // Latest session completed; create next one.
  return (sessionId: '${prefix}_${maxSeq + 1}', isExisting: false);
}
