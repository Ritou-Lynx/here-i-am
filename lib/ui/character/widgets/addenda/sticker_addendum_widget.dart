import 'package:flutter/material.dart';

/// Renders a sticker image attached to a chat message.
///
/// Sourced from the sticker addendum schema:
///   {"type": "sticker", "stickerId": "...", "assetPath": "...", "caption": "..."}
///
/// Displays the sticker at a fixed display size (128×128 logical px) with
/// rounded corners.  An optional caption appears below the image in a muted
/// style.  Unlike [ImageAddendumWidget], this renders from a bundled asset
/// path rather than base64-encoded bytes, so it is lightweight and instant.
class StickerAddendumWidget extends StatelessWidget {
  final Map<String, dynamic> data;
  final bool isCharacterBubble;

  const StickerAddendumWidget({
    super.key,
    required this.data,
    required this.isCharacterBubble,
  });

  static const double _stickerSize = 128;

  @override
  Widget build(BuildContext context) {
    final assetPath = data['assetPath'] as String?;
    if (assetPath == null || assetPath.isEmpty) {
      return const SizedBox.shrink();
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Image.asset(
        assetPath,
        width: _stickerSize,
        height: _stickerSize,
        fit: BoxFit.contain,
        gaplessPlayback: true,
        errorBuilder: (context, error, stackTrace) {
          debugPrint('StickerAddendumWidget: failed to load asset $assetPath: $error');
          return Container(
            width: _stickerSize,
            height: _stickerSize,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.image_not_supported_outlined,
              size: 40,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          );
        },
      ),
    );
  }
}
