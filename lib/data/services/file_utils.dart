import 'dart:convert';
import 'dart:io';
import 'api_exception.dart';

/// File handling utilities
class FileUtils {
  /// Convert file to base64
  static Future<String> fileToBase64(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        throw ApiException('File not found: $filePath');
      }
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) {
        throw ApiException('File is empty: $filePath');
      }
      return base64Encode(bytes);
    } catch (e) {
      if (e is ApiException) {
        rethrow;
      }
      throw ApiException('Failed to read file: ${e.toString()}');
    }
  }

  /// Get file extension
  static String getFileExtension(String path) {
    final parts = path.split('.');
    return parts.length > 1 ? parts.last.toLowerCase() : 'jpg';
  }

  /// Get MIME type by extension
  static String getMimeType(String extension) {
    switch (extension.toLowerCase()) {
      case 'png':
        return 'image/png';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'heic':
        return 'image/heic';
      case 'heif':
        return 'image/heif';
      case 'gif':
        return 'image/gif';
      case 'webp':
        return 'image/webp';
      case 'm4a':
        return 'audio/mp4';
      case 'mp3':
        return 'audio/mpeg';
      default:
        return 'image/jpeg';
    }
  }
}

