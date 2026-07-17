/// Shared JSON repair helpers used by Dreaming agents to salvage LLM
/// output that is malformed due to truncation, content-filter stops, or
/// common formatting drift. Kept here so fragment_extractor and
/// episode_consolidator use the same logic.
library;

import 'dart:convert';

/// Strip trailing commas / double commas / unescaped newlines-in-strings,
/// then close any unclosed `]` / `}` left by a truncated response and
/// drop any trailing incomplete key-value tail. The result is still
/// passed through jsonDecode, so if bracket tracking is itself wrong,
/// the decode will throw the original FormatException — no silent
/// data corruption.
String repairLlmJson(String json) {
  // Use replaceAllMapped so $1 is a real backreference, not a literal.
  var repaired = json.replaceAllMapped(
      RegExp(r',(\s*[}\]])'), (m) => m.group(1)!);
  repaired = repaired.replaceAll(',,', ',');
  repaired = _escapeRawCharsInStrings(repaired);
  repaired = closeTruncatedJson(repaired);
  return repaired;
}

/// Repair JSON whose output was truncated. Finds the longest valid prefix
/// (left-to-right jsonDecode trial) and appends whatever closing `]` / `}`
/// keep it balanced.
///
/// After finding the longest parseable prefix, applies a Dreaming-specific
/// sanity check: if the recovered JSON is a `{"fragments": [...]}` payload,
/// drop any fragment that is missing required fields (it's an incomplete
/// trailing fragment from a content-filter stop) and re-close brackets
/// until the result is the LONGEST prefix containing only complete
/// fragments. Other JSON shapes fall through unchanged.
///
/// O(n) where n is the number of close brackets. Each close position gets
/// at most one jsonDecode attempt; with n typically in the dozens, this
/// is fast enough.
String closeTruncatedJson(String input) {
  // Quick win: if the input already parses as-is, run the sanity check
  // and return.
  try {
    jsonDecode(input);
    return _dropIncompleteFragments(input);
  } catch (_) {}

  // Append the missing closers for the FULL input. Sometimes the model
  // outputs everything but forgets the trailing `]}` — appending them
  // gives a recoverable JSON.
  String closeFrom(int endExclusive) {
    final prefix = input.substring(0, endExclusive);
    // Strip trailing whitespace / `,` / `:` so the appended closers
    // don't produce `,"]}`.
    var cleaned = prefix;
    while (cleaned.isNotEmpty &&
        (cleaned.endsWith(',') ||
            cleaned.endsWith(':') ||
            cleaned.endsWith(' ') ||
            cleaned.endsWith('\n') ||
            cleaned.endsWith('\r'))) {
      cleaned = cleaned.substring(0, cleaned.length - 1);
    }
    final closings = _unclosedBrackets(cleaned);
    return cleaned + closings;
  }

  String sanitizeCandidate(String candidate) {
    try {
      final sanitized = _dropIncompleteFragments(candidate);
      jsonDecode(sanitized);
      return sanitized;
    } catch (_) {
      return candidate;
    }
  }

  // Try the full input first.
  final candidate0 = closeFrom(input.length);
  final sanitized0 = sanitizeCandidate(candidate0);
  try {
    jsonDecode(sanitized0);
    return sanitized0;
  } catch (_) {}

  // Build position list: every position right after a `,` `}` `]` is a
  // candidate truncate point. Try right-to-left so we find the LONGEST
  // valid prefix.
  final positions = <int>[];
  for (var i = input.length - 1; i >= 0; i--) {
    final c = input[i];
    if (c == ',' || c == '}' || c == ']') {
      positions.add(i + 1);
    }
  }

  for (final pos in positions) {
    if (pos <= 0 || pos > input.length) continue;
    final candidate = closeFrom(pos);
    final sanitized = sanitizeCandidate(candidate);
    try {
      jsonDecode(sanitized);
      // Return the input prefix (not the appended candidate). If we
      // dropped incomplete fragments, the original input prefix includes
      // them, but the sanitized output does NOT — so we return the
      // sanitized form so consumers see only complete data.
      return sanitized;
    } catch (_) {
      // try next position
    }
  }

  // Couldn't find any valid prefix. Return the best-effort sanitized full
  // input (with unclosed brackets appended and incomplete fragments
  // dropped).
  return sanitized0;
}

/// Compute which closing brackets are needed to balance `input`.
String _unclosedBrackets(String input) {
  final closings = <String>[];
  var inString = false;
  var prev = '';
  for (var i = 0; i < input.length; i++) {
    final ch = input[i];
    if (ch == '"' && prev != '\\') {
      inString = !inString;
    } else if (!inString) {
      if (ch == '{') {
        closings.add('}');
      } else if (ch == '[') {
        closings.add(']');
      } else if (ch == '}' || ch == ']') {
        if (closings.isNotEmpty &&
            closings.last == (ch == '}' ? '}' : ']')) {
          closings.removeLast();
        }
      }
    }
    prev = ch;
  }
  return closings.reversed.join();
}

/// Required fields for a Dreaming fragment. If any of these is missing
/// the fragment was truncated mid-build (e.g. content-filter stopped the
/// model mid-way through emitting it) and must be dropped to avoid
/// silent partial persistence.
const _requiredFragmentKeys = [
  'content',
  'sourceMessageIds',
  'sourceScope',
  'emotionalWeight',
  'isUserTruthCandidate',
  'entityLinks',
];

/// If `json` is a `{"fragments": [...]}` payload, drop any fragment that
/// is missing a required field and re-close brackets so the result is
/// the shortest valid prefix. Returns `json` unchanged if it doesn't
/// match the fragment shape or is too malformed to safely mutate.
String _dropIncompleteFragments(String json) {
  Map<String, dynamic> parsed;
  try {
    parsed = jsonDecode(json) as Map<String, dynamic>;
  } catch (_) {
    return json;
  }
  final fragments = parsed['fragments'];
  if (fragments is! List) return json;
  final complete = fragments.where((f) {
    if (f is! Map) return false;
    for (final key in _requiredFragmentKeys) {
      if (!f.containsKey(key)) return false;
    }
    return true;
  }).toList();

  if (complete.length == fragments.length) {
    // Nothing to drop — return the input untouched to preserve formatting.
    return json;
  }

  // Build a new minimal JSON containing only complete fragments. Use the
  // original text as the source of truth, but mutate the fragments list.
  // We can't safely reparse-then-re-encode (would change whitespace /
  // original formatting), so we just return the input untouched if we
  // can't surgically edit it. The downstream parser will defensively
  // skip fragments with missing required fields, so dropping isn't
  // strictly required for correctness. We do drop via the parser path
  // in DreamingFragmentExtraction.fromJson, but that only drops
  // empty-content fragments. To drop mid-build fragments we need to
  // do it HERE.
  //
  // To keep this simple, re-encode from the parsed map.
  return jsonEncode({'fragments': complete});
}

String _escapeRawCharsInStrings(String input) {
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
