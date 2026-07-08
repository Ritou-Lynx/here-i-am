/// V3 Dreaming fragment extractor.
///
/// Pure analysis layer: assembles prompt context, calls the caller-supplied
/// LLM, and parses JSON into [DreamingFragmentExtraction]. Persistence lives in
/// services/dreaming_orchestrator_service.dart.
library;

import 'dart:convert';

import 'package:dart_agent_core/dart_agent_core.dart';
import 'package:memex/data/memory_v3/models/dreaming_fragment.dart';
import 'package:memex/utils/logger.dart';

import 'prompt.dart';

final _logger = getLogger('memory_v3.DreamingFragmentExtractor');

class DreamingChatMessageInput {
  DreamingChatMessageInput({
    required this.id,
    required this.isFromCharacter,
    required this.content,
    required this.timestamp,
    this.messageType = 'chat',
  });

  final int id;
  final bool isFromCharacter;
  final String content;
  final DateTime timestamp;
  final String messageType;

  Map<String, dynamic> toJson() => {
        'id': id,
        'speaker': isFromCharacter ? 'I' : 'user',
        'content': content,
        'timestamp': timestamp.toIso8601String(),
        'messageType': messageType,
      };
}

class DreamingFragmentExtractorV3 {
  const DreamingFragmentExtractorV3();

  Future<DreamingFragmentExtraction> extract({
    required LLMClient client,
    required ModelConfig modelConfig,
    required List<DreamingChatMessageInput> messages,
    required DateTime now,
    List<String> existingFragmentSummaries = const [],
  }) async {
    if (messages.isEmpty) {
      return DreamingFragmentExtraction(fragments: const []);
    }

    final payload = <String, dynamic>{
      'current_time': now.toIso8601String(),
      'messages': messages.map((m) => m.toJson()).toList(),
    };
    final systemPrompt = dreamingFragmentExtractorSystemPromptV3(
      existingFragmentSummaries: existingFragmentSummaries,
    );
    final requestMessages = [
      SystemMessage(systemPrompt),
      UserMessage([TextPart(jsonEncode(payload))]),
    ];
    final extra = Map<String, dynamic>.from(modelConfig.extra ?? {});
    extra['thinking'] = {'type': 'disabled'};
    final mc = ModelConfig(
      model: modelConfig.model,
      maxTokens: 8192,
      extra: extra,
    );

    final firstText =
        (await client.generate(requestMessages, modelConfig: mc)).textOutput;
    if (firstText == null || firstText.trim().isEmpty) {
      throw const FormatException(
          'Dreaming Fragment Extractor returned no output');
    }
    try {
      return _parse(firstText);
    } on FormatException catch (e) {
      final snippet =
          firstText.length > 300 ? firstText.substring(0, 300) : firstText;
      _logger.warning(
        'First parse failed ($e). Will retry. Raw (first 300): $snippet',
      );
    }

    final retryMessages = [
      SystemMessage(systemPrompt),
      UserMessage([
        TextPart(jsonEncode(payload)),
        TextPart(
          'STRICT: Reply with ONLY a single JSON object. '
          'No markdown fences, no commentary, no trailing comma. '
          'The first character must be "{".',
        ),
      ]),
    ];
    final retryText =
        (await client.generate(retryMessages, modelConfig: mc)).textOutput;
    if (retryText == null || retryText.trim().isEmpty) {
      throw const FormatException(
        'Dreaming Fragment Extractor retry returned no output',
      );
    }
    try {
      return _parse(retryText);
    } on FormatException {
      final snippet =
          retryText.length > 400 ? retryText.substring(0, 400) : retryText;
      _logger.severe(
        'Retry parse also failed. Raw output (first 400): $snippet',
      );
      throw FormatException(
        'Dreaming Fragment Extractor returned invalid JSON after retry. '
        'Raw response (first 400 chars):\n$snippet',
      );
    }
  }

  DreamingFragmentExtraction _parse(String raw) {
    var trimmed = raw.trim();
    trimmed = trimmed.replaceAll(RegExp(r'<think>[\s\S]*?</think>'), '');
    final unclosedThink = trimmed.indexOf('<think>');
    if (unclosedThink >= 0) {
      final braceAfter = trimmed.indexOf('{', unclosedThink);
      trimmed = braceAfter >= 0 ? trimmed.substring(braceAfter) : '';
    }

    var fenceMatch = RegExp(
      r'^```(?:json|JSON)?\s*\n([\s\S]*?)\n```\s*$',
    ).firstMatch(trimmed);
    fenceMatch ??= RegExp(
      r'```(?:json|JSON)?\s*\n([\s\S]*?)\n```',
    ).firstMatch(trimmed);
    if (fenceMatch != null) {
      trimmed = fenceMatch.group(1)!.trim();
    }

    final start = trimmed.indexOf('{');
    final end = trimmed.lastIndexOf('}');
    if (start < 0 || end <= start) {
      throw const FormatException(
        'Dreaming Fragment Extractor response contains no JSON',
      );
    }
    var jsonPart = trimmed.substring(start, end + 1);
    jsonPart = _repairLLMJson(jsonPart);
    final decoded = jsonDecode(jsonPart);
    if (decoded is! Map) {
      throw const FormatException(
        'Dreaming Fragment Extractor JSON root must be an object',
      );
    }
    return DreamingFragmentExtraction.fromJson(
      decoded.cast<String, dynamic>(),
    );
  }

  static String _repairLLMJson(String json) {
    var repaired = json.replaceAll(RegExp(r',(\s*[}\]])'), r'$1');
    repaired = repaired.replaceAll(',,', ',');
    repaired = _escapeRawCharsInStrings(repaired);
    return repaired;
  }

  static String _escapeRawCharsInStrings(String input) {
    final buf = StringBuffer();
    var inString = false;
    var prev = '';
    for (var i = 0; i < input.length; i++) {
      final ch = input[i];
      if (ch == '"' && prev != '\\') {
        inString = !inString;
        buf.write(ch);
      } else if (inString) {
        switch (ch) {
          case '\n':
            buf.write(r'\n');
            break;
          case '\r':
            buf.write(r'\r');
            break;
          case '\t':
            buf.write(r'\t');
            break;
          default:
            buf.write(ch);
        }
      } else {
        buf.write(ch);
      }
      prev = ch;
    }
    return buf.toString();
  }
}
