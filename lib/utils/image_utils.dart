import 'dart:io';
import 'dart:ui' as ui;
import 'package:memex/utils/logger.dart';

/// Image handling utilities
class ImageUtils {
  static final _logger = getLogger('ImageUtils');

  /// Get image dimensions (width, height, aspect ratio).
  /// Returns map: width, height (pixels, 0 on failure), aspectRatio (0.0 on failure).
  static Future<Map<String, dynamic>> getImageDimensions(
      String imagePath) async {
    int width = 0;
    int height = 0;
    double aspectRatio = 0.0;

    try {
      final file = File(imagePath);
      if (!await file.exists()) {
        _logger.warning("Image file not found: $imagePath");
        return {
          'width': width,
          'height': height,
          'aspectRatio': aspectRatio,
        };
      }

      final bytes = await file.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      width = frame.image.width;
      height = frame.image.height;
      aspectRatio = width / height;
      frame.image.dispose();
      codec.dispose();
    } catch (e) {
      _logger.warning('Failed to get image dimensions for $imagePath: $e');
    }

    return {
      'width': width,
      'height': height,
      'aspectRatio': aspectRatio,
    };
  }
}

