import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _readSource(String relativePath) {
  final file = File(relativePath);
  expect(
    file.existsSync(),
    isTrue,
    reason: 'Missing expected source file: $relativePath',
  );
  return file.readAsStringSync();
}

void main() {
  group('Critical fixes guard', () {
    test('Fix 1: chat input stays enabled during AI streaming', () {
      const path = 'lib/ui/character/widgets/persona_chat_screen.dart';
      const marker = 'Input stays enabled during streaming';
      final content = _readSource(path);

      expect(
        content.contains(marker),
        isTrue,
        reason:
            '$path is missing "$marker" '
            '(TextField must NOT have enabled: !isStreaming).',
      );
    });

    test('Fix 2: sleep date semantics (WAKE-UP date) in agent prompts', () {
      const files = [
        'lib/agent/built_in_tools/coros_mcp_tool.dart',
        'lib/agent/skills/companion_agent/companion_agent_skill.dart',
        'lib/agent/companion_agent/companion_agent.dart',
      ];
      final pattern = RegExp(r'WAKE-UP date|wake-up date|睡眠数据');

      for (final path in files) {
        final content = _readSource(path);
        expect(
          pattern.hasMatch(content),
          isTrue,
          reason:
              '$path is missing sleep date semantics guidance '
              '(expected pattern: WAKE-UP date|wake-up date|睡眠数据).',
        );
      }
    });

    test('Fix 3: health_strategies.dart documents WAKE UP (dateTo) design', () {
      const path = 'lib/data/services/health_strategies.dart';
      const marker = 'WAKE UP (dateTo)';
      final content = _readSource(path);

      expect(
        content.contains(marker),
        isTrue,
        reason:
            '$path is missing "$marker" '
            '(_aggregateSleep must document why it uses dateTo / wake-up date).',
      );
    });
  });
}
