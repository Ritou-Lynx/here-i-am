library;

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:memex/domain/workbench_ai/context/context_envelope.dart';
import 'package:memex/domain/workbench_ai/search/workbench_search_contract.dart';

/// Converts an on-demand search response into the existing ContextEnvelope
/// recall contract. Search results remain untrusted content and keep stable
/// product references; no adapter payload is copied into the envelope.
abstract final class ContextSearchProjection {
  static List<ContextRecallSnippet> toRecallSnippets(
    WorkbenchSearchResponse response, {
    int maxSnippets = ContextEnvelopeLimits.maxRecallSnippets,
    int maxCharacters = 8000,
  }) {
    if (maxSnippets <= 0 ||
        maxSnippets > ContextEnvelopeLimits.maxRecallSnippets) {
      throw ArgumentError('maxSnippets exceeds ContextEnvelope limits');
    }
    if (maxCharacters <= 0 ||
        maxCharacters > ContextEnvelopeLimits.maxRecallCharacters) {
      throw ArgumentError('maxCharacters exceeds ContextEnvelope limits');
    }
    final snippets = <ContextRecallSnippet>[];
    var remaining = maxCharacters;
    for (final hit in response.hits) {
      if (snippets.length >= maxSnippets || remaining <= 0) break;
      final combined = '${hit.title}\n${hit.snippet}';
      final perItemLimit =
          remaining < ContextEnvelopeLimits.maxContentItemCharacters
              ? remaining
              : ContextEnvelopeLimits.maxContentItemCharacters;
      final content = _truncateCharacters(combined, perItemLimit);
      if (content.trim().isEmpty) continue;
      final digest = sha256
          .convert(utf8.encode('${response.trace.traceId}\n${hit.stableRef}'))
          .toString()
          .substring(0, 24);
      snippets.add(
        ContextRecallSnippet(
          recallId: 'search-$digest',
          sourceType: hit.objectType,
          sourceId: hit.stableRef,
          content: ContextText(
            text: content,
            trust: ContextTrust.untrustedContent,
          ),
          retrievedAt: hit.provenance.retrievedAt,
        ),
      );
      remaining -= content.length;
    }
    return List.unmodifiable(snippets);
  }
}

String _truncateCharacters(String value, int maxCharacters) {
  if (value.length <= maxCharacters) return value;
  if (maxCharacters == 1) return '…';
  final buffer = StringBuffer();
  for (final rune in value.runes) {
    final character = String.fromCharCode(rune);
    if (buffer.length + character.length > maxCharacters - 1) break;
    buffer.write(character);
  }
  return '${buffer.toString()}…';
}
