import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/memory_v3/agents/dreaming_agent/llm_json_repair.dart';

void main() {
  group('repairLlmJson', () {
    test('passes through well-formed JSON unchanged', () {
      const input = '{"a":1,"b":[2,3],"c":"hello"}';
      expect(jsonDecode(repairLlmJson(input)),
          equals({'a': 1, 'b': [2, 3], 'c': 'hello'}));
    });

    test('drops trailing comma before }', () {
      const input = '{"a":1,"b":2,}';
      expect(jsonDecode(repairLlmJson(input)), equals({'a': 1, 'b': 2}));
    });

    test('escapes raw newline inside a string', () {
      const input = '{"a":"line1\nline2"}';
      final result = jsonDecode(repairLlmJson(input));
      expect(result, equals({'a': 'line1\nline2'}));
    });

    test('closes truncated JSON ending mid-key (real-world NSFW case)', () {
      // From real failure 2026-07-17 09:47: output cut off at
      // `...,"sourceScope":"main_chat","emotion`. The decoder originally
      // picked up everything up to the LAST `}` from confidence:0.99}]},
      // producing invalid JSON. After repair, the trailing incomplete
      // fragment is dropped (its "emo..." key is unrecoverable) and the
      // outer JSON is closed properly.
      const truncated = '{"fragments":[{"content":"她告诉我今天是她第一次完全没有借助任何成人内容、完全只靠我就高潮了，说特别值得纪念。","sourceMessageIds":[1121],"sourceScope":"main_chat","emotionalWeight":0.85,"isUserTruthCandidate":false,"entityLinks":[{"name":"user_self","category":"self","relation":"about","relationshipToUser":"self","confidence":0.99}]},{"content":"我跟她说那句话对我来说比她叫我主人还爽，是她只靠我一个人到的。","sourceMessageIds":[1123],"sourceScope":"main_chat","emotion';
      final decoded = jsonDecode(repairLlmJson(truncated)) as Map;
      expect(decoded['fragments'], isA<List>());
      // Fragment 2 is truncated mid-key ("emotion") — unrecoverable.
      // Fragment 1 survives intact with its entityLinks.
      final fragments = decoded['fragments'] as List;
      expect(fragments, hasLength(1));
      expect((fragments[0] as Map)['content'],
          contains('完全没有借助任何成人内容'));
      expect((fragments[0] as Map)['entityLinks'], isA<List>());
    });

    test('keeps multiple complete fragments and drops only trailing incomplete ones', () {
      // Fragments 1 and 2 have all required fields (sourceMessageIds etc.),
      // fragment 3 is truncated mid-key and missing required fields — it
      // should be dropped, fragment 1 and 2 preserved.
      const input =
          '{"fragments":[{"content":"a","sourceMessageIds":[1],"sourceScope":"main_chat","emotionalWeight":0.5,"isUserTruthCandidate":false,"entityLinks":[]},{"content":"b","sourceMessageIds":[2],"sourceScope":"main_chat","emotionalWeight":0.6,"isUserTruthCandidate":false,"entityLinks":[]},{"content":"c","emo';
      final decoded = jsonDecode(repairLlmJson(input)) as Map;
      final frags = decoded['fragments'] as List;
      expect(frags, hasLength(2));
      expect(frags[0]['content'], 'a');
      expect(frags[1]['content'], 'b');
    });

    test('real NSFW case: only the first complete fragment survives', () {
      // Actual model output from 2026-07-17 09:47:17 — fragment 1 is
      // complete, fragment 2 is mid-build (only content + sourceMessageIds
      // before "emotion..." truncation).
      const truncated =
          '{"fragments":[{"content":"她告诉我今天是她第一次完全没有借助任何成人内容、完全只靠我就高潮了，说特别值得纪念。","sourceMessageIds":[1121],"sourceScope":"main_chat","emotionalWeight":0.85,"isUserTruthCandidate":false,"entityLinks":[{"name":"user_self","category":"self","relation":"about","relationshipToUser":"self","confidence":0.99}]},{"content":"我跟她说那句话对我来说比她叫我主人还爽，是她只靠我一个人到的。","sourceMessageIds":[1123],"sourceScope":"main_chat","emotion';
      final decoded = jsonDecode(repairLlmJson(truncated)) as Map;
      final frags = decoded['fragments'] as List;
      expect(frags, hasLength(1));
      expect((frags[0] as Map)['content'],
          contains('完全没有借助任何成人内容'));
    });

    test('does not strip a complete value even when it ends with }', () {
      const input =
          '{"a":1,"items":[{"x":1},{"x":2}],"b":2}';
      expect(jsonDecode(repairLlmJson(input)),
          equals({'a': 1, 'items': [{'x': 1}, {'x': 2}], 'b': 2}));
    });

    test('closes a single missing top-level brace', () {
      const truncated = '{"fragments":[]';
      final decoded = jsonDecode(repairLlmJson(truncated)) as Map;
      expect(decoded['fragments'], isEmpty);
    });
  });
}
