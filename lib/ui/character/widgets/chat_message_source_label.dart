import 'package:flutter/material.dart';
import 'package:memex/db/app_database.dart';

/// Source is derived only from core provenance, never from message contents.
class ChatMessageSourceLabel extends StatelessWidget {
  const ChatMessageSourceLabel({super.key, required this.message, this.color});

  final PersonaChatMessage message;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    if (message.originDeviceId?.startsWith('frontend:') != true) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Align(
        alignment: message.isFromCharacter
            ? Alignment.centerLeft
            : Alignment.centerRight,
        child: Text(
          '网页端',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: color ?? Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      ),
    );
  }
}
