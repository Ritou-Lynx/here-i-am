import 'dart:convert';
import 'dart:collection';

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
///
/// Uses [gaplessPlayback] so the image does not flash white/dark when the
/// widget rebuilds during list scrolling.  The decoded [Uint8List] is cached
/// in a static map keyed by a hash of the base64 string, so repeated builds
/// of the same message do not re-decode on the main thread.
class ImageAddendumWidget extends StatelessWidget {
  final Map<String, dynamic> data;

  const ImageAddendumWidget({super.key, required this.data});

  /// Small in-memory cache: base64-hash → decoded bytes.
  /// Bounded to [maxCacheEntries]; oldest entries are evicted.
  static const int maxCacheEntries = 40;
  static final LinkedHashMap<int, Uint8List> _bytesCache =
      LinkedHashMap<int, Uint8List>();

  static Uint8List _decode(String base64Str) {
    final key = base64Str.hashCode;
    final cached = _bytesCache[key];
    if (cached != null) {
      // Move to end (most-recently-used).
      _bytesCache.remove(key);
      _bytesCache[key] = cached;
      return cached;
    }
    final decoded = Uint8List.fromList(base64Decode(base64Str));
    _bytesCache[key] = decoded;
    if (_bytesCache.length > maxCacheEntries) {
      _bytesCache.remove(_bytesCache.keys.first);
    }
    return decoded;
  }

  @override
  Widget build(BuildContext context) {
    final base64Str = data['base64'] as String?;
    if (base64Str == null || base64Str.isEmpty) {
      return const SizedBox.shrink();
    }

    final Uint8List bytes;
    try {
      bytes = _decode(base64Str);
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
        gaplessPlayback: true,
        errorBuilder: (context, error, stackTrace) {
          debugPrint('ImageAddendumWidget: image decode error: $error');
          return Container(
            width: double.infinity,
            height: 120,
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: const Center(
              child: Icon(Icons.broken_image_outlined, size: 32),
            ),
          );
        },
      ),
    );
  }
}
