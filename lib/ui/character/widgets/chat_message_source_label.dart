import 'package:flutter/material.dart';
import 'package:memex/db/app_database.dart';

const Map<String, String> _knownChatSources = {
  'frontend:claude_web': 'Claude',
  'frontend:chatgpt_web': 'ChatGPT',
  'frontend:gemini_web': 'Gemini',
  'frontend:antigravity': 'Antigravity',
  'frontend:sesame': 'Sesame',
};

/// Resolves only exact, case-sensitive device provenance. Empty frontend IDs
/// have no usable source name and deliberately remain unlabelled.
String? chatSourceLabelFor(String? originDeviceId) {
  final known = _knownChatSources[originDeviceId];
  if (known != null) return known;
  if (originDeviceId != null &&
      originDeviceId.startsWith('frontend:') &&
      originDeviceId.length > 'frontend:'.length) {
    return '网页端';
  }
  return null;
}

/// Reuses the exact chat provenance mapping for other read-only replica views.
String? foodSourceLabelFor(String? originDeviceId) =>
    chatSourceLabelFor(originDeviceId);

/// Presentation-only provenance, kept outside message contents and selection.
class ChatMessageSourceLabel extends StatelessWidget {
  const ChatMessageSourceLabel({super.key, required this.message, this.color});

  final PersonaChatMessage message;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final label = chatSourceLabelFor(message.originDeviceId);
    if (label == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Align(
        alignment: message.isFromCharacter
            ? Alignment.centerLeft
            : Alignment.centerRight,
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: color ?? Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      ),
    );
  }
}
