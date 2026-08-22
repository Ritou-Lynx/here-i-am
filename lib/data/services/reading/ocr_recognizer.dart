import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

enum OcrAvailability { available, unavailable, failed }

class OcrRecognition {
  const OcrRecognition({
    required this.availability,
    this.text = '',
    this.confidence,
    this.reason,
    required this.recognizerVersion,
  });

  const OcrRecognition.unavailable({
    this.reason = 'OCR is unavailable on this platform',
    this.recognizerVersion = 'unavailable',
  })  : availability = OcrAvailability.unavailable,
        text = '',
        confidence = null;

  final OcrAvailability availability;
  final String text;
  final double? confidence;
  final String? reason;
  final String recognizerVersion;
}

/// Device-independent OCR boundary. Tests inject a fixture recognizer and do
/// not initialize platform channels or ML Kit.
abstract class OcrRecognizer {
  Future<OcrRecognition> recognize(String imagePath);
}

class MlKitChineseOcrRecognizer implements OcrRecognizer {
  const MlKitChineseOcrRecognizer();

  static const version = 'google-mlkit-chinese-v1';

  @override
  Future<OcrRecognition> recognize(String imagePath) async {
    final recognizer = TextRecognizer(script: TextRecognitionScript.chinese);
    try {
      final recognised = await recognizer.processImage(
        InputImage.fromFilePath(imagePath),
      );
      final text = recognised.blocks
          .map((block) => block.text.trim())
          .where((value) => value.isNotEmpty)
          .join('\n');
      // ML Kit's Flutter text-recognition API does not expose a calibrated
      // confidence for text blocks. Keep it null rather than inventing one.
      return OcrRecognition(
        availability: OcrAvailability.available,
        text: text,
        recognizerVersion: version,
      );
    } on UnsupportedError catch (error) {
      return OcrRecognition.unavailable(
        reason: error.toString(),
        recognizerVersion: version,
      );
    } catch (error) {
      final message = error.toString();
      final unavailable = message.contains('MissingPluginException') ||
          message.contains('not implemented') ||
          message.contains('unsupported');
      if (unavailable) {
        return OcrRecognition.unavailable(
          reason: message,
          recognizerVersion: version,
        );
      }
      return OcrRecognition(
        availability: OcrAvailability.failed,
        reason: message,
        recognizerVersion: version,
      );
    } finally {
      try {
        await recognizer.close();
      } catch (_) {
        // Closing an unavailable platform channel must not replace the
        // explicit unavailable/failed result produced above.
      }
    }
  }
}
