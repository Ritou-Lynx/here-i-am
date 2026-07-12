import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:memex/data/services/image_gen/image_gen_cache.dart';
import 'package:memex/data/services/image_gen/image_gen_provider.dart';
import 'package:memex/utils/user_storage.dart';

/// Image generation via any OpenAI-compatible /v1/images/generations endpoint.
/// Covers relay-proxied Grok, DALL-E, and future compatible providers.
class OpenAICompatibleImageService {
  OpenAICompatibleImageService._();

  static const _timeout = Duration(seconds: 60);

  static final _dio = Dio(BaseOptions(
    connectTimeout: _timeout,
    receiveTimeout: _timeout,
  ));

  static Future<ImageGenerationResult> generate(
    ImageGenerationRequest request,
  ) async {
    // Read which LLMConfig entry to use
    final configKey = await UserStorage.getImageGenLlmConfigKey();
    if (configKey == null || configKey.isEmpty) {
      throw Exception(
        'No model config selected for image generation. '
        'Please select a config in Settings → Image Generation.',
      );
    }

    final configs = await UserStorage.getLLMConfigs();
    final config = configs.firstWhere(
      (c) => c.key == configKey,
      orElse: () => throw Exception('LLM config "$configKey" not found.'),
    );

    if (config.apiKey.isEmpty) {
      throw Exception('API key is empty for config "${config.key}".');
    }

    // Build endpoint: strip trailing slash, append /images/generations
    final baseUrl = config.baseUrl.endsWith('/')
        ? config.baseUrl.substring(0, config.baseUrl.length - 1)
        : config.baseUrl;
    final endpoint = '$baseUrl/images/generations';

    // Check cache
    final cacheKey = ImageGenCache.cacheKey(
      prompt: request.prompt,
      provider: 'openai_compat',
      model: config.modelId,
      size: request.size,
      style: request.style,
    );
    final cached = await ImageGenCache.lookup(cacheKey);
    if (cached != null) {
      debugPrint('[ImageGen] OpenAICompat cache HIT key=$cacheKey');
      final bytes = await _readBytes(cached);
      return ImageGenerationResult(
        images: [bytes],
        providerModel: config.modelId,
      );
    }

    debugPrint('[ImageGen] OpenAICompat: POST $endpoint model=${config.modelId}');
    final body = {
      'model': config.modelId,
      'prompt': request.prompt,
      'size': request.size,
      'n': request.numImages,
      'response_format': 'url',
    };

    final response = await _dio.post(
      endpoint,
      options: Options(headers: {
        'Authorization': 'Bearer ${config.apiKey}',
        'Content-Type': 'application/json',
      }),
      data: jsonEncode(body),
    );

    final data = response.data as Map<String, dynamic>;
    final dataList = data['data'] as List?;
    if (dataList == null || dataList.isEmpty) {
      throw Exception('No images returned. Response: ${jsonEncode(data)}');
    }

    final images = <Uint8List>[];
    for (final item in dataList) {
      final url = (item as Map<String, dynamic>)['url'] as String?;
      final b64 = item['b64_json'] as String?;
      if (url != null) {
        debugPrint('[ImageGen] OpenAICompat downloading from URL: ${url.substring(0, 80)}...');
        final resp = await _dio.get(
          url,
          options: Options(responseType: ResponseType.bytes),
        );
        images.add(Uint8List.fromList(resp.data as List<int>));
      } else if (b64 != null) {
        debugPrint('[ImageGen] OpenAICompat decoding base64 (${b64.length} chars)');
        images.add(base64Decode(b64));
      }
    }

    if (images.isEmpty) {
      throw Exception('Failed to extract images from response.');
    }

    debugPrint('[ImageGen] OpenAICompat success: ${images.length} image(s), ${images.first.length} bytes each');
    for (final img in images) {
      try {
        await ImageGenCache.store(cacheKey, img);
      } catch (e) {
        debugPrint('[ImageGen] OpenAICompat cache store failed (non-fatal): $e');
      }
    }

    return ImageGenerationResult(
      images: images,
      providerModel: config.modelId,
    );
  }

  static Future<Uint8List> _readBytes(String path) async {
    return Uint8List.sublistView(await File(path).readAsBytes());
  }
}
