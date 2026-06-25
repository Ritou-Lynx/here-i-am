import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:memex/data/services/image_gen/image_gen_cache.dart';
import 'package:memex/data/services/image_gen/image_gen_provider.dart';
import 'package:memex/utils/user_storage.dart';

/// Image generation via Aliyun DashScope / Tongyi Wanxiang (通义万相).
class TongyiWanxiangImageService {
  TongyiWanxiangImageService._();

  static const _baseUrl =
      'https://dashscope.aliyuncs.com/api/v1/services/aigc/multimodal-generation/generation';
  static const _model = 'wan2.1-t2i-turbo';
  static const _timeout = Duration(seconds: 45);

  static final _dio = Dio(BaseOptions(
    connectTimeout: _timeout,
    receiveTimeout: _timeout,
  ));

  static String _enrichedPrompt(ImageGenerationRequest request) {
    final prompt = request.prompt;
    final style = request.style?.trim();
    if (style == null || style.isEmpty) return prompt;

    final lower = style.toLowerCase();
    if (lower.contains('photoreal') || lower.contains('写实')) {
      return '$prompt, photorealistic, highly detailed, professional photography';
    }
    if (lower.contains('anime') || lower.contains('二次元') || lower.contains('动漫')) {
      return '$prompt, anime style, clean lines, vibrant colors, illustration';
    }
    if (lower.contains('watercolor') || lower.contains('水彩')) {
      return '$prompt, watercolor painting, soft edges, artistic, on paper';
    }
    if (lower.contains('oil') || lower.contains('油画')) {
      return '$prompt, oil painting, canvas texture, classical fine art';
    }
    return '$prompt, $style style';
  }

  /// Returns an error string on failure, or the image bytes on success.
  static Future<ImageGenerationResult> generate(
    ImageGenerationRequest request,
  ) async {
    // 1. API key from existing Qwen LLM config
    final apiKey = await UserStorage.getDashScopeApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      throw Exception(
        'No DashScope API key found. '
        'Please configure a Qwen (通义千问) model in Settings with your Aliyun API key.',
      );
    }

    // 2. Check cache
    final key = ImageGenCache.cacheKey(
      prompt: request.prompt,
      provider: 'tongyi_wanxiang',
      model: _model,
      size: request.size,
      style: request.style,
    );
    final cached = await ImageGenCache.lookup(key);
    if (cached != null) {
      final file = await File(cached).readAsBytes();
      return ImageGenerationResult(
        images: [Uint8List.sublistView(file)],
        providerModel: _model,
      );
    }

    // 3. Call API
    final sizeParam = request.size.replaceAll('x', '*');
    final body = {
      'model': _model,
      'input': {'prompt': _enrichedPrompt(request)},
      'parameters': {
        'size': sizeParam,
        'n': request.numImages,
      },
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
    final output = data['output'];
    if (output == null) {
      final code = data['code'] ?? 'unknown';
      final message = data['message'] ?? 'No output returned';
      throw Exception('DashScope error [$code]: $message');
    }

    // 4. Download results
    final results = output['results'] as List?;
    if (results == null || results.isEmpty) {
      throw Exception('DashScope returned no images');
    }

    final images = <Uint8List>[];
    for (final result in results) {
      final url = result['url'] as String?;
      if (url == null) continue;
      final imgResp = await _dio.get(
        url,
        options: Options(responseType: ResponseType.bytes),
      );
      images.add(Uint8List.fromList(imgResp.data as List<int>));
    }

    if (images.isEmpty) {
      throw Exception('Failed to download generated images');
    }

    // 5. Cache (best-effort) & return
    for (final img in images) {
      try {
        await ImageGenCache.store(key, img);
      } catch (e) {
        debugPrint('[ImageGen] Tongyi cache store failed (non-fatal): $e');
      }
    }
    return ImageGenerationResult(
      images: images,
      providerModel: _model,
    );
  }
}
