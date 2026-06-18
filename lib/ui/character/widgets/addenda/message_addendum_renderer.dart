import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'image_addendum_widget.dart';
import 'reading_card_addendum_widget.dart';

/// Renders the structured "addenda" attached to a chat message.
///
/// A message can carry zero or more addenda in [PersonaChatMessages.attachmentsJson].
/// Each addendum is a JSON object with a [type] discriminator field. Supported
/// types so far:
///
///   - `image`        — base64-encoded image (legacy: missing `type` ⇒ image)
///   - `reading_card` — a saved article preview (Reading Companion)
///
/// New addendum types should be added by:
///   1. Creating a dedicated widget under `lib/ui/character/widgets/addenda/`
///   2. Adding a `case` branch below.
///
/// Renders nothing (zero-height SizedBox) when [attachmentsJson] is null/empty
/// or cannot be parsed.
class MessageAddendumRenderer extends StatelessWidget {
  final String? attachmentsJson;

  /// True when this renders inside a character (assistant) bubble. Used by
  /// individual addendum widgets to pick palette / alignment.
  final bool isCharacterBubble;

  const MessageAddendumRenderer({
    super.key,
    required this.attachmentsJson,
    required this.isCharacterBubble,
  });

  @override
  Widget build(BuildContext context) {
    final json = attachmentsJson;
    if (json == null || json.isEmpty) return const SizedBox.shrink();

    final List<dynamic> raw;
    try {
      raw = jsonDecode(json) as List<dynamic>;
    } catch (e) {
      debugPrint('MessageAddendumRenderer: failed to decode attachments: $e');
      return const SizedBox.shrink();
    }
    if (raw.isEmpty) return const SizedBox.shrink();

    final widgets = <Widget>[];
    for (var i = 0; i < raw.length; i++) {
      final item = raw[i];
      if (item is! Map) continue;
      final map = Map<String, dynamic>.from(item);

      // Legacy compatibility: rows without a `type` field are images.
      final type = (map['type'] as String?) ?? 'image';

      final widget = _buildOne(type: type, data: map);
      if (widget == null) continue;

      if (widgets.isNotEmpty) {
        widgets.add(const SizedBox(height: 8));
      }
      widgets.add(widget);
    }

    if (widgets.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: isCharacterBubble
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: widgets,
    );
  }

  /// Dispatch a single addendum object to its dedicated widget.
  /// Returns null for unknown types so the renderer can silently skip them
  /// (forward compatibility: old client encounters a future addendum type).
  Widget? _buildOne({
    required String type,
    required Map<String, dynamic> data,
  }) {
    switch (type) {
      case 'image':
        return ImageAddendumWidget(data: data);
      case 'reading_card':
        return ReadingCardAddendumWidget(
          data: data,
          isCharacterBubble: isCharacterBubble,
        );
      default:
        debugPrint('MessageAddendumRenderer: unknown addendum type: $type');
        return null;
    }
  }
}
