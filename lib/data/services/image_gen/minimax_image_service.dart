import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:memex/data/services/image_gen/image_gen_cache.dart';
import 'package:memex/data/services/image_gen/image_gen_provider.dart';
import 'package:memex/utils/user_storage.dart';

/// Image generation via MiniMax API.
class MiniMaxImageService {
  MiniMaxImageService._();

  static const _baseUrl = 'https://api.minimax.chat/v1/image_generation';
  static const _model = 'image-01';
  static const _timeout = Duration(seconds: 45);

  static final _dio = Dio(BaseOptions(
    connectTimeout: _timeout,
    receiveTimeout: _timeout,
  ));

  /// Maps our size string to MiniMax aspect_ratio format.
  static String _aspectRatio(String size) {
    switch (size) {
      case '1792x1024':
        return '16:9';
      case '1024x1792':
        return '9:16';
      default:
        return '1:1';
    }
  }

  static Future<ImageGenerationResult> generate(
    ImageGenerationRequest request,
  ) async {
    // 1. API key from existing MiniMax key
    final apiKey = await UserStorage.getMiniMaxApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      throw Exception(
        'No MiniMax API key found. '
        'Please configure a MiniMax API key in Settings.',
      );
    }

    // 2. Check cache
    final aspectR = _aspectRatio(request.size);
    final key = ImageGenCache.cacheKey(
      prompt: request.prompt,
      provider: 'minimax',
      model: _model,
      size: aspectR,
      style: request.style,
    );
    final cached = await ImageGenCache.lookup(key);
    if (cached != null) {
      debugPrint('[ImageGen] MiniMax cache HIT key=$key');
      final file = await File(cached).readAsBytes();
      return ImageGenerationResult(
        images: [Uint8List.sublistView(file)],
        providerModel: _model,
      );
    }

    // 3. Call API
    debugPrint('[ImageGen] MiniMax API call: model=$_model aspect_ratio=$aspectR');
    final body = {
      'model': _model,
      'prompt': request.prompt,
      'aspect_ratio': aspectR,
      'n': request.numImages,
      'prompt_optimizer': true,
    };

    final response = await _dio.post(
      _baseUrl,
      options: Options(
        headers: {
          'Authorization': 'Bearer $apiKey',
          'Content-Type': 'application/json',
        },
      ),
      data: jsonEncode(body),
    );

    final data = response.data as Map<String, dynamic>;
    debugPrint('[ImageGen] MiniMax raw response: ${jsonEncode(data).substring(0, 500)}');

    final baseResp = data['base_resp'] as Map<String, dynamic>?;
    if (baseResp != null) {
      final statusCode = baseResp['status_code'] as int? ?? 0;
      if (statusCode != 0) {
        final statusMsg = baseResp['status_msg'] ?? 'Unknown error';
        throw Exception('MiniMax error [$statusCode]: $statusMsg');
      }
    }

    // 4. Extract image data
    final imageUrls = data['data']?['image_urls'] as List?;
    if (imageUrls == null || imageUrls.isEmpty) {
      // Fallback: check alternative response shapes
      debugPrint('[ImageGen] MiniMax: no data.image_urls, raw keys: ${data.keys}');
      throw Exception('MiniMax returned no images. Response keys: ${data.keys}');
    }

    final images = <Uint8List>[];
    for (final url in imageUrls) {
      if (url is String) {
        // MiniMax may return base64-encoded images or URLs
        if (url.startsWith('http')) {
          debugPrint('[ImageGen] MiniMax downloading image from URL: ${url.substring(0, 80)}...');
          final imgResp = await _dio.get(
            url,
            options: Options(responseType: ResponseType.bytes),
          );
          images.add(Uint8List.fromList(imgResp.data as List<int>));
        } else {
          // Base64-encoded image
          debugPrint('[ImageGen] MiniMax decoding base64 image (${url.length} chars)');
          images.add(base64Decode(url));
        }
      }
    }

    if (images.isEmpty) {
      throw Exception('Failed to extract generated images');
    }

    // 5. Cache & return
    debugPrint('[ImageGen] MiniMax success: ${images.length} image(s), ${images.first.length} bytes each');
    for (final img in images) {
      await ImageGenCache.store(key, img);
    }
    return ImageGenerationResult(
      images: images,
      providerModel: _model,
    );
  }
}
