import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Renders a base64-encoded image attached to a chat message.
///
/// Sourced from the legacy image-only schema:
///   {"mimeType": "image/webp", "base64": "..."}
/// Or the v1 schema:
///   {"type": "image", "mimeType": "image/webp", "base64": "..."}
///
/// The visual output matches the previous inline-attachment rendering
/// (10px rounded corners, full-width cover) to avoid regressing existing
/// user-side image bubbles.
class ImageAddendumWidget extends StatelessWidget {
  final Map<String, dynamic> data;

  const ImageAddendumWidget({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    final base64Str = data['base64'] as String?;
    if (base64Str == null || base64Str.isEmpty) {
      return const SizedBox.shrink();
    }

    final Uint8List bytes;
    try {
      bytes = Uint8List.fromList(base64Decode(base64Str));
    } catch (e) {
      debugPrint('ImageAddendumWidget: failed to decode base64: $e');
      return const SizedBox.shrink();
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Image.memory(
        bytes,
        fit: BoxFit.cover,
        width: double.infinity,
      ),
    );
  }
}
